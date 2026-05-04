---
topic: tech-debt-cleanup-spec
updated_at: 2026-05-03
status: draft
related:
  - decisions/ADR-011-bin-dev-loads-dotenv.md
  - decisions/ADR-014-rls-policy-generator.md
  - decisions/ADR-015-data-pack-depends-on.md
  - decisions/ADR-016-lint-schema-consistency.md
  - architecture/data-version.md
---

# 2026-05-03 rlbox 生态技术债清理 Spec

> **For agentic workers:** 本文是设计文档（Spec），不是执行 plan。锁定方案后，应调用 `box-writing-plans` skill 生成对应的 `YYYY-MM-DD-<slug>-plan.md` 再执行。

**Goal:** 把 rlbox 底座从"能跑"升级到"干净整齐可复制"，同时把 5 个派生项目（Goomart / planet / IdleSwap / Kangoo / duvy）的 database 命名、`bin/db_init`、lint_schema 工具链统一到同一套约定上。

**Strategy:** Rlbox-First 底座先行——先把 rlbox 改完立好新规矩，再按新规矩推派生项目。7 项债一次清完，不留"下次再说"的尾巴。

---

## 1. Background & Goals

### 1.1 债务盘点

本轮清债的触发来自两个信号：

- 用户在 rlbox 本机环境跑 `bin/rake validator:lint_schema` 报了 **22 ERROR**，初步看是业务表缺 `DataVersionable` include，但深挖后发现是**本机 DB 被历史实验污染** + **仓库真实的 RLS 策略债** + **lint 文案有歧义** 的三重叠加。
- 上一轮 reverse-port（`db6b914`）把 rls_policy generator / data_pack depends_on / lint_schema 等新工具从 Goomart 反向同步到了 rlbox 底座，但 `bin/db_init` 和 `database.yml` 的命名约定**没跟着同步**——rlbox 还留着最原始的"Rails 出厂 `myapp_development` + `postgres/postgres`"默认值，而 5 个派生项目已经各自用 `<slug>_db` / `<slug>_development` + `app_user/postgres` 等不同风格在跑。这导致：
  - rlbox fork 出新项目时，如果忘记改 `database.yml` 的 database 名，会和其他 rlbox-family 项目**共享同一个 PG database**（撞车）。
  - 派生项目之间命名风格不统一，跨项目切换心智成本大。

### 1.2 完整债清单（7 项）

| # | 债 | 性质 | 范围 | 本轮覆盖 |
|---|---|---|---|---|
| 1 | 本机 DB 污染：10 张孤儿表（addresses/cart_items/categories/locations/order_items/orders/payment_passwords/product_variants/products/reviews）+ 25 条幽灵 schema_migrations 记录 | 个人环境污染 | 我本机 PG | ✅ P0 |
| 2 | 12 张表的 RLS policy 仍是旧 `FOR ALL` 单策略，未按 ADR-014 拆成 4 个 op（SELECT/INSERT/UPDATE/DELETE） | 仓库真实债 | rlbox | ✅ P1 |
| 3 | `sessions` 表带 `data_version` 列（schema drift），违反 ADR-003「系统表三件套不带 data_version」 | 仓库真实债 | rlbox | ✅ P1 |
| 4 | `validator:lint_schema` rake 任务的错误文案 `"no model includes DataVersionable"` 误导——真正原因可能是"Ruby model 文件根本不存在"或"表是污染进来的" | 仓库真实债 | rlbox | ✅ P1 |
| 5 | `database.yml` 默认 `myapp_development` / `myapp_test` + `postgres/postgres`，所有 fork 不改就撞车 | 机制问题 | rlbox | ✅ P1 |
| 6 | `bin/db_init` 是 70 行旧版本（密码硬编码 `password`，不建 DB，无 DROP 模式，无 `app.data_version` GUC 注册），严重落后于 Goomart/planet/Kangoo/duvy 的 183 行版本 | 仓库真实债 | rlbox | ✅ P1 |
| 7 | 5 个派生项目的 `database.yml` 命名**不统一**（`goomart_db`/`planet_db`/`idleswap_db`/`kangoo_development`/`duvy_db` 五种风格共存），username/password 也各异（`goomart/goomart` vs `app_user/postgres` vs `app_user/duvy`） | 生态一致性 | 5 派生项目 | ✅ P2 |

### 1.3 Goals

- **G1**：rlbox 本机 PG 干净，`bin/rake validator:lint_schema` 输出 0 ERROR。
- **G2**：rlbox 仓库的 schema / RLS policy / sessions 表 / lint 文案 / db_init / database.yml **全部符合 Goomart 实证过的新标准**。
- **G3**：`database.yml` 命名约定被正式写成 ADR（ADR-017），成为 rlbox 生态的强制约定。
- **G4**：5 个派生项目的 `database.yml` 按 ADR-017 统一，同时各自本机 PG 能通过 `DROP=1 bin/db_init` 一键重建到干净状态。
- **G5**：`lint_schema` 的错误文案不再误导 agent——要么精确描述"Ruby 模型文件不存在"，要么精确描述"RLS 策略格式过时"。

### 1.4 Non-Goals

- **不**重构 RLS policy 的业务语义（只把旧 `FOR ALL` 拆成新 4-op，策略内容等价迁移）。
- **不**动 `agent_tasks` / `linear_installations` / `project_mappings` 这三张 rlbox 内置的辅助表（它们是 agent 平台自己用的，跟业务无关）。
- **不**碰 production `DATABASE_URL` 流程（本轮只影响开发/测试本机环境）。
- **不**改 `appname.txt` 语义（它是中文展示名，不是 slug，本轮不绑定它到 database 名）。

---

## 2. Scope

### 2.1 In Scope（本轮必做）

**rlbox 底座（1 仓库）：**
- `config/database.yml` 改名 + 加 `WORKTREE_DEV_DB`/`WORKTREE_TEST_DB` fallback
- `bin/db_init` 从 Goomart 反向同步完整版（183 行模板）
- migration 删 `sessions.data_version` 列
- `app/models/session.rb` 加三件套（`data_version_excluded!` + `unscope` + `skip_callback`）
- 12 张业务表跑 `rails g rls_policy` 批量升级
- `lib/tasks/validator.rake` 的 `lint_schema` 文案精修
- 新开 ADR-017 正式立命名约定
- 本机执行 `DROP=1 bin/db_init` 清污染 + 重建

**派生项目（5 仓库）：**
- `config/database.yml` 按 ADR-017 统一（命名后缀 / username / password）
- 各家本机执行 `DROP=1 bin/db_init` 迁移到新 database 名
- 跑 `bin/rake validator:lint_schema` 验证 0 error
- 提交各自 PR

### 2.2 Out of Scope（本轮不做，但记录在案）

| 未做 | 理由 | 归宿 |
|---|---|---|
| 把 `bin/db_init` 进一步从"每个项目独立脚本"变成"rlbox gem 抽象" | 抽象成本 > 当前收益，6 个项目复制粘贴同一份 183 行就够了 | 未来 RFC |
| 更深的 RLS policy 业务逻辑审计（比如 UPDATE 时是否应该校验 old.data_version） | 本轮只做格式迁移，不动业务语义 | Future work |
| production 环境 `DATABASE_URL` 的命名规范 | production 走 Railway，由平台注入，本轮不涉及 | N/A |
| `schema_migrations` 幽灵记录清除的根因（历史某次用了错误的 Rails.root 跑 migration） | 本轮 `DROP=1` 足以消除现象，根因是"多项目共享 DB"，已被 ADR-017 消除 | 已解决 |

---

## 3. Database Naming Convention（ADR-017 核心）

### 3.1 正式约定

```yaml
# <project>/config/database.yml
development:
  adapter:  postgresql
  host:     localhost
  encoding: unicode
  database: <%= ENV.fetch('WORKTREE_DEV_DB',  '<slug>_development') %>
  pool:     15
  username: app_user
  password: postgres
  template: template0

test:
  adapter:  postgresql
  host:     localhost
  encoding: unicode
  database: <%= ENV.fetch('WORKTREE_TEST_DB', '<slug>_test') %>
  pool:     15
  username: app_user
  password: postgres
  template: template0

production:
  primary: &primary_production
    adapter:  postgresql
    pool:     30
    url:      <%= ENV.fetch('DATABASE_URL', '') %>

  cable:
    <<: *primary_production
    migrations_paths: db/cable_migrate
```

**规则：**
1. **DB 名后缀**：dev 用 `_development`（Rails 官方标准），test 用 `_test`。左右对称。
2. **slug 来源**：每个项目**硬编码**自己的 slug，是 fork 后第一件事。slug = 项目仓库文件夹名的小写形式。
3. **ENV fallback**：`WORKTREE_DEV_DB` / `WORKTREE_TEST_DB` 走 box-using-git-worktrees 的多 worktree 隔离（ADR-011）。
4. **username / password**：统一 `app_user / postgres`。`app_user` 是 `NOSUPERUSER + CREATEDB` 角色（RLS 生效必需 + test 库重建必需）。
5. `template: template0` 避免继承 template1 的地区设置（保证 UTF8 一致）。

### 3.2 各项目的目标 slug

| 项目 | slug | dev DB | test DB |
|---|---|---|---|
| rlbox | `rlbox` | `rlbox_development` | `rlbox_test` |
| Goomart | `goomart` | `goomart_development` | `goomart_test` |
| planet | `planet` | `planet_development` | `planet_test` |
| IdleSwap | `idleswap` | `idleswap_development` | `idleswap_test` |
| Kangoo | `kangoo` | `kangoo_development` | `kangoo_test` |
| duvy | `duvy` | `duvy_development` | `duvy_test` |

### 3.3 appname.txt 与 slug 的关系

- `config/appname.txt` = **中文展示名**（"我购market"/"星球社交网"），用于页面标题、PWA 名称等用户可见位置。
- **slug** = **英文技术标识**，用于 database 名、git 文件夹名、service 名等机器可读位置。
- 二者**解耦**，各自演化。本轮不合并、不交叉引用。

---

## 4. Execution Order

### 4.1 三阶段总图

```
P0 本机清理 (独立, 15 min)
    ↓
P1 rlbox 底座修复 (单仓库, 1 个 session, ~2h)
  ├─ P1.1 反向同步 bin/db_init (从 Goomart 复制模板)
  ├─ P1.2 改 database.yml (DB 名 + user + pass + ENV fallback)
  ├─ P1.3 migration 删 sessions.data_version 列
  ├─ P1.4 Session model 加三件套
  ├─ P1.5 12 张业务表跑 rails g rls_policy
  ├─ P1.6 精修 lint_schema 文案
  ├─ P1.7 写 ADR-017
  └─ P1.8 DROP=1 bin/db_init → rake validator:lint_schema 0 error → commit
    ↓
P2 派生项目同步 (5 仓库, 可并行, 各 ~30 min)
  ├─ P2.1 Goomart: database.yml 改名 + DROP 重建 + 0-error check + PR
  ├─ P2.2 planet:  同上
  ├─ P2.3 IdleSwap: 同上
  ├─ P2.4 Kangoo:   同上 (改动最少)
  └─ P2.5 duvy:    同上
```

### 4.2 为什么 P0 必须最先做

P0 是**幂等清理我本机环境**，不改仓库。做不做 P0 都不影响仓库 diff，但**不做 P0 就看不清 P1 效果**——`lint_schema` 会一直挂着 10 个孤儿表的 ERROR 干扰视线。

### 4.3 为什么 P1 必须在 P2 之前

- P1 会新出 ADR-017 + 新 `bin/db_init` 模板 + 新 `lint_schema` 文案。P2 要依赖这些产物。
- 派生项目改 database.yml 时，会引用 ADR-017 的规定行文。
- P1 也会反证一个关键点：**rlbox 底座在新约定下本身能跑通 0 error**——如果底座都跑不通，派生项目照抄也没用。

### 4.4 P2 为什么可以并行

5 家派生项目的改动是**独立 git 仓库各自独立 PR**，改的又是各自的 `database.yml`（不是共享文件），互不影响。唯一共享的是"跟着 rlbox 新 ADR-017 走"这个精神——精神已经在 P1 阶段固化为文字。

---

## 5. rlbox P1 改动详单

### 5.1 P1.1 反向同步 `bin/db_init`

**来源：** `Goomart/bin/db_init`（183 行模板）

**动作：**
- 直接 `cp Goomart/bin/db_init rlbox/bin/db_init`
- 把脚本里硬编码的 `'🚀 Goomart 数据库初始化'` 改成 `'🚀 rlbox 数据库初始化'`（仅 banner 文字，不影响逻辑）
- `chmod +x rlbox/bin/db_init` 确认可执行

**验收：**
- `bin/db_init` 首次运行能在空 PG 上建好 `rlbox_development` + `rlbox_test`，owner 都是 app_user
- `DROP=1 bin/db_init` 能把现有 DB 删除后重建
- `psql rlbox_development -c "SHOW app.data_version;"` 返回 `'0'`（GUC 参数注册成功）

### 5.2 P1.2 改 `config/database.yml`

**当前：**
```yaml
database: myapp_development
username: postgres
password: postgres
```

**目标：**
```yaml
database: <%= ENV.fetch('WORKTREE_DEV_DB', 'rlbox_development') %>
username: app_user
password: postgres
```

test 段同样改。

**验收：** YAML 语法合法；`bin/rails db:version` 能连上。

### 5.3 P1.3 Migration 删 `sessions.data_version` 列

**产物：** 新 migration `db/migrate/YYYYMMDDHHMMSS_drop_data_version_from_sessions.rb`

```ruby
class DropDataVersionFromSessions < ActiveRecord::Migration[7.2]
  def change
    remove_column :sessions, :data_version, :string
    # 同时移除可能存在的索引（如果 schema.rb 里有）
  end
end
```

**验收：** `bin/rails db:migrate` 跑过 + `db/schema.rb` 里 `sessions` 表不再有 `data_version` 列。

### 5.4 P1.4 `app/models/session.rb` 加三件套

**参考：** ADR-003 / ADR-010 系统表三件套规范

**改动：**
```ruby
class Session < ApplicationRecord
  data_version_excluded!
  default_scope { unscope(where: :data_version) }
  skip_callback :create, :before, :set_data_version
  # ...原有的 association / validation 保留
end
```

**验收：** `bin/rails runner 'p Session.first'` 不再附加 `WHERE data_version = ...` 条件。

### 5.5 P1.5 12 张业务表跑 `rails g rls_policy`

**来源表清单：** 通过 `bin/rake validator:lint_schema` 的 "old FOR ALL policy" 报告得出。

**批处理脚本（预留）：**
```bash
for t in posts users administrators admin_oplogs validator_executions agent_tasks \
         project_mappings linear_installations friendly_id_slugs good_jobs good_job_batches \
         good_job_executions good_job_processes good_job_settings active_storage_attachments \
         active_storage_blobs active_storage_variant_records; do
  bin/rails g rls_policy $t
done
# （实际表清单以 lint_schema 报告为准，12 张可能会包含上面部分）
```

**注意：** 系统表（administrators/sessions/admin_oplogs/validator_executions/active_storage_*）需要走**特殊策略**（按 ADR-003 bypass data_version），不是标准 4-op。rls_policy generator 对系统表应该识别并跳过，或生成占位 migration。

**验收：** `bin/rake validator:lint_schema` 不再报 "old FOR ALL policy" ERROR。

### 5.6 P1.6 精修 `lint_schema` 文案

**当前文案（`lib/tasks/validator.rake` 约 390 行附近）：**
> `"Table X has data_version column but no model includes DataVersionable"`

**问题：** 用户/agent 看到后会去 model 加 `include DataVersionable`，但实际可能是"model 文件根本不存在（污染表）"或"model 文件存在但 Ruby class name resolver 没找到"。

**新文案（建议）：**
> `"Table 'X' has data_version column but cannot locate Ruby model. Possible causes: (1) Ruby model file missing under app/models/ (table may be residual from a polluted DB — run 'DROP=1 bin/db_init' to rebuild); (2) Ruby class name does not match table name convention; (3) Model exists but not auto-registered via DataVersionable inherited hook."`

**验收：** 文案包含三种可能性提示 + 具体行动建议。

### 5.7 P1.7 写 ADR-017

**路径：** `docs/decisions/ADR-017-database-naming-convention.md`

**结构：** Context / Decision / Consequences / Migration notes

**关键内容：**
- 约定条款（第 3.1 节内容）
- slug vs appname 解耦说明（第 3.3 节内容）
- fork 新项目的 checklist（第一件事改 database.yml 的 slug）
- 与 ADR-011（ENV fallback）的关系
- 历史遗留（5 派生项目迁移日期）

### 5.8 P1.8 一把梭验收

**顺序：**
1. `DROP=1 bin/db_init` — 清污染 + 重建新 DB
2. `bin/rails db:test:prepare` — 同步 schema 到 test DB
3. `bin/rake validator:lint_schema` — 必须 **0 error**
4. `bin/rake test` / `bundle exec rspec` — 必须全绿
5. `git add -A && git commit -m "chore: tech debt cleanup (ADR-017 + db_init sync + RLS migration)"`

---

## 6. Sibling Sync Playbook（P2）

### 6.1 通用 5 步（每家派生项目都一样）

```bash
cd /Volumes/SengclawWorkspace/code/<project>

# Step 1: 备份现状（保险起见）
pg_dump <old_dev_db> > /tmp/<project>_dev_backup.sql   # 可选

# Step 2: 改 database.yml（按 ADR-017 表格）
# - database 名改成 <slug>_development / <slug>_test
# - username 统一 app_user
# - password 统一 postgres
# - 确保 ENV.fetch 在位

# Step 3: 本机迁移
DROP=1 bin/db_init                                   # 清旧 DB + 建新 DB + migrate + reset_baseline

# Step 4: 验证
bin/rake validator:lint_schema                        # 必须 0 error
bin/rake test                                         # 必须全绿
bin/dev                                               # 手动访问首页确认

# Step 5: 提 PR
git checkout -b chore/adr-017-database-naming
git add config/database.yml
git commit -m "chore(db): rename to <slug>_development per ADR-017"
git push -u origin chore/adr-017-database-naming
```

### 6.2 各家差异速查

| 项目 | database 名改动 | username 改动 | password 改动 | 备注 |
|---|---|---|---|---|
| **Goomart** | `goomart_db` → `goomart_development` | `goomart` → `app_user` | `goomart` → `postgres` | 改动最大 |
| **planet** | `planet_db` → `planet_development` | —（已是 app_user） | —（已是 postgres） | 只改 DB 名 |
| **IdleSwap** | `idleswap_db` → `idleswap_development` | — | — | 只改 DB 名 |
| **Kangoo** | —（已是 `kangoo_development`） | — | — | **几乎无改动**（只确保 ENV.fetch 在位即可） |
| **duvy** | `duvy_db` → `duvy_development` | — | `duvy` → `postgres` | 改 DB 名 + 密码 |

### 6.3 `bin/db_init` 反向同步到派生项目？

**不需要。** 派生项目的 `bin/db_init`（183 行 Goomart 模板）已经足够完备，只有 IdleSwap 稍旧（165 行）可以在本轮顺手升级到 183 行，但不是硬性要求——它已经有 DROP 模式和 GUC 注册，能干活就行。

### 6.4 时间预期

- Kangoo：10 分钟
- planet / IdleSwap：20 分钟
- Goomart / duvy：30 分钟
- 总计：约 2 小时（串行）或 40 分钟（并行 + 主力 + 副手）

---

## 7. Validator Acceptance Scenarios

rlbox 有 `app/validators/` 体系，本轮改动虽然不直接新增 validator，但需要保证**现有 validator 在新环境下不 regress**。

### 7.1 场景 V1：`sessions` 表三件套后，Session 创建不 appending data_version

**前置：** P1.3 + P1.4 完成。

**步骤：**
1. `bin/rails console`
2. `Session.new(user: User.first).save!`
3. 观察生成的 INSERT SQL 不包含 `data_version` 字段。

**通过条件：** SQL 不包含 `data_version`；记录创建成功。

### 7.2 场景 V2：`DROP=1 bin/db_init` 后基线数据幂等

**前置：** P1.1 + P1.8 完成。

**步骤：**
1. `DROP=1 bin/db_init`
2. 记录 `User.where(data_version: '0').count`
3. `bin/rake validator:reset_baseline`
4. 再次记录 `User.where(data_version: '0').count`

**通过条件：** 两次 count 完全一致（幂等）。

### 7.3 场景 V3：新 `lint_schema` 在干净环境下报 0 error

**前置：** P1.8 完成，本机 DB 已重建为纯 rlbox schema。

**步骤：**
1. `bin/rake validator:lint_schema`

**通过条件：** 输出包含 `✅ All schema integrity checks passed.`（或等价成功文案）；退出码 0。

### 7.4 场景 V4：新 `lint_schema` 人为制造一个孤儿表能正确识别

**步骤：**
1. `psql rlbox_development -c "CREATE TABLE fake_orphan (id serial, data_version varchar);"`
2. `bin/rake validator:lint_schema`

**通过条件：** 输出包含新文案的三种可能性提示；定位到 `fake_orphan` 表；退出码非 0。

**清理：** `psql rlbox_development -c "DROP TABLE fake_orphan;"`

### 7.5 场景 V5：5 派生项目各自 lint_schema 0 error

**前置：** P2.1 ~ P2.5 全部完成。

**步骤：** 每家 `cd <project> && bin/rake validator:lint_schema`

**通过条件：** 5 家都 0 error。

---

## 8. ADR 规划

### 8.1 新增

| ADR | 标题 | 本轮是否落盘 |
|---|---|---|
| ADR-017 | Database Naming Convention（`<slug>_development/_test` + `app_user/postgres` + ENV fallback） | ✅ P1.7 |

### 8.2 更新

| 文档 | 更新点 |
|---|---|
| `docs/decisions/ADR-011-bin-dev-loads-dotenv.md` | 补一段"与 ADR-017 的关系：WORKTREE_DEV_DB/TEST_DB 是 ADR-017 约定的 ENV fallback" |
| `docs/architecture/data-version.md` | 补一条"sessions 表作为系统表不带 data_version（参见 ADR-003）" |
| `docs/architecture/validator-linter.md` | 更新 lint_schema 新文案示例 + 三种可能性说明 |
| `CLAUDE.md` 路由表 | 新增一行"DB 命名/fork 后第一件事"→ ADR-017 |

### 8.3 归档

无（本轮不淘汰任何现有 ADR）。

---

## 9. Risks & Rollback

### 9.1 风险矩阵

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| **本机数据丢失**（DROP=1 误操作） | 中 | 低（本机 dev 环境，数据都是 baseline + 造的） | 备份 dump + 严格区分 dev 与 production DATABASE_URL 流程 |
| **派生项目 PR 冲突** | 低 | 低（只改 database.yml 一个文件） | P2 5 家各自独立 PR，互不影响 |
| **RLS policy 迁移漏表** | 中 | 中（漏掉的表跨会话不隔离） | `lint_schema` 会兜底报错；跑 `rake test` 验证 |
| **sessions 去 data_version 后，某处代码还在引用 `session.data_version`** | 低 | 低 | `grep -rn "session.data_version\|session\[.data_version.\]"` 全局扫 + 跑测试 |
| **Goomart 等派生项目用户遗留数据**（如 duvy 本机有真实试用数据） | 低 | 中 | P2 Step 1 建议 `pg_dump` 备份 |
| **`bin/db_init` 183 行模板 banner 改名遗漏** | 低 | 极低（仅影响输出美观） | Code review 时肉眼检查 |

### 9.2 Rollback 计划

- **P1（rlbox）回滚**：`git revert <commit_hash>` + `DROP=1 bin/db_init`（用旧 yml 回滚前重新跑）。但因为 P1 是单 commit、改动隔离，revert 成本很低。
- **P2（派生项目）回滚**：各家独立 revert，互不影响。

### 9.3 故意不做防御的地方

- **production `DATABASE_URL`**：本轮不碰，由 Railway 平台注入，与本地 `database.yml` 无关。
- **多 worktree 隔离**：已由 ADR-011 的 `WORKTREE_DEV_DB`/`WORKTREE_TEST_DB` 覆盖，不重复设计。

---

## 10. Out-of-Scope / Future Work

| 议题 | 为什么本轮不做 | 未来归宿 |
|---|---|---|
| 抽象 `bin/db_init` 到 rlbox gem | 6 个项目复制粘贴成本低于抽象成本 | RFC-20XX |
| RLS policy 业务语义审计（UPDATE 是否应锁定 old.data_version） | 本轮只做格式迁移不动语义 | 专题 session |
| production DATABASE 命名规范 | 由 Railway 平台注入，与本地开发流程解耦 | 部署 playbook |
| `appname.txt` 扩展为结构化（中文名 + slug + 主题色） | 目前没有刚需 | 观察 |
| `bin/db_init` IdleSwap 183 行模板升级（现在 165 行） | 能干活，非阻塞 | 下一轮顺手 |
| `schema_migrations` 幽灵记录根因报告 | DROP=1 已消除现象，ADR-017 已消除成因 | 无 |

---

## 11. 执行节奏建议

### 11.1 单 session 全部完成？

**不建议。** 本 Spec 涉及 6 个仓库、约 4 小时净工作量，单 session 执行风险在于：
- 注意力衰减导致后半段 RLS policy 迁移漏表
- 某个意外错误打断后重启成本高

### 11.2 建议分段

| Session | 内容 | 预估时长 |
|---|---|---|
| **Session A** | P0 本机清理 + P1.1~P1.4（db_init + database.yml + sessions 三件套） | 1h |
| **Session B** | P1.5~P1.8（RLS 12 表 + lint_schema + ADR-017 + 一把梭验收） | 1.5h |
| **Session C** | P2 派生项目（5 家按顺序或并行） | 1~2h |

Session A/B/C 之间可以间隔，每段结束有明确 commit 节点。

### 11.3 单 session 可接受的 MVP

如果只有 1 小时，优先做 P0 + P1.2 + P1.7（ADR-017）——规矩先立住，具体改动可以下次继续。但这意味着 rlbox 本身仍然不达标，不算"干净底座"。

---

## 12. Spec 自检清单

- [x] **范围明确**：7 项债全部列出，每项有"本轮/未来"标签。
- [x] **顺序合理**：P0 → P1 → P2 有依赖关系说明。
- [x] **产物清晰**：每个 P1 子任务都有验收条件。
- [x] **回滚路径**：每阶段 revert 都是 git 单 commit 级别。
- [x] **无占位符**：没有 `TODO`/`TBD`/`FIXME` 遗留。
- [x] **ADR 边界**：新 ADR-017 和已有 ADR-011/003 的关系明确。
- [x] **验收场景**：5 个 Validator Acceptance Scenarios 覆盖本轮主要改动面。
- [x] **Non-Goals 显式**：4 项明确不做的事列在案。
- [x] **风险缓解**：6 项风险都有应对。
- [x] **时长可控**：总预估 4h，分段 1-2h 每段。

---

## 13. Next Step

**用户 review 本 Spec → 锁定 → 调用 `box-writing-plans` skill 生成执行 plan：**

```
/box-writing-plans spec=docs/architecture/2026-05-03-tech-debt-cleanup-spec.md
```

生成的 plan 将命名为 `docs/architecture/2026-05-03-tech-debt-cleanup-plan.md`，以 checkbox 格式列出具体 task，可由 `box-executing-plans` 逐步执行。

---

## 14. Appendix

### 14.1 本机 DB 污染的历史回放

1. 某次（可能是 Goomart 或 duvy 早期）在 rlbox 目录下误跑了其他项目的 migration，或共用了 `myapp_development` 数据库。
2. 10 张表（addresses/cart_items/categories 等）和对应 schema_migrations 记录被持久化在本机 PG 中。
3. rlbox 的 `db/schema.rb` 和 `db/migrate/` 都是干净的（只有 18 张合法表 + 10 个 migration 文件）。
4. **结论**：仓库清白，本机脏。DROP=1 重建即可根除。

### 14.2 关键实证数据

```
rlbox migration 文件数：10
rlbox 本机 PG schema_migrations 行数：35
差异：25 条幽灵 migration（来自其他项目）

rlbox schema.rb create_table 数：18
rlbox 本机 PG tables 数：~28
差异：10 张孤儿表（addresses/cart_items/categories/locations/order_items/orders/
      payment_passwords/product_variants/products/reviews）
```

### 14.3 相关文件路径

- `docs/decisions/ADR-011-bin-dev-loads-dotenv.md` — 现有 ENV fallback 机制
- `docs/decisions/ADR-014-rls-policy-generator.md` — RLS policy 4-op 标准
- `docs/decisions/ADR-015-data-pack-depends-on.md` — data pack 依赖 DSL
- `docs/decisions/ADR-016-lint-schema-consistency.md` — lint_schema 框架
- `docs/architecture/data-version.md` — data_version 软隔离核心
- `docs/architecture/validator-system.md` — validator 生命周期
- `Goomart/bin/db_init` — P1.1 反向同步源模板
- `Goomart/config/database.yml` — P2 参考样式（但 Goomart 自己也要改）

---

**Spec 负责人**：大胜龙虾  
**最后更新**：2026-05-03  
**状态**：Draft → 等用户 review → Accepted
