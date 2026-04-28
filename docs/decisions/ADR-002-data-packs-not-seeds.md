---
topic: adr-002
updated_at: 2026-04-28
status: accepted
decision_date: 2026-04-28
---

# ADR-002 Baseline 数据只通过 `data_packs/v1/` 加载，`db/seeds.rb` 不作入口

## Status
✅ **Accepted** — 2026-04-28

## Context

Rails 传统做法是用 `db/seeds.rb` 加初始数据。我们最初也这样做，结果出现几类问题：

1. `db/seeds.rb` 成为"大杂烩"，几百行数据混在一起
2. 新人容易忘写 `data_version: '0'`
3. 不是幂等的——多次运行会主键冲突
4. Agent 会话结束后无法选择性清理（所有 seeds 数据都没有版本标签）

## Decision

- **Baseline 数据只走 `app/validators/support/data_packs/v1/`**
- `db/seeds.rb` 只保留一行注释，指向 `data_packs/`
- 加载命令：`rake validator:reset_baseline`（幂等，可反复执行）

## Consequences

### Positive
- 幂等：`base.rb` 先清理，各模块 `insert_all` 不会冲突
- 自动版本标注：rake 任务执行时已 `SET SESSION app.data_version = '0'`，所有插入自动落 baseline
- 模块化：每业务一文件，按字母序加载，FK 顺序可控

### Negative
- 需要运行 `rake validator:reset_baseline` 而不是 `rails db:seed`（习惯成本）

## Implementation
- `lib/tasks/validator.rake` 实现 `reset_baseline` 任务
- 详见 [architecture/data-packs.md](../architecture/data-packs.md)
