---
topic: data-version
updated_at: 2026-04-28
related:
  - architecture/agent-sandbox.md
  - architecture/data-packs.md
  - decisions/ADR-001-all-business-tables-have-data-version.md
  - decisions/ADR-003-business-vs-system-tables.md
  - decisions/ADR-004-rls-requires-bin-db-init.md
source_files:
  - app/models/concerns/data_versionable.rb
  - app/models/application_record.rb
  - config/database.yml
  - bin/db_init
  - bin/setup
  - db/structure.sql
  - lib/validator_linter.rb
---

# 🔒 data_version 隔离机制

> 前置阅读：[agent-sandbox.md](agent-sandbox.md) —— 理解**为什么**需要 data_version 后再读本文**怎么实现**。

## 1. 总览图

```
┌─────────────────────────────────────────────────────────────────┐
│  Application Layer (Rails)                                       │
│                                                                  │
│  ApplicationRecord                                               │
│   └── include DataVersionable                                    │
│        ├── before_create :set_data_version    ← 写入时自动打标   │
│        └── default_scope { where(current_versions) } ← 查询时过滤 │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│  Database Layer (PostgreSQL)                                     │
│                                                                  │
│  SET SESSION app.data_version = '<hex>'                          │
│   │                                                              │
│   └─► Row-Level Security (RLS) policy                            │
│         USING (data_version IN ('0', current_setting(...)))      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**双保险**（defense in depth）：
- 应用层 `default_scope` 会被 `unscoped` 绕过
- DB 层 RLS 由 `app_user` 角色强制，无法绕过
- 两层任一失守，另一层兜底

## 2. 三段式生命周期

### 2.1 启动 / baseline 加载
```ruby
# lib/tasks/validator.rake
ActiveRecord::Base.connection.execute("SET SESSION app.data_version = '0'")
load 'app/validators/support/data_packs/v1/base.rb'
# ... 其他 packs 按字母序
# 所有 insert_all / create! 产生的记录自动 data_version='0'
```

### 2.2 Agent 会话开始
```ruby
# Validator 基类
@data_version = SecureRandom.hex(16)  # "a3f2e1..."
ActiveRecord::Base.connection.execute(
  "SET SESSION app.data_version = '#{@data_version}'"
)
```
此刻起，本连接上：
- `Product.all` → 自动过滤为 `data_version IN ('0', 'a3f2e1...')`
- `Product.create!(name: 'X')` → before_create 读 session var，自动设 `data_version='a3f2e1...'`

### 2.3 回滚
```ruby
DataVersionable.models.each do |klass|
  klass.unscoped.where.not(data_version: '0').delete_all
end
```
回到起点，环境可复用。

## 3. 核心文件清单

| 文件 | 职责 |
|---|---|
| `app/models/concerns/data_versionable.rb` | Concern：before_create + default_scope + 模型注册 |
| `app/models/application_record.rb` | `include DataVersionable`（所有子类自动获得） |
| `db/migrate/..._configure_app_data_version_parameter.rb` | **no-op 占位**。`ALTER DATABASE SET app.data_version='0'` 需要 superuser，migration 以 app_user 跑不动，改由 `bin/db_init` 处理。详见 [ADR-004](../decisions/ADR-004-rls-requires-bin-db-init.md) |
| `db/migrate/..._enable_rls_on_business_tables.rb` | 对所有业务表 ENABLE + FORCE RLS + CREATE POLICY |
| `config/database.yml` | Rails 以 `app_user`（NOSUPERUSER + CREATEDB）身份连接，受 RLS 约束 |
| `bin/db_init` | **RLS 初始化唯一入口**。创角色 + 创库 + 注册 GUC 参数 + migration + baseline + 自检。详见 [ADR-004](../decisions/ADR-004-rls-requires-bin-db-init.md) |
| `bin/setup` | 首次搭建检测：无 app_user → 转发 `bin/db_init`；否则走 `db:prepare` |
| `db/structure.sql` | **必须**用 SQL 格式 dump，`schema.rb` 无法序列化 RLS policy |
| `lib/validator_linter.rb` | 静态扫描 validator 中的查询是否漏 `data_version` 过滤 |
| `lib/tasks/validator.rake` | `reset_baseline`, `lint` 任务 |

**⚠️ 为什么不用 `db/schema.rb`**：
Rails 的 Ruby schema dumper 不支持 `CREATE POLICY` / `ENABLE ROW LEVEL SECURITY` / `ALTER DATABASE SET`。
用 `db:schema:load` 新建库 → RLS 策略**全部丢失** → 单层防御。
`config.active_record.schema_format = :sql` + `db/structure.sql` 才能完整保留 PG 特有 DDL。

## 3.1. 双保险如何真正生效（容易踩坑）

**关键**：PostgreSQL 的 `ENABLE ROW LEVEL SECURITY` 对**表所有者**和**superuser**都**不生效**。

| 场景 | 是否受 RLS 约束 |
|---|---|
| 用 `postgres`（superuser）连接 | ❌ 绕过（PG 设计，无解） |
| 用表所有者连接（只 ENABLE） | ❌ 绕过 |
| 用表所有者连接（ENABLE + **FORCE**） | ✅ 受约束 |
| 用 NOSUPERUSER 非所有者 + ENABLE | ✅ 受约束 |

**rlbox 的组合拳**：
1. migration 里 `ALTER TABLE xxx FORCE ROW LEVEL SECURITY`（让表所有者也被约束）
2. `config/database.yml` 把 dev/test 也切到 `app_user`（NOSUPERUSER）—— 双保险
3. `bin/db_init` 自动创建 app_user 并把 dev/test 两个库的 owner 都改成 app_user

### ⚠️ 为什么 `db:setup` / `db:reset` 不够用？

- `ALTER DATABASE ... SET app.data_version='0'` 是**数据库级 GUC 参数**，PG 规定只有 **superuser** 能设，migration 跑不动
- `app_user` 需要 **CREATEDB** 权限（让 `db:test:prepare` 能 DROP+CREATE test 库），这个也需要 superuser 建

**→ 必须用 `bin/db_init` 才能正确初始化。详见 [ADR-004](../decisions/ADR-004-rls-requires-bin-db-init.md)。**

## 4. 加新表的流程

### ✅ 业务表
```bash
# 1. 用生成器（自动加 data_version 列）
bin/rails g model Coupon code:string discount:decimal

# 2. 生成的 migration 自动含：
#    t.string :data_version, default: '0', null: false, limit: 50
#    t.index  :data_version

# 3. ApplicationRecord 继承 → 自动 include DataVersionable

# 4. 跑 migration（app_user 身份）
bin/rails db:migrate

# 5. RLS policy 自动生效（migration 跑后 ENABLE + FORCE RLS + CREATE POLICY）
```

### ✅ 系统表（罕见）
只有 Administrator / Session / AdminOplog / ValidatorExecution / ActiveStorage* 这类才用：
```ruby
class AuditLog < ApplicationRecord
  data_version_excluded!
  default_scope { unscope(where: :data_version) }
  skip_callback :create, :before, :set_data_version
end
```
migration 手写不加 data_version 列。详见 [ADR-003](../decisions/ADR-003-business-vs-system-tables.md)。

## 5. 易错点（不断更新）

### ❌ Category 被误认为系统表
```ruby
class Category < ApplicationRecord
  data_version_excluded!   # ← WRONG！Agent 可能新建分类
end
```
**结果**：Agent 新建的分类永久写入 baseline，pollute 后续所有评测。

### ❌ simulate 里创建 data_version='0'
```ruby
def simulate
  Product.create!(name: 'test', data_version: '0')  # ← WRONG！
end
```
**结果**：测试数据污染 baseline。**正确**：用 `@data_version`。

### ❌ 不用 `bin/db_init` 初始化
```bash
bin/rails db:setup   # ← WRONG！不会创建 app_user，不会注册 GUC
```
**结果**：`username: postgres` 是 superuser，RLS 形同虚设。

## 6. 延伸阅读
- [data-packs.md](data-packs.md) — baseline 数据加载
- [ADR-001](../decisions/ADR-001-all-business-tables-have-data-version.md) — 所有业务表必须有 data_version
- [ADR-003](../decisions/ADR-003-business-vs-system-tables.md) — 业务 vs 系统表判断
- [ADR-004](../decisions/ADR-004-rls-requires-bin-db-init.md) — 为什么必须用 bin/db_init
- [conventions/adding-models.md](../conventions/adding-models.md) — 加新表完整流程
