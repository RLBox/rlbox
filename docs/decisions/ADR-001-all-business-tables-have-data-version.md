---
topic: adr-001
updated_at: 2026-04-28
status: accepted
decision_date: 2026-04-28
supersedes: none
---

# ADR-001 所有业务表都必须有 data_version 列

## Status
✅ **Accepted** — 2026-04-28

## Context

rlbox 是 Agent 评测沙盒（见 [architecture/agent-sandbox.md](../architecture/agent-sandbox.md)）。核心诉求是：

> 每次评测后，环境能一键回到 baseline，供下一次评测使用。

实现手段是 `data_version` 软隔离：
- `data_version='0'` 的记录是永不删除的 baseline
- `data_version≠'0'` 的记录在 rollback 时 `DELETE`

早期曾把某些表看作"参考数据 / 字典表"，不加 `data_version` 列，改用三件套在代码层排除：
```ruby
data_version_excluded!
default_scope { unscope(where: :data_version) }
skip_callback :create, :before, :set_data_version
```

**典型受害者：Category**。被当成"商品分类字典"排除。

## Problem

如果 Agent 任务是：
- 「新建一个分类叫『限时特惠』」→ Agent 会 `Category.create!(name: '限时特惠')`
- 因为 Category 没有 data_version 列，这条记录**永久写入 baseline**
- `rake validator:reset_baseline` 无法清除它
- **下一次评测时，baseline 已被污染**，所有后续测试结果不可信

实际上任何 Agent 能 CREATE/UPDATE/DELETE 的表，都面临同样风险。

## Decision

**所有业务表必须有 `data_version` 列**，定义如下：
```ruby
t.string :data_version, null: false, default: '0', limit: 50
t.index  :data_version
```

**"业务表"的判断准则**（见 [ADR-003](ADR-003-business-vs-system-tables.md)）：
> 如果能出一道题让 Agent 新建/修改/删除这张表的记录，它就是业务表。

## Consequences

### Positive
- Rollback 完全可靠：一条 SQL 清干净所有会话数据
- 规则**唯一**：不再区分"真业务表"和"准字典表"，简化心智

### Negative
- 所有业务表多一列（50 字节级别，代价可忽略）

### Neutral
- 系统表仍可用三件套排除。见 [ADR-003](ADR-003-business-vs-system-tables.md)。

## Implementation
- 生成器 `rails g model` / `rails g models` 自动加 data_version 列
- `CLAUDE.md` 里明文禁止「业务表用三件套」
- ValidatorLinter 静态检测漏过滤（见 [validator-linter.md](../architecture/validator-linter.md)）
- `rake docs:lint` 扫描 `app/models/**/*.rb` 是否有业务表用三件套
