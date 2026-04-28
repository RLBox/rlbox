---
topic: agent-sandbox
updated_at: 2026-04-28
related:
  - architecture/data-version.md
  - architecture/data-packs.md
  - decisions/ADR-001-all-business-tables-have-data-version.md
---

# 🤖 Agent 评测沙盒 —— 项目核心架构

> 这是整个项目的**第一性原理**。任何模型/数据/API 设计冲突时，回到这个文档裁决。

## 1. 项目本质

**rlbox** 是一个 **Agent Benchmark 测试床模板**。每个派生项目（Goomart / IdleSwap / Kangoo…）都是：
- 表面：一个真实业务 App（电商 / 二手交易 / 外卖）
- 本质：通过 Task + Validators，验证 Agent 能否完成用户任务

```
         ┌─────────────────────────────────────────┐
         │   评测者（研究员）                         │
         │   出题：Task + Validator                  │
         └───────────────┬─────────────────────────┘
                         ↓
         ┌─────────────────────────────────────────┐
         │   App（被操作对象）                        │
         │   - 浏览、下单、评价 …                     │
         └───────────────┬─────────────────────────┘
                         ↑
         ┌─────────────────────────────────────────┐
         │   Agent（被评测方）                       │
         │   读懂 Task → 操作应用 → 完成任务          │
         └─────────────────────────────────────────┘
                         ↓
         ┌─────────────────────────────────────────┐
         │   Validator 判定：任务是否完成            │
         │   断言：DB 是否有目标记录？字段是否正确？   │
         └─────────────────────────────────────────┘
```

所以应用里的一切业务功能**都是为了让 Agent 有事可做**。
真实用户的产品体验是副产品，Agent benchmark 是主产品。

## 2. 关键难题：多次评测如何复用环境？

**需求**：同一个实例需要被数千次、数百个 Agent 轮流评测。
**矛盾**：每次 Agent 操作会写数据，污染下一次评测。

### ❌ Naive 方案
- **每次重建数据库**：慢、昂贵、Postgres migration 成本高
- **事务回滚**：跨请求做不到，Agent 操作是真实 HTTP
- **单独租户**：多租户改造代价巨大

### ✅ 我们的方案：`data_version` 软隔离

每行业务数据打上一个版本标签：
- **`data_version = '0'`**：baseline（永不删除，所有评测共享）
- **`data_version = '<session-hex>'`**：某次 Agent 会话产生的数据

```sql
-- 回滚只需一条 SQL：
DELETE FROM <each_business_table> WHERE data_version != '0';
```

这个方案的**三个前提**（不满足就会崩）：

| 前提 | 保证机制 |
|---|---|
| ❶ **所有业务表都有 data_version 列** | `rails g model` 自动加；ADR-001 强制 |
| ❷ **所有查询默认按 session 过滤** | PostgreSQL Row-Level Security + Rails default_scope（双保险） |
| ❸ **baseline 数据稳定可复现** | 只通过 `data_packs/v1/` 加载，幂等；见 `data-packs.md` |

详见 [`data-version.md`](data-version.md)。

## 3. 一次评测的完整生命周期

```ruby
# ① 分配 session（validator 运行前）
@data_version = SecureRandom.hex(16)  # e.g. "a3f2e1..."
ActiveRecord::Base.connection.execute("SET SESSION app.data_version = '#{@data_version}'")

# ② prepare：查 baseline 数据（只读，不写）
@user = User.find_by!(email: 'demo@example.com', data_version: '0')

# ③ Agent 操作应用（HTTP 请求）
#    → Agent 操作业务系统 → 产生带 @data_version 的新记录

# ④ verify：断言业务目标达成
add_assertion "操作成功", weight: 50 do
  record = Order.where(user: @user, data_version: @data_version).last
  expect(record).to be_present
end

# ⑤ cleanup：一键回滚（所有 data_version != '0' 的数据蒸发）
```

## 4. 业务表 vs 系统表

这是整个架构的**分水岭**，错了会污染 baseline 或破坏评测：

| 类别 | 特征 | 处理 | 例子 |
|---|---|---|---|
| **业务表** | Agent 可能读/写 | **必须**有 `data_version` | Product, Order, CartItem, User |
| **系统表** | 只用于运维/鉴权/追踪 | **必须不**有 `data_version`（用三件套排除） | Administrator, Session, AdminOplog, ValidatorExecution, ActiveStorage* |

**判断准则（出题人视角）**：
> *如果我能出一道题让 Agent 新建/修改这张表的记录，它就是业务表。*

**典型陷阱**：看起来像"系统字典"的表（Category / Tag / Location），但 Agent 可能被要求"新建一个分类"——所以它是业务表。详见 [ADR-001](../decisions/ADR-001-all-business-tables-have-data-version.md)。

## 5. 为什么 `db/seeds.rb` 不能当数据入口？

| 维度 | `db/seeds.rb` | `data_packs/v1/` |
|---|---|---|
| 幂等性 | ❌ 用户自己写 | ✅ base.rb 清理 + 模块文件 insert_all |
| 数据版本 | ❌ 容易忘写 `data_version: '0'` | ✅ rake 已 `SET SESSION`，自动落 baseline |
| 模块化 | ❌ 一个大文件 | ✅ 每业务一文件，按字母序加载 |
| 可回滚 | ❌ | ✅ `rake validator:reset_baseline` |

**规则**：`db/seeds.rb` 只放一句注释指向 `data_packs/`。详见 [`data-packs.md`](data-packs.md)。

## 6. 延伸阅读
- [data-version.md](data-version.md) — 实现细节：RLS、DataVersionable concern、lint 保证
- [data-packs.md](data-packs.md) — 数据加载约定
- [ADR-001](../decisions/ADR-001-all-business-tables-have-data-version.md) — 为什么所有业务表都要 data_version
- [ADR-003](../decisions/ADR-003-business-vs-system-tables.md) — 业务表 vs 系统表的判断准则
