---
topic: adr-018
updated_at: 2026-05-05
status: accepted
decision_date: 2026-05-05
supersedes: none
related:
  - decisions/ADR-004-rls-requires-bin-db-init.md
  - decisions/ADR-014-rls-policy-generator.md
  - decisions/ADR-016-lint-schema-consistency.md
  - conventions/counter-column.md
---

# ADR-018 Counter 字段（`*_count`）与 RLS 的不兼容 + 快照表范式

## Status
✅ **Accepted** — 2026-05-05

## Context

rlbox 模板自 [ADR-004](ADR-004-rls-requires-bin-db-init.md) 起对所有业务表开启 Row-Level Security
并通过 `bin/db_init` + [ADR-014](ADR-014-rls-policy-generator.md) 生成的默认 4-op policy 实施
data-version 隔离。默认 UPDATE policy：

```sql
USING (data_version <> '0'
       AND data_version = current_setting('app.data_version', true))
```

意思是："session 只能 UPDATE 自己 data_version 下的记录，baseline（`'0'`）永远锁死。"

这个策略保证了多 session 并发训练下 baseline 不被污染，是 rlbox 的核心隔离假设。

但模板默认 RLS **和 Rails 约定俗成的几种"写入型 counter"路径彻底互斥**，
在派生项目里反复以 silent-fail 方式咬人：

1. **`counter_cache`**：`belongs_to :post, counter_cache: true` → Like 创建时 Rails 发
   `UPDATE posts SET likes_count = likes_count + 1 WHERE id = ?`，baseline post 永远匹配不上 policy，
   `likes_count` 永远是 0。
2. **手写 `increment!` / `decrement!` / `update_counters`**：同样走 UPDATE 路径，同样 silent fail。
3. **`touch: true` 级联**：同样是 UPDATE，baseline 记录 updated_at 死字段。

**为什么 silent fail 特别坏**：
- `.increment!` 返回 `true`（UPDATE 0 也是"成功"执行）
- 没有 RLS 异常抛出
- counter 从用户视角看"数字就是没变"，难以归因
- baseline 跑 `SELECT` 时 policy 放行，数据看起来正常

这类坑在至少 3 个 fork 各自独立踩过：
- **IdleSwap**：`posts.likes_count`、`posts.views_count`
- **duvy**：`comment_likes.likes_count` (CommentLike counter_cache)、`users.followers_count/following_count`
- **Kangoo**：`products.sales_count`（早期）

fork 各自建了本地的 "ADR-012 counter-column ban"。现在把它升格到 rlbox 模板，
让后续派生项目 day-one 就知道这条禁令。

## Decision

**rlbox 模板规定**（业务表，即所有带 `data_version` 列的表）：

### 1. 禁止 counter_cache
```ruby
# ❌ 禁止
class Like < ApplicationRecord
  belongs_to :post, counter_cache: true
end

# ✅ 允许
class Like < ApplicationRecord
  belongs_to :post
end
```

### 2. 禁止手写 counter UPDATE
```ruby
# ❌ 禁止
@post.increment!(:views_count)
User.increment_counter(:followers_count, user.id)
post.update_columns(likes_count: n)

# ✅ 允许（视图层 .count）
<%= post.likes.count %> 个赞
```

### 3. 禁止在业务表 schema 里建 `*_count` 列
```ruby
# ❌ 禁止（字段存在 = 诱导后续代码去 UPDATE 它）
create_table :posts do |t|
  t.integer :likes_count, default: 0
end

# ✅ 允许
create_table :posts do |t|
  # 不加 likes_count，视图层用 post.likes.count
end
```

### 4. 高并发/排序/缓存场景 → 快照表范式 (Snapshot Table Pattern)

若真有性能需求（上万 baseline 数据 + 视图 `.count` 拖垮首页）：

<a id="snapshot-table-pattern"></a>
**范式**：把 counter 拆出来放独立"快照表"，用 split-by-operation RLS policy 允许 session INSERT
baseline 的 delta，但**仍禁止 UPDATE baseline 本身**。

**样板**（Kangoo 的 `product_inventory_snapshots` 是生态范本，见下面 "Kangoo Snapshot Table Pattern"）：

```ruby
# db/migrate/xxxxx_create_product_inventory_snapshots.rb
create_table :product_inventory_snapshots do |t|
  t.references :product, null: false
  t.integer :sales_delta, default: 0, null: false  # 正数 = 卖出，负数 = 退款
  t.string :data_version, default: '0', null: false, limit: 50
  t.index :data_version
  t.timestamps
end

# RLS: 4 条 policy 覆盖不同 op
execute <<~SQL
  ALTER TABLE product_inventory_snapshots ENABLE ROW LEVEL SECURITY;

  -- SELECT: 看 baseline + 自己的 session delta
  CREATE POLICY snapshots_select_policy ON product_inventory_snapshots FOR SELECT
    USING (data_version = '0' OR data_version = current_setting('app.data_version', true));

  -- INSERT: session 只能插自己的 data_version（baseline 由 data_pack 独立塞，绕过 RLS）
  CREATE POLICY snapshots_insert_policy ON product_inventory_snapshots FOR INSERT
    WITH CHECK (data_version = current_setting('app.data_version', true));

  -- UPDATE: 禁止——快照表是 append-only
  -- DELETE: session 只能删自己的（session reset 用）
  CREATE POLICY snapshots_delete_policy ON product_inventory_snapshots FOR DELETE
    USING (data_version = current_setting('app.data_version', true));
SQL
```

读取时合计：

```ruby
class Product < ApplicationRecord
  has_many :inventory_snapshots, class_name: 'ProductInventorySnapshot'

  # baseline 累计（data pack 预先塞的历史销量）+ 当前 session 的 delta
  def effective_sales_count
    baseline = self.class.baseline_sales_count_for(id)          # 缓存的 data_pack 合计
    session_delta = inventory_snapshots
                      .where(data_version: session_data_version)
                      .sum(:sales_delta)
    baseline + session_delta
  end

  def apply_inventory_delta!(delta)
    inventory_snapshots.create!(
      sales_delta: delta,
      data_version: session_data_version
    )
  end
end
```

这个范式同时满足：
- ✅ RLS 不拦（INSERT-only，baseline 由 data_pack 在 RLS 旁路塞）
- ✅ 多 session 隔离（每 session 看到 baseline + 自己的 delta）
- ✅ 可排序（`effective_sales_count` 可参与 ORDER BY，或物化视图）
- ✅ session reset 干净（只删自己的 snapshot）

## Consequences

### Positive
- 从 day-one 消除 counter_cache silent-fail 这类最常见的 RLS 隐雷
- 派生项目不再各自摸索 / 踩坑 / 各立 ADR-012
- 快照表范式可直接复用（未来可做 `rails g snapshot_counter` 生成器）

### Negative
- 现有 fork 里遗留的 `*_count` 字段需要单独清理（Kangoo、IdleSwap、duvy 已完成）
- 开发者得记住"要显示数量？用 `.count`"而不是"存个字段"
- 高性能场景要写快照表，比 counter_cache 重，得评估真实需要

### Neutral
- 系统表（`data_version_excluded!` 的 Session / Administrator / ActiveStorage::Blob 等）不受此约束
- 此 ADR 不推翻 Rails 其他并发语义，只针对 RLS 隔离下的 counter 写入

## Implementation

### 文档
- [conventions/counter-column.md](../conventions/counter-column.md) — 使用者手册 / 四部曲
- 此 ADR — 架构层决策记录

### 静态检测（已部署）
- `rake validator:lint_schema`（[ADR-016](ADR-016-lint-schema-consistency.md)）未来会增加"`belongs_to ... counter_cache: true` on data-versioned table"告警

### 生成器（未来）
- `rails g snapshot_counter products sales_delta:integer` — 一键生成快照表 + 4 op RLS policy + model 样板
  （[B2 待规划]，若需求频繁再做）

### Kangoo Snapshot Table Pattern（生态范本）
- `app/models/product_inventory_snapshot.rb` + `db/migrate/20260505021038_create_product_inventory_snapshots.rb`
- `Product#apply_inventory_delta!` (`app/models/product.rb:140-155`)
- `Order#pay!` / `Order#cancel!` 调用 `apply_inventory_delta!`
- `Shop#baseline_sales_count` + `Product#baseline_sales_count_for(relation)` helper

## Historical Context

### fork 侧早期 ADR-012 条款

在 rlbox 形式化这条规则之前，多个 fork 各自建了本地 ADR-012：

- **IdleSwap** `ADR-012-counter-column-ban.md`：禁 `posts.likes_count` / `views_count`
- **duvy** `ADR-016-counter-column-ban.md`（同思路不同编号）：禁 `comment_likes.likes_count` / `users.followers_count`

这些本地 ADR 作为 rlbox ADR-018 的前置实践，**保留不动**（历史记录），
但后续新 fork 继承 rlbox ADR-018 后不必再各自建一份。

### 相关 commits（仅记录、不要模仿）
| 项目 | Commit | 场景 |
|---|---|---|
| IdleSwap | `44287d8` | 视图层 `.count` 替代 `posts.likes_count` |
| IdleSwap | `6e951bf` | drop `posts.views_count` 列 + 删 `increment!` |
| duvy | `2218cc0` | CommentLike 去 counter_cache |
| duvy | `9a090b1` | drop `users.followers_count` / `following_count` |
