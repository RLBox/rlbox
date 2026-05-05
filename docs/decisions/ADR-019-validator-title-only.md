---
topic: adr-019-validator-title-only
status: Accepted
date: 2026-05-05
updated_at: 2026-05-05
related:
  - conventions/validator-writing.md
  - architecture/validator-linter.md
---

# ADR-019: Validator 只写 title，description 字段彻底移除

- **Status**: Accepted

## Context

Validator 元数据历史上有两个文案字段：

- `self.title` — 给人看的任务名，例如"在「30 天·品质好物档」里只完成「每日签到」任务领话费券"
- `self.description` — 补充描述，早期被用作"给 agent/LLM 看的断言提示"

两个字段共存造成了三个工程问题：

1. **对外交付维度从不消费 description**。甲方 android_sandbox 通过 `/api/tasks` 拉元数据生成 Task 文件，`sengclaw/generate_tasks.py` 只读 `task_meta["title"]` + `task_meta["task_id"]`。从未读 description。
2. **Admin 视觉污染**。任务详情页 `<h1><%= title %></h1>` 紧跟 `<p><%= description %></p>`，内容重复 / 用内部术语重述 title，给非开发者看是噪音。
3. **断言提示应由 `@assertions` 区承载**。verify 方法里的 `assert_*` 调用本身就是权威断言，admin show 页已有专门的 `@assertions` 面板展示解析后的清单，不需要 description 再用自然语言重述一次。

**openclacky 生态跨项目调研结果**（2026-05-05）：

| 项目 | self.description 次数 | BaseValidator 字段 | controller/view 渲染 |
|---|---|---|---|
| rlbox（template） | 0 | ❌ 已删 | ✅ 僵尸代码 |
| Goomart | 0 | ✅ 还在 | ✅ 还在 |
| IdleSwap | 0 | ❌ 已删 | ❌ 已删 ← 最彻底 |
| Kangoo | 0 | ❌ 已删 | ✅ 僵尸代码 |
| planet | 0 | ✅ 还在 | ✅ 还在 |
| duvy | 0（刚清理） | ✅ 还在 | ✅ 还在 |

**没有任何一个生态项目真正在 validator 层使用 description 承载独立信息**。IdleSwap 已经证明"彻底拔掉"路径可行。

duvy 的 [ADR-019（fork 本地版本）](../../../duvy/docs/decisions/ADR-019-validator-title-only-drop-description.md) 当时选择了"保留兼容字段、仅约定不写"的保守策略。实践反馈：**约定不足以防 AI 犯傻** — 新 validator 仍有可能被 copy-paste 回老 DSL。本 ADR 作为 template 层的最终决策，采用更彻底的方案。

## Decision

**彻底移除 validator 的 `description` 字段，并通过 linter 硬拦截。**

具体要求：

1. **BaseValidator**：移除 `attr_accessor :description`（本仓库 rlbox 此前已做到）。`metadata` 方法里不返回 `description:` key。
2. **Controller / View**：删除 `admin/validation_tasks_controller.rb` 的 description 搜索分支；删除 `show.html.erb` / `index.html.erb` 的 `<%= @task[:description] %>` / `<%= task[:description] %>` 渲染（本 ADR 落地时完成）。
3. **新建 validator**：类定义里只出现 `self.validator_id` / `self.title` / `self.timeout_seconds`，**禁止** `self.description = ...`。
4. **Linter 护栏**（关键）：`rake validator:lint` 新增第五类检查 `deprecated_fields`，默认配置扫描 `self\.description\s*=` 模式，severity HIGH，**无需外部配置文件就生效**。这是防御 AI agent 从记忆里 copy-paste 老 DSL 的唯一硬保障。
5. **任务细节**：如果 agent prompt 需要比 title 更多的细节，走 `prepare` 返回的 `{ task:, hint: }` — `hint` 是运行时字段，边界清晰。

## Consequences

**正面**：

- Admin 详情页视觉清爽，只剩 title，与 IdleSwap 基线对齐。
- `rake validator:lint` 静态拦截老 DSL，**代码级防御 > 文档级约定**。
- 消除 "title 和 description 内容冗余、哪个权威" 的歧义。
- 甲方脚本行为不变（它本来就不读 description）。
- 从 rlbox fork 出的新项目自动拿到正解，不会继承 description 习惯。

**负面 / 代价**：

- 派生项目（Goomart / planet / duvy / Kangoo）需要跟进同步（已在本次会话批量完成）。
- 后续 fork-to-template 同步时，派生项目若从上游拉 description 相关代码，会因 linter 规则失败 — 这是预期行为。

## Alternatives Considered

1. **保留 BaseValidator 字段 + 仅约定不写**（duvy ADR-019 选择） — 拒绝。约定不足以防 AI 犯傻，下次会话很可能复发。
2. **只删 BaseValidator，保留 controller/view 僵尸引用**（Kangoo 现状） — 拒绝。代码里残留 `t[:description]` 会误导新开发者以为字段仍可用。
3. **把 description 改名为 internal_notes，只给 debug 用** — 拒绝。和 `prepare#hint` 职责重叠。

## Implementation Note (2026-05-05)

- rlbox 清理了 `admin/validation_tasks_controller.rb` + `show.html.erb` + `index.html.erb` 的 description 引用。
- `lib/validator_linter.rb` 新增第五类检查 `deprecated_fields`，内置默认规则 `self.description =`（HIGH），无需 `config/validator_lint_rules.yml` 即可生效。
- 同步 Goomart / planet / duvy / Kangoo 四个派生项目；IdleSwap 已提前完成，无需动。
- 同步更新 `docs/conventions/validator-writing.md` 与 `docs/architecture/validator-linter.md`。
