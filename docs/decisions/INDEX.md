---
topic: adr-index
updated_at: 2026-04-28
---

# Architecture Decision Records (ADR) 索引

> ADR 记录架构决策的历史——**为什么**这样做，而不是只记录"做了什么"。
> ADR 一旦 Accepted，不可修改内容（只可标记 Superseded）。

## 已接受的 ADR

| ADR | 标题 | 状态 | 日期 |
|---|---|---|---|
| [ADR-001](ADR-001-all-business-tables-have-data-version.md) | 所有业务表都必须有 data_version 列 | ✅ Accepted | 2026-04-28 |
| [ADR-002](ADR-002-data-packs-not-seeds.md) | Baseline 数据只通过 data_packs/v1/ 加载 | ✅ Accepted | 2026-04-28 |
| [ADR-003](ADR-003-business-vs-system-tables.md) | 业务表 vs 系统表的判断准则 | ✅ Accepted | 2026-04-28 |
| [ADR-004](ADR-004-rls-requires-bin-db-init.md) | RLS 初始化必须走 bin/db_init | ✅ Accepted | 2026-04-28 |
| [ADR-005](ADR-005-validator-seed-hook.md) | 引入 `seed` 钩子承载题目私有预制数据 | ✅ Accepted | 2026-04-28 |
| [ADR-006](ADR-006-validators-namespaced-root.md) | Validators 挂到命名空间根，避免与业务模型撞车 | ✅ Accepted | 2026-04-28 |
| [ADR-007](ADR-007-verify-cross-request-isolation.md) | Validator 执行状态默认不跨请求持久化（verify 用独立实例） | ✅ Accepted | 2026-04-28 |

## 新建 ADR 模板

```markdown
---
topic: adr-NNN
updated_at: YYYY-MM-DD
status: accepted
decision_date: YYYY-MM-DD
supersedes: none  # 或 ADR-XXX
related:
  - decisions/ADR-XXX-...
---

# ADR-NNN 标题

## Status
✅ **Accepted** — YYYY-MM-DD

## Context
[为什么需要这个决策？当时面临什么问题？]

## Decision
[决定怎么做]

## Consequences
### Positive
### Negative
### Neutral

## Implementation
[关键文件、rake task、生成器等]
```

## 何时开新 ADR

| 情况 | 去哪里 |
|---|---|
| 小改字段/修 bug | 只更新 entity page 或 conventions/ |
| 引入新模式（命名、流程） | 更新 conventions/ |
| **改变基本假设（数据流、隔离策略、架构层级）** | **必开 ADR** |
| 一次性历史修复 | `docs/archive/` |
