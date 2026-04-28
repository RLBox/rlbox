---
topic: adr-007
updated_at: 2026-04-28
status: accepted
decision_date: 2026-04-28
related:
  - decisions/ADR-005-validator-seed-hook.md
  - decisions/ADR-006-validators-namespaced-root.md
  - architecture/validator-system.md
  - conventions/validator-writing.md
---

# ADR-007 Validator 执行状态默认不跨请求持久化（verify 用独立实例）

## Status
✅ **Accepted** — 2026-04-28

## Context

Validator 有四个运行阶段：`seed → prepare → simulate → verify`。在生产环境，它们跨**两次独立 HTTP 请求**：

```
POST /tasks/:id/prepare   → new Validator + seed + prepare  → 进程结束
[Agent 在浏览器做动作]                                      → DB 变化
POST /tasks/:id/verify    → new Validator + verify          → 进程结束
```

两次请求是**两个不同的 validator 实例**。只有显式写进数据库 `validator_executions.state` 的数据（由 `execution_state_data` / `restore_from_state` 约定）才会被 verify 实例恢复。框架默认只持久化 `@data_version`。

### 事故根因（"单机绿、浏览器红"）

在这个决策之前，自动化测试 `execute_simulate` 的实现是：

```ruby
# 旧版 execute_simulate
def execute_simulate
  execute_prepare      # 同一个 self 实例
  simulate             # 同一个 self 实例
  execute_verify       # 同一个 self 实例 —— @user/@product 全在
end
```

这个 pipeline 在**同一个实例上**跑三个阶段，`prepare` 里设置的 `@user`、`@product` 等 ivar 在 verify 阶段仍然存在。结果：

- 本地/CI 跑 `rake validator:simulate` 全绿 ✅
- 真实浏览器 + Agent 场景全红 ❌（`@user = nil`，assertion 静默失败）

**根因**：旧版 `execute_simulate` 和生产行为不等价，测试通过不代表生产通过。

### 尝试过的方案

- **方案 A：prepare 结束后静态快照 diff 检测新增 ivar**。问题：
  - 会误判 `load_refs` memoize 模式
  - 需要维护 whitelist 白名单
  - 本质是"猜"——没有真正跑一遍生产行为
- **方案 B：行为级检测**——`execute_simulate` 里 verify 阶段新建实例、只从 `execution_state_data` 恢复。**最终选这个**。

## Decision

1. `BaseValidator#execute_simulate` 在 verify 阶段**新建一个 validator 实例**，通过 `@execution_id` + 数据库 `validator_executions.state` 恢复状态，然后调 `execute_verify`。

2. 基类默认 `execution_state_data` 只序列化 `@data_version`。子类**必须**按以下方式之一让 verify 独立工作：
   - **A. 局部变量**：prepare 用局部变量组装 hint 文案，不依赖跨阶段 ivar
   - **B. verify 重查**（推荐）：verify 里按 baseline 重新查 `User.find_by!(...)` 等引用
   - **C. `load_refs` 模式**（配合 seed 的 validator）：prepare / seed / verify / simulate 都调 `load_refs`，`return if @user` memoize
   - **D. 显式持久化**：覆盖 `execution_state_data` / `restore_from_state`

3. `ValidatorStateLeakError` 异常类保留，但框架不再自动抛（供 validator 显式 raise）。

### 关键代码（app/validators/base_validator.rb）

```ruby
def execute_simulate
  # ...
  execute_prepare                          # self 实例
  simulate                                 # self 实例
  verify_instance = self.class.new(@execution_id)  # 🔑 新实例
  result[:verify_result] = verify_instance.execute_verify
  # 同步断言结果回 self（便于调试）
  @assertions = verify_instance.assertions
  @errors     = verify_instance.errors
  @score      = verify_instance.score
  # ...
end
```

## Consequences

### 正面

- **单进程测试真实反映生产**。`rake validator:simulate` 绿 ⇒ 生产也绿。
- **verify 方法天然独立**，易读易重构。
- **不需要白名单**，框架零启发式，写错了 NoMethodError 直接暴露。
- **与 `load_refs` 模式天然兼容**，memoize 幂等，自然通过。

### 负面

- **新写 validator 需要注意 verify 独立性**（用 B/C/D 三种姿势之一）。
- **verify 里多一点查询开销**（重查 baseline 引用）。可忽略——只发生一次，且 baseline 查询极快。

## 验证

- `spec/validators/base_validator_leak_detection_spec.rb` — 行为级单元测试（LeakyTestValidator 会失败，LocalVarTestValidator / DeclaredTestValidator 会通过）
- `bundle exec rake test` 绿 → 框架级保证生效

## References

- [conventions/validator-writing.md §6](../conventions/validator-writing.md) — 三种合规姿势 + 快速自查
- [architecture/validator-system.md](../architecture/validator-system.md) — 生命周期说明
- [ADR-005](./ADR-005-validator-seed-hook.md) — seed 钩子（`load_refs` 模式的起点）
- `spec/validators/base_validator_leak_detection_spec.rb` — 行为级单元测试
