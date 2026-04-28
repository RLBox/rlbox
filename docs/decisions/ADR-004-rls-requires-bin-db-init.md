---
topic: adr-004
updated_at: 2026-04-28
status: accepted
decision_date: 2026-04-28
related:
  - decisions/ADR-001-all-business-tables-have-data-version.md
  - architecture/data-version.md
---

# ADR-004 RLS 初始化必须走 `bin/db_init`，不能纯靠 migration

## Status
✅ **Accepted** — 2026-04-28

## Context

ADR-001 确立「所有业务表有 `data_version` 列」；为防止 `.unscoped` 意外跨越 session 泄漏，加了一层 PostgreSQL RLS（Row-Level Security）作为数据库级防御。

RLS 要正常工作需要三件事同时成立：

1. **注册 GUC 参数**：`ALTER DATABASE ... SET app.data_version='0'`（需要 superuser）
2. **创建专属角色**：Rails 以 `app_user`（NOSUPERUSER）连库，不是 `postgres`（否则 superuser 绕过 RLS）
3. **表上的 RLS 策略**：`ENABLE + FORCE ROW LEVEL SECURITY + CREATE POLICY`（migration 跑，但需要 app_user 身份）

问题：**第 1 步需要 superuser 权限**，migration 以 app_user 身份跑会报 `PG::InsufficientPrivilege`。

## Decision

- **`bin/db_init`** 是 RLS 初始化的**唯一入口**
- 它以 superuser（`postgres`）身份执行第 1、2 步，再切到 `app_user` 执行 migration
- `bin/setup` 检测 `app_user` 是否存在：无则调 `bin/db_init`，有则调 `db:prepare`
- migration `..._configure_app_data_version_parameter.rb` 保留为 **no-op 占位**（不删，占版本号）

## Consequences

### Positive
- RLS 双保险真正生效（DB 层独立于应用层）
- 幂等：重跑 `bin/db_init` 只会校准偏差，不会炸

### Negative
- 新成员需要知道「不能只跑 `rails db:setup`」—— CLAUDE.md 硬规则已说明
- CI 需要有 superuser 权限的 PG 实例（Clacky 已满足）

## Implementation
- `bin/db_init` — 主入口
- `bin/setup` — 首次 clone 时调用
- 详见 [conventions/new-branch.md](../conventions/new-branch.md)
