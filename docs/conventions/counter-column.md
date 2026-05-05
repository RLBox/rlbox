---
topic: counter-column
updated_at: 2026-05-05
related:
  - architecture/data-version.md
  - decisions/ADR-004-rls-requires-bin-db-init.md
  - decisions/ADR-014-rls-policy-generator.md
  - decisions/ADR-018-counter-column-and-rls.md
---

# 🚫 Counter 字段（`*_count`）与 RLS 的兼容性

> **结论先行**：在 RLS（Row-Level Security，见 [ADR-004](../decisions/ADR-004-rls-requires-bin-db-init.md)）下，
> **业务表上所有 `*_count` 字段都是陷阱**。Rails 的 `counter_cache` 和手写的 `increment!` / `decrement!`
> 都会在 baseline 记录上 **silent fail**——SQL 返回 `UPDATE 0`，Rails 返回 `true`，没人报错，数字永远停在 0。
>
> **正确做法**：别存 counter，需要时视图层 `relation.count` 现算（baseline 合计 + session delta）。

## 为什么会 silent fail？

RLS 的 `UPDATE` policy 长这样（ADR-014 生成器默认模板）：

```sql
CREATE POLICY posts_update_policy ON public.posts FOR UPDATE
  USING (data_version <> '0'
         AND data_version = current_setting('app.data_version', true));
```

语义："只有当这条记录的 `data_version` 匹配当前 session 的 data_version **且不是 baseline ('0')**，
才允许 UPDATE。"

问题：baseline 记录（`data_version = '0'`）永远不满足 `<> '0'`，
于是 **任何尝试 UPDATE baseline 记录的 SQL 都会被 policy 静默丢弃**（0 rows affected，不抛错）。

| 触发路径 | 结果 |
|---|---|
| `@post.increment!(:views_count)` | `UPDATE posts SET views_count=... WHERE id=...` → 0 rows affected，counter 停在 0 |
| `belongs_to :post, counter_cache: true`（Like 创建时） | 同上，Like 行插入成功但 posts.likes_count 不动 |
| `belongs_to :user, counter_cache: :followers_count`（Follow 创建时） | 同上，users.followers_count 死 |

三条路径全都走 `UPDATE counter_table SET count_col = count_col ± 1`，全部在 baseline 上失效。

## 四部曲解决方案

一次性把这类问题解决干净：

### 第 1 步：不要在 schema 里建 counter 列

建新业务表时：

```ruby
# ❌ 错：字段会诱导后续代码去 increment!
bin/rails g model Post title:string likes_count:integer:default=0

# ✅ 对：根本不建 counter 字段
bin/rails g model Post title:string
```

如果业务逻辑真的"很想"显示数量，走 **视图层计算**（见第 4 步）。

### 第 2 步：不要声明 `counter_cache`

```ruby
# ❌ 错：Rails 会生成 UPDATE posts SET likes_count = likes_count + 1，
#    在 baseline post 上 silent fail
class Like < ApplicationRecord
  belongs_to :post, counter_cache: true
end

# ✅ 对：干净的 belongs_to，数字交给视图层
class Like < ApplicationRecord
  belongs_to :post
end
```

### 第 3 步：不要手写 `increment!` / `decrement!` / `update_counters`

```ruby
# ❌ 错：和 counter_cache 一样的 UPDATE 语义，同样被 RLS 拦截
def show
  @post = Post.find(params[:id])
  @post.increment!(:views_count)   # baseline post → silent fail
end

# ✅ 对：直接不记数，或用独立表插入（INSERT 不受 UPDATE policy 约束）
def show
  @post = Post.find(params[:id])
  # 可选：记录真实访问到独立表
  PostView.create!(post: @post, user: Current.user, viewed_at: Time.current)
end
```

**关键洞察**：RLS 拦的是 **UPDATE on baseline**。`INSERT` 受 `WITH CHECK` 约束，但
session-scope INSERT 都带 `data_version = current_setting('app.data_version')`
所以是合法的。独立的"事件表"（PostView / Like / Follow） **本质就是 INSERT-only 的**，
天然绕过这个坑。

### 第 4 步：视图层现算数量

```erb
<!-- ❌ 错：读死字段，永远 0 -->
<%= post.likes_count %> 个赞

<!-- ✅ 对：用关联 .count，baseline Like + session Like 自然合计 -->
<%= post.likes.count %> 个赞
```

Rails 的 `.count` 发 `SELECT COUNT(*)`，不走 UPDATE，不受 policy 约束。
RLS 的 `SELECT` policy 对 baseline 和 session 数据都放行，所以读取得到的是两种数据的并集——
这正是用户应该看到的数字。

若 N+1 担心，用 `counter_cache: false`（只禁 counter，不禁 `.count`）+ eager loading，
或改走 `has_many :likes, counter_cache: :likes_count_cache`（若真想走 counter，就得改 RLS policy，
这种场景下见 [ADR-018](../decisions/ADR-018-counter-column-and-rls.md) 权衡分析）。

## 速查：这些字段名见了就警惕

|字段名模式 | 检查动作 |
|---|---|
| `*_count` (views_count / likes_count / followers_count / comments_count / sold_count …) | `grep` 看有没有 `counter_cache` 或 `increment!`，有就改 |
| `*_total` / `*_sum` | 同上逻辑 |
| `last_*_at` 缓存型时间戳 | 同上（`update_columns` 也在 UPDATE 路径上） |

`rake validator:lint_schema`（ADR-016）已内建部分检测；**但不替代人肉 review**——
遇到新加字段，问一句"这字段会被 UPDATE 吗？如果是 UPDATE baseline 会怎样？"。

## 合法豁免：系统表

系统表（`ActiveStorage::*` / `Session` / `Administrator` / `ValidatorExecution` 等，
见 [ADR-003](../decisions/ADR-003-business-vs-system-tables.md)）**不开 RLS**，
counter 字段随便用。但业务表——`data_version` 列在身——就得守这条规矩。

## 涉及本规约的历史修复（仅记录，不要模仿）

| 项目 | Commit | 场景 |
|---|---|---|
| IdleSwap | `44287d8` | `posts.likes_count` 通过视图层 `post.likes.count` 现算 |
| IdleSwap | `6e951bf` | drop `posts.views_count` 列 + 删 `increment!` 调用 |
| duvy | `2218cc0` | `comment_likes` counter_cache 去除 |
| duvy | `9a090b1` | drop `users.followers_count` / `users.following_count` 列 |
| Kangoo | 多笔（见 [decisions/ADR-018](../decisions/ADR-018-counter-column-and-rls.md#kangoo-snapshot-table-pattern)） | 销量迁移到独立 `product_inventory_snapshots` 表 |

这些 fork 各自的 ADR-012（counter-column ban）是本 convention 的先导实践，
rlbox 这边正式化成模板规约。

## 下一步：新业务怎么办？

- **读计数，低并发**：视图层 `.count` 就够，别存。
- **读计数，高并发 / 要排序 / 要缓存**：用独立快照表（split-by-operation RLS policy 允许 INSERT baseline delta）。范式见 [decisions/ADR-018](../decisions/ADR-018-counter-column-and-rls.md#snapshot-table-pattern)。
- **真要 counter_cache**：改 RLS UPDATE policy 让 baseline 可被覆写——**一般别这么干**，因为 baseline 是公共数据，一 session 污染，所有 session 遭殃。
