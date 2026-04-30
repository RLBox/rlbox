---
topic: adr-010
updated_at: 2026-04-30
status: accepted
decision_date: 2026-04-30
related:
  - decisions/ADR-007-verify-cross-request-isolation.md
---


# ADR-010: CQRS 读写分离 — verify 与 cleanup 拆分为独立端点

## Status
Accepted (2026-04-30)

## Context
旧设计中 `execute_verify` 承担了两个职责：
1. **读**：验证用户操作结果、计算分数
2. **写**：清理 data_version 对应的所有业务数据

这个合并带来的问题：

### 问题 1：verify 不幂等 → Agent 多步评估一红到底
Android Agent 在 `eval_every_step=True` 模式下，每执行一步操作都会调 verify 验证当前状态。如果 verify 内部顺带执行了 `rollback_to_baseline`，第一次验证后数据被清空，第二次 verify 进来面对的是一片空库——**所有 assert 全挂，永远 0 分**。

### 问题 2：职责混淆 → API 语义不清
`POST /api/verify/run` 的名字暗示只做验证，实际上却在背后删数据。调用方不知道调用后数据还在不在，需要额外传 `cleanup:` 参数来控制行为，增加了心智负担。

### 问题 3：session 生命周期归属不明
`is_active=false` 原来被耦合在 verify 的成功/失败分支里。实际上 session 何时结束应该由外部控制（Agent runner 跑完一整轮 episode、用户关闭浏览器 tab），不应该由 verify 这个纯读操作来判定。

## Decision
采用 **CQRS（Command Query Responsibility Segregation）** 模式，将验证和清理拆分为两个独立端点：

| 端点 | HTTP 方法 | 职责 | 幂等性 |
|---|---|---|---|
| `/api/verify/run` | POST | 纯读验证（Query） | ✅ 可重复调用 |
| `/api/sessions/:session_id/cleanup` | POST | 数据清理（Command） | ✅ 宽松幂等 |

### 具体变更

1. **`execute_verify(cleanup: true)`** — 保留 `cleanup` 参数用于向后兼容（`execute_simulate` 内部调用链），但注释明确要求对外 HTTP API 必须传 `cleanup: false`。

2. **新增 `execute_cleanup`** — 独立的清理入口，职责单一：`rollback_to_baseline` + `cleanup_execution_state`，不打分不验证。

3. **新增 `POST /api/sessions/:session_id/cleanup`** — HTTP 端点，宽松幂等（state 已清/数据已空/session 已失活都返回 200）。

4. **`is_active=false` 不再由 verify 设置** — session 生命周期改由 `cleanup` 和 `remove_session` 管理。

## Consequences

### 正面
- verify 成为真正的纯读操作，Agent 多步评估不再崩
- API 语义清晰：一个端点做验证，另一个端点做清理
- session 生命周期可控：外部决定何时结束、何时清理
- 宽松幂等让调用方无需防御重复调用

### 负面
- 多了一个需要调用的端点（Agent runner 需要在任务结束时额外调 cleanup）
- `execute_simulate` 内部仍走 `cleanup: true` 老路径，两种调用路径需要分别理解
