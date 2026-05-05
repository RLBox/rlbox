---
topic: snapshot-table
updated_at: 2026-05-05
related:
  - conventions/counter-column.md
  - decisions/ADR-018-counter-column-and-rls.md
  - decisions/ADR-014-rls-policy-generator.md
  - architecture/data-version.md
---

# 📸 快照表范式（Snapshot Table Pattern）

> **何时使用**：业务需要一个**会被频繁 +1/-1** 的整数字段（库存、销量、访问数、点赞数…），
> **且** 不能接受视图层每次 `relation.count` 现算的性能代价。
>
> 默认场景下请先读 [counter-column.md](counter-column.md)——大部分 counter 只要视图层
> `relation.count` 就够了。只有当 **每次访问都要读这个数 + 数据规模确实大**，才升级到快照表。

## 为什么不能用 counter_cache？

见 [counter-column.md](counter-column.md) 和 [ADR-018](../decisions/ADR-018-counter-column-and-rls.md)：
RLS 的 UPDATE policy 会让 baseline 记录的 counter_cache / `increment!` **silent fail**，
`*_count` 列永远停在 0。

## 范式要点

快照表把"counter"从"对 baseline 记录做 UPDATE"改成"对快照表做 INSERT"，**绕开 RLS UPDATE 的 baseline 禁令**。

| 维度 | 传统 counter_cache | 快照表范式 |
|---|---|---|
| SQL 操作 | `UPDATE posts SET likes_count = likes_count + 1` | `INSERT INTO post_like_snapshots (post_id, delta, data_version) VALUES (...)` |
| RLS 拦截？ | ✅ 会 silent fail | ❌ 不会（INSERT policy 允许 session data_version） |
| Baseline 怎么来？ | 业务写入时 UPDATE（baseline 阶段做不到） | data_pack `insert_all` 装入基线总数 |
| 读取 | `post.likes_count` | `post.effective_likes_count`（baseline + session delta 合计） |
| Reset session | 无（baseline 被污染了也清不掉） | `DELETE FROM post_like_snapshots WHERE data_version = current_setting(...)` |

## 完整样板代码

**样板已收录在 [ADR-018 §Implementation](../decisions/ADR-018-counter-column-and-rls.md#implementation-guidance)**，
包含：

- Migration（带三段 RLS policy：SELECT 允许跨 session 读、INSERT 仅限 session data_version、
  DELETE 仅限 session data_version、**禁 UPDATE**——保证 append-only）
- Model（`effective_*_count` 方法、`apply_*_delta!(delta)` 方法）
- data_pack 加载 baseline 快照
- session reset 只删自己 snapshot 的清理策略

Kangoo 的 `product_inventory_snapshots` 是目前生产里的活体样板，
参考 migration：`20260505021038_create_product_inventory_snapshots.rb`（Kangoo 仓）。

## 何时 **不要** 用快照表

- 列表页只在详情页展示的 counter → 直接视图层 `.count`
- 后台统计报表 → 写 SQL query，不建列
- 管理员 dashboard → 同上

> 快照表是"性能兜底"，不是默认选择。**先 `.count` 现算，profiler 显示慢了再升级到快照表。**

## 未来工作

`rails g snapshot_counter <parent> <name>` generator 是开放 idea（ADR-018 § Future Work），
等真正有第二个 fork 需要复制 Kangoo 范式时再做。现在手写。

## 相关

- [counter-column.md](counter-column.md) — 为什么不能用 counter_cache（四部曲）
- [ADR-018](../decisions/ADR-018-counter-column-and-rls.md) — 决策 + 完整样板
- [ADR-014](../decisions/ADR-014-rls-policy-generator.md) — RLS policy 默认模板
