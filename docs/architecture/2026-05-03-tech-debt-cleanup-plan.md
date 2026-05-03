---
topic: tech-debt-cleanup-plan
updated_at: 2026-05-03
status: ready
related:
  - architecture/2026-05-03-tech-debt-cleanup-spec.md
  - decisions/ADR-011-bin-dev-loads-dotenv.md
  - decisions/ADR-014-rls-policy-generator.md
---

# rlbox 生态技术债清理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use box:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 清理 rlbox 底座本机污染 + 修复 6 项仓库真实债 + 统一 5 派生项目 database.yml 命名，一次性把 rlbox 生态从"能跑"提升到"干净整齐可复制"。

**Architecture:** 三阶段顺序执行。P0 本机 DB 清理为 gate，P1 rlbox 底座 8 个子任务固化新标准（含 ADR-017），P2 五派生项目按 ADR-017 统一 database.yml 并各自 DROP=1 重建。rlbox 的 bin/db_init 从 Goomart 183 行模板反向同步。

**Tech Stack:** Rails 7.2, PostgreSQL 14+ (RLS + data_version GUC), Ruby 3.3.5, rbenv, bash scripts, 6 个 git 仓库在 /Volumes/SengclawWorkspace/code/ 下。

**Spec 参考:** `rlbox/docs/architecture/2026-05-03-tech-debt-cleanup-spec.md`

**仓库路径:**
- rlbox（底座）: `/Volumes/SengclawWorkspace/code/rlbox`
- Goomart: `/Volumes/SengclawWorkspace/code/Goomart` (端口 11601)
- planet: `/Volumes/SengclawWorkspace/code/planet` (端口 11604)
- IdleSwap: `/Volumes/SengclawWorkspace/code/IdleSwap` (端口 11602)
- Kangoo: `/Volumes/SengclawWorkspace/code/Kangoo` (端口 11603)
- duvy: `/Volumes/SengclawWorkspace/code/duvy` (端口 11605)

**执行顺序:** P0 本机清理 → P1 rlbox 8 子任务 → P2 五派生并行/串行。单 session 建议 P0+P1.1~P1.4，第二 session P1.5~P1.8，第三 session P2 全家。

**关键实证数据:**
- rlbox 本机 PG lint_schema 当前报 22 ERROR（10 张孤儿表 × 2 类错误 + 12 张 old policy + sessions 0 policy）
- 清污染后仓库真实需要 `rails g rls_policy` 的只剩 `posts` 和 `users` 两张（其余都是本机污染的孤儿）
- sessions 表需删 `data_version` 列 + `index_sessions_on_data_version` 索引

---

## Phase P0: 本机 DB 清理（Gate，15 min）

**目的：** 清掉本机 PG 的 10 张孤儿表 + 25 条幽灵 schema_migrations 记录。不改仓库，不产生 commit。

### Task P0.1: 备份当前 rlbox 本机 DB（保险）

**Files:**
- Create: `/tmp/rlbox_pre_cleanup_backup.sql`

- [ ] **Step 1: 导出当前 DB（留个回退）**

Run:
```bash
pg_dump -h localhost -U postgres myapp_development > /tmp/rlbox_pre_cleanup_backup.sql
ls -la /tmp/rlbox_pre_cleanup_backup.sql
```

Expected: 文件存在，大小 > 0。如果 pg_dump 报 database 不存在，说明早就是干净的，跳过 P0.1 直接 P0.2。

### Task P0.2: 手动 drop+create+migrate 重建

> **注意：** rlbox 当前 `bin/db_init` 是旧版 70 行，不会 drop DB，所以 P0 必须手动 dropdb。P1.1 完成后就有完整的 db_init 可用了。

- [ ] **Step 1: 确认没有进程占用 DB**

Run:
```bash
ps aux | grep -E "rails|puma|psql" | grep -v grep
```

Expected: 没有 myapp_development 相关进程。如有，先 kill 掉。

- [ ] **Step 2: dropdb + createdb**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/rlbox
dropdb -h localhost -U postgres --if-exists myapp_development
dropdb -h localhost -U postgres --if-exists myapp_test
createdb -h localhost -U postgres -T template0 -E UTF8 myapp_development
createdb -h localhost -U postgres -T template0 -E UTF8 myapp_test
```

Expected: 无报错。

- [ ] **Step 3: migrate 把仓库 10 个 migration 跑进干净 DB**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/rlbox
eval "$(rbenv init - bash)"
bundle exec rails db:migrate
```

Expected: 10 个 migration 全绿，无其他 migration。

- [ ] **Step 4: 验证孤儿表已消失**

Run:
```bash
psql -h localhost -U postgres -d myapp_development -c "\dt" | grep -cE "addresses|cart_items|categories|locations|order_items|orders|payment_passwords|product_variants|products|reviews"
```

Expected: 输出 `0`（10 张孤儿表都不存在）。

- [ ] **Step 5: 验证 schema_migrations 行数**

Run:
```bash
psql -h localhost -U postgres -d myapp_development -c "SELECT COUNT(*) FROM schema_migrations;"
```

Expected: `count = 10`（不是 35）。

### Task P0.3: P0 验收 gate

- [ ] **Step 1: lint_schema 确认 10 张孤儿表 ERROR 消失**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/rlbox
eval "$(rbenv init - bash)"
bundle exec rake validator:lint_schema 2>&1 | tail -30
```

Expected: 10 张孤儿表相关的 "has data_version column but no model" ERROR **全部消失**。剩下的 ERROR 只有 `posts` / `users` / `sessions` 的 RLS policy 问题（这些是仓库真实债，P1 修）。

Note: P0 不产生 git commit。继续 P1。

---

## Phase P1: rlbox 底座修复（~2h，单 branch 一次提）

**Branch 约定:** 全部 P1 子任务在同一 branch `chore/tech-debt-cleanup-p1` 上，最后合并为 1 个 commit（或保留子任务 commits 由 reviewer 选择 squash）。

### Task P1.1: 反向同步 bin/db_init（从 Goomart 183 行模板）

**Files:**
- Source: `/Volumes/SengclawWorkspace/code/Goomart/bin/db_init` (183 lines)
- Overwrite: `/Volumes/SengclawWorkspace/code/rlbox/bin/db_init` (currently 70 lines old version)

- [ ] **Step 1: 切 branch**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/rlbox
git checkout -b chore/tech-debt-cleanup-p1
git status  # 应该干净
```

Expected: 在新 branch `chore/tech-debt-cleanup-p1`，working tree clean。

- [ ] **Step 2: 复制 Goomart 的 db_init 到 rlbox**

Run:
```bash
cp /Volumes/SengclawWorkspace/code/Goomart/bin/db_init /Volumes/SengclawWorkspace/code/rlbox/bin/db_init
chmod +x /Volumes/SengclawWorkspace/code/rlbox/bin/db_init
wc -l /Volumes/SengclawWorkspace/code/rlbox/bin/db_init
```

Expected: 文件 183 行。可执行。

- [ ] **Step 3: 改 banner 文字 Goomart → rlbox**

Edit `/Volumes/SengclawWorkspace/code/rlbox/bin/db_init`:
- Find: `'🚀 Goomart 数据库初始化'`
- Replace: `'🚀 rlbox 数据库初始化'`

Also check if comments reference "Goomart" by name (e.g. in doc comments). Replace each occurrence to "rlbox". Logic code must stay identical — only string literals / comments change.

Run verification:
```bash
grep -i "goomart" /Volumes/SengclawWorkspace/code/rlbox/bin/db_init
```

Expected: 输出为空（已全部替换为 rlbox）。

- [ ] **Step 4: 暂不跑（database.yml 还没改，跑了会用旧名字）**

Skip execution for now. Will run in P1.8 verification after database.yml is updated.

- [ ] **Step 5: Commit P1.1**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/rlbox
git add bin/db_init
git commit -m "chore(db_init): reverse-port Goomart's 183-line db_init to rlbox

- adds DROP=1 mode for full rebuild
- creates app_user role with NOSUPERUSER+CREATEDB
- creates dev/test DBs with app_user as owner
- registers app.data_version GUC parameter
- runs migrate + reset_baseline + RLS self-check

Replaces 70-line legacy version that only ran migrate.
Source template: Goomart/bin/db_init"
```

Expected: 1 file changed (bin/db_init), ~113 lines added net.

### Task P1.2: 改 config/database.yml 统一到 ADR-017

**Files:**
- Modify: `/Volumes/SengclawWorkspace/code/rlbox/config/database.yml`

- [ ] **Step 1: 读当前内容确认起点**

Run:
```bash
cat /Volumes/SengclawWorkspace/code/rlbox/config/database.yml
```

Expected: 看到 `database: myapp_development` / `username: postgres` / `password: postgres`。

- [ ] **Step 2: 改 development 段**

Edit `config/database.yml`:
- Find: `database: myapp_development`
- Replace: `database: <%= ENV.fetch('WORKTREE_DEV_DB', 'rlbox_development') %>`
- Find (in development): `username: postgres`
- Replace: `username: app_user`
- (password 保持 `postgres` 不变，符合 ADR-017)

- [ ] **Step 3: 改 test 段**

Edit `config/database.yml`:
- Find: `database: myapp_test`
- Replace: `database: <%= ENV.fetch('WORKTREE_TEST_DB', 'rlbox_test') %>`
- Find (in test): `username: postgres`
- Replace: `username: app_user`

- [ ] **Step 4: 验证 YAML 合法 + ENV.fetch 在位**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/rlbox
eval "$(rbenv init - bash)"
ruby -ryaml -rerb -e "puts YAML.safe_load(ERB.new(File.read('config/database.yml')).result, aliases: true).dig('development', 'database')"
```

Expected: 输出 `rlbox_development`（无 fallback 时的默认值）。

- [ ] **Step 5: Commit P1.2**

Run:
```bash
git add config/database.yml
git commit -m "chore(db): rename to rlbox_development per ADR-017

- myapp_development → rlbox_development (via ENV.fetch WORKTREE_DEV_DB)
- myapp_test → rlbox_test (via ENV.fetch WORKTREE_TEST_DB)
- username postgres → app_user (NOSUPERUSER+CREATEDB for RLS)
- password stays postgres
- adds ENV fallback for box-using-git-worktrees isolation (ADR-011)"
```

Expected: 1 file changed.

### Task P1.3: Migration 删 sessions.data_version 列 + 索引

**Files:**
- Create: `/Volumes/SengclawWorkspace/code/rlbox/db/migrate/YYYYMMDDHHMMSS_drop_data_version_from_sessions.rb`
- Auto-modify: `db/schema.rb`

- [ ] **Step 1: 生成 migration**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/rlbox
eval "$(rbenv init - bash)"
bundle exec rails g migration DropDataVersionFromSessions
```

Expected: `db/migrate/<ts>_drop_data_version_from_sessions.rb` 创建出来，骨架空的。

- [ ] **Step 2: 填充 migration 内容**

Edit the newly created migration file. Replace the body with:

```ruby
class DropDataVersionFromSessions < ActiveRecord::Migration[7.2]
  def change
    remove_index :sessions, name: 'index_sessions_on_data_version', if_exists: true
    remove_column :sessions, :data_version, :string, limit: 50, default: '0', null: false
  end
end
```

Note: `remove_column` 里带上原类型 + 默认值 + null: false 是为了 `down` 可逆。

- [ ] **Step 3: 先重建本机 DB 再 migrate（因为 P0 用旧名字 myapp_development 建了，现在 P1.2 改成 rlbox_development 了）**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/rlbox
eval "$(rbenv init - bash)"
dropdb -h localhost -U postgres --if-exists myapp_development
dropdb -h localhost -U postgres --if-exists myapp_test
# 新 db_init 会建 rlbox_development + rlbox_test，但还没跑过，先手动一次
createdb -h localhost -U postgres -T template0 -E UTF8 rlbox_development
createdb -h localhost -U postgres -T template0 -E UTF8 rlbox_test
bundle exec rails db:migrate
```

Expected: 11 个 migration 全绿（10 原有 + 1 新 drop 列）。

- [ ] **Step 4: 验证 sessions 表无 data_version 列**

Run:
```bash
psql -h localhost -U postgres -d rlbox_development -c "\d sessions"
```

Expected: 列出的字段中**没有** `data_version`，也没有 `index_sessions_on_data_version` 索引。

- [ ] **Step 5: 验证 db/schema.rb 已更新**

Run:
```bash
grep -A 10 'create_table "sessions"' /Volumes/SengclawWorkspace/code/rlbox/db/schema.rb
```

Expected: sessions 的 create_table 块中**不再有** `data_version` 列和 `index_sessions_on_data_version`。

- [ ] **Step 6: Commit P1.3**

Run:
```bash
git add db/migrate/*_drop_data_version_from_sessions.rb db/schema.rb
git commit -m "chore(sessions): drop data_version column (system table, per ADR-003)

sessions is a system table and must NOT carry data_version per ADR-003.
The column was a legacy leftover that caused schema drift warnings in
validator:lint_schema. Matches Goomart/Kangoo/planet/IdleSwap/duvy
where sessions is already clean."
```

Expected: 2 files changed (migration + schema.rb).

### Task P1.4: Session model 补齐三件套

**Files:**
- Modify: `/Volumes/SengclawWorkspace/code/rlbox/app/models/session.rb`

当前 Session 已有 `unscope` + `skip_callback` 两件套，缺 `data_version_excluded!`。

- [ ] **Step 1: 读当前 session.rb**

Run:
```bash
cat /Volumes/SengclawWorkspace/code/rlbox/app/models/session.rb
```

Expected: 看到注释 `# 系统模型，排除 data_version 隔离` 但没有 `data_version_excluded!` 调用。

- [ ] **Step 2: 补齐 data_version_excluded! 宏**

Edit `app/models/session.rb`:
- Find:
```ruby
class Session < ApplicationRecord
  # 系统模型，排除 data_version 隔离
  default_scope { unscope(where: :data_version) }
```
- Replace:
```ruby
class Session < ApplicationRecord
  # 系统模型，三件套排除 data_version 隔离（ADR-003）
  data_version_excluded!
  default_scope { unscope(where: :data_version) }
```

- [ ] **Step 3: 验证 Session 标记为 excluded**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/rlbox
eval "$(rbenv init - bash)"
bundle exec rails runner 'puts DataVersionable.excluded_models.include?(Session)'
```

Expected: 输出 `true`。

- [ ] **Step 4: 验证 Session.create 不 append data_version**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/rlbox
eval "$(rbenv init - bash)"
bundle exec rails runner '
  ActiveRecord::Base.logger = Logger.new(STDOUT)
  User.first || User.create!(email_address: "demo@local", password: "password123")
  s = Session.new(user: User.first, user_agent: "test", ip_address: "127.0.0.1")
  s.save!
  puts "OK"
'
```

Expected: INSERT SQL 里**不包含** data_version 列。

- [ ] **Step 5: Commit P1.4**

Run:
```bash
git add app/models/session.rb
git commit -m "chore(session): add data_version_excluded! for complete trio (ADR-003)

Previously only had unscope + skip_callback (2/3 trio).
Adding data_version_excluded! completes the system-table trio so
validator:lint_schema can correctly identify Session as system-table."
```

Expected: 1 file changed.

---

## Phase P1.5-P1.8: rlbox RLS + lint_schema 精修 + ADR-017 + 验收

### Task P1.5: 业务表跑 rails g rls_policy（posts + users）

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_rls_policy_posts.rb`（由 generator 生成）
- Create: `db/migrate/YYYYMMDDHHMMSS_rls_policy_users.rb`（由 generator 生成）
- Auto-modify: `db/schema.rb`

**说明：** P0 + P1.3 清理后，rlbox 仓库里带 `data_version` 列且需要 4-op policy 的业务表只剩 `posts` 和 `users`（sessions 已删列；10 张孤儿表已清）。

- [ ] **Step 1: 跑 generator for posts**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/rlbox
eval "$(rbenv init - bash)"
bundle exec rails g rls_policy posts
```

Expected: 在 `db/migrate/` 生成新 migration `<ts>_rls_policy_posts.rb`，包含 4 个 CREATE POLICY（select/insert/update/delete）+ 1 个 DROP POLICY（旧 FOR ALL）。

- [ ] **Step 2: 跑 generator for users**

Run:
```bash
bundle exec rails g rls_policy users
```

Expected: 在 `db/migrate/` 生成新 migration `<ts>_rls_policy_users.rb`。

- [ ] **Step 3: migrate 两个 new migration 到本机 DB**

Run:
```bash
bundle exec rails db:migrate
```

Expected: 2 个 migration 全绿。

- [ ] **Step 4: 验证 posts / users 各有 4 条 policy**

Run:
```bash
psql -h localhost -U postgres -d rlbox_development -c "SELECT tablename, policyname, cmd FROM pg_policies WHERE tablename IN ('posts', 'users') ORDER BY tablename, cmd;"
```

Expected: 每张表 4 行（SELECT / INSERT / UPDATE / DELETE 各一条），共 8 行。

- [ ] **Step 5: test DB 同步**

Run:
```bash
bundle exec rails db:test:prepare
psql -h localhost -U postgres -d rlbox_test -c "SELECT tablename, COUNT(*) FROM pg_policies WHERE tablename IN ('posts', 'users') GROUP BY tablename;"
```

Expected: posts 4 条，users 4 条。

- [ ] **Step 6: Commit P1.5**

Run:
```bash
git add db/migrate/*_rls_policy_posts.rb db/migrate/*_rls_policy_users.rb db/schema.rb
git commit -m "chore(rls): split FOR ALL policy into 4-op for posts/users (ADR-014)

Old single FOR ALL policy did not enforce granular data_version
checks on different ops. New 4-op split (SELECT/INSERT/UPDATE/DELETE)
matches ADR-014 and the rls_policy generator output.

Only posts and users need migration — sessions has had its data_version
column dropped in P1.3; remaining 10 orphan tables were polluted local
state now cleaned (P0)."
```

Expected: 3 files changed (2 migrations + schema.rb).

### Task P1.6: 精修 lint_schema 文案

**Files:**
- Modify: `/Volumes/SengclawWorkspace/code/rlbox/lib/tasks/validator.rake:455-456`

- [ ] **Step 1: 看当前文案**

Run:
```bash
sed -n '450,460p' /Volumes/SengclawWorkspace/code/rlbox/lib/tasks/validator.rake
```

Expected: 看到 `errors << "Table '#{t}' has 'data_version' column but no model includes DataVersionable for it ..."`.

- [ ] **Step 2: 替换文案**

Edit `lib/tasks/validator.rake`. 找到这段（约 454-457 行）：
```ruby
    not_registered = db_tables_with_column - registered_tables
    not_registered.each do |t|
      errors << "Table '#{t}' has `data_version` column but no model includes DataVersionable for it " \
                '(SELECT will leak across sessions, writes will bypass set_data_version callback)'
    end
```

替换为：
```ruby
    not_registered = db_tables_with_column - registered_tables
    not_registered.each do |t|
      errors << "Table '#{t}' has `data_version` column but cannot locate a Ruby model auto-registered via DataVersionable. " \
                'Possible causes: (1) Ruby model file missing under app/models/ — table may be residual from a polluted DB, ' \
                "run 'DROP=1 bin/db_init' to rebuild; " \
                '(2) Ruby class name does not match table-name convention; ' \
                '(3) Model file exists but not loaded (Zeitwerk autoloader issue).'
    end
```

- [ ] **Step 3: 跑 lint_schema 确认文案生效**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/rlbox
eval "$(rbenv init - bash)"
bundle exec rake validator:lint_schema 2>&1 | tail -20
```

Expected: 此时 DB 已经干净（posts/users 都有 4-op 了，sessions 无 data_version），应该**输出 0 ERROR**。如果为了验证文案想人工制造一次 error，按 Step 4 做（可选）。

- [ ] **Step 4（可选）: 人工制造孤儿表验证新文案**

Run:
```bash
psql -h localhost -U postgres -d rlbox_development -c "CREATE TABLE fake_orphan (id serial PRIMARY KEY, data_version varchar DEFAULT '0' NOT NULL);"
bundle exec rake validator:lint_schema 2>&1 | grep -A 5 fake_orphan
psql -h localhost -U postgres -d rlbox_development -c "DROP TABLE fake_orphan;"
```

Expected: 看到新文案的三条 possible causes 提示。然后清理 fake_orphan。

- [ ] **Step 5: Commit P1.6**

Run:
```bash
git add lib/tasks/validator.rake
git commit -m "chore(lint): improve orphan-table error message with 3 possible causes

Old message 'no model includes DataVersionable' misled users into
adding 'include DataVersionable' when the real cause was a polluted
DB (residual tables from another project) or a missing Ruby file.
New message lists 3 possibilities with concrete next steps."
```

Expected: 1 file changed.

### Task P1.7: 写 ADR-017（Database Naming Convention）

**Files:**
- Create: `/Volumes/SengclawWorkspace/code/rlbox/docs/decisions/ADR-017-database-naming-and-db-init.md`
- Modify: `/Volumes/SengclawWorkspace/code/rlbox/docs/decisions/INDEX.md`（加一行）
- Modify: `/Volumes/SengclawWorkspace/code/rlbox/CLAUDE.md`（路由表加一行）

- [ ] **Step 1: 创建 ADR-017**

Create `docs/decisions/ADR-017-database-naming-and-db-init.md` with content:

```markdown
---
topic: ADR-017
updated_at: 2026-05-03
status: Accepted
related:
  - ADR-011-bin-dev-loads-dotenv.md
  - ADR-003-system-tables-trio.md
supersedes: []
---

# ADR-017: Database Naming Convention

## Context

rlbox 生态下 6 个项目（rlbox 底座 + Goomart + planet + IdleSwap + Kangoo + duvy）历史上 `config/database.yml` 各自演化，出现五种不同风格：

- rlbox: `myapp_development` / `myapp_test` + `postgres/postgres`（Rails 出厂默认）
- Goomart: `goomart_db` / `goomart_test` + `goomart/goomart`
- planet/IdleSwap: `<slug>_db` / `<slug>_test` + `app_user/postgres`
- Kangoo: `kangoo_development` / `kangoo_test` + `app_user/postgres`
- duvy: `duvy_db` / `duvy_test` + `app_user/duvy`

问题:
1. rlbox 默认 `myapp_development` 是 Rails 出厂值，任何 fork 忘记改就会和其他 fork **共享同一个 PG database**（撞车事故已发生，见 2026-05-03 10 张孤儿表污染事件）。
2. 命名风格不统一，跨项目切换心智成本大。
3. username/password 不统一，`bin/db_init` 脚本要做大量 if-else 兼容。

## Decision

**rlbox 生态统一 database 命名约定：**

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
```

**规则：**
1. DB 名后缀: dev 用 `_development`, test 用 `_test`（Rails 官方标准，左右对称）
2. slug 来源: 每个项目**硬编码**自己的 slug = 项目仓库文件夹名的小写形式
3. ENV fallback: `WORKTREE_DEV_DB` / `WORKTREE_TEST_DB` 走 box-using-git-worktrees 的多 worktree 隔离（ADR-011）
4. username 统一 `app_user`（NOSUPERUSER + CREATEDB 角色，RLS 生效必需）
5. password 统一 `postgres`（本地 dev/test，无安全含义）
6. `template: template0` 避免继承 template1 的 locale 设置

**各项目 slug 映射表：**

| 项目 | slug | dev DB | test DB |
|---|---|---|---|
| rlbox | `rlbox` | `rlbox_development` | `rlbox_test` |
| Goomart | `goomart` | `goomart_development` | `goomart_test` |
| planet | `planet` | `planet_development` | `planet_test` |
| IdleSwap | `idleswap` | `idleswap_development` | `idleswap_test` |
| Kangoo | `kangoo` | `kangoo_development` | `kangoo_test` |
| duvy | `duvy` | `duvy_development` | `duvy_test` |

## Consequences

**Positive:**
- Fork 新项目时只需改 database.yml 的 slug（1 处），其他 boilerplate 不变
- `bin/db_init` 脚本不需要 per-project 适配
- 跨项目切换心智一致（`<slug>_development/test` 永远对称）

**Negative:**
- 5 个派生项目需要各自迁移（一次性，后续不再有）
- production `DATABASE_URL` 不受此约定影响（由 Railway 注入）

**Migration:**
- rlbox: `myapp_development` → `rlbox_development`（本 plan P1.2 执行）
- Goomart: `goomart_db` → `goomart_development`（本 plan P2.1 执行）
- planet: `planet_db` → `planet_development`（P2.2）
- IdleSwap: `idleswap_db` → `idleswap_development`（P2.3）
- Kangoo: 已经是 `kangoo_development`（P2.4 只补 ENV.fetch）
- duvy: `duvy_db` → `duvy_development`（P2.5）

## Notes

- `config/appname.txt` 是**中文展示名**（"我购market"），与 slug 解耦，各自演化
- fork 新项目的 checklist：`echo "<slug>_development" | ...` 替换 database.yml 第一行
```

- [ ] **Step 2: 更新 docs/decisions/INDEX.md**

找 INDEX.md 的 ADR 表格（ADR-016 所在行），在下面加一行:

```markdown
| `ADR-017` | Database Naming Convention | Accepted | 2026-05-03 |
```

- [ ] **Step 3: 更新 CLAUDE.md 路由表**

在 CLAUDE.md 的 "📍 Documentation Map" 表格中加一行（建议放在"新分支初始化/部署"之后）：

```markdown
| **Fork 新项目 / database 命名** | `docs/decisions/ADR-017-database-naming-and-db-init.md` | P1 |
```

- [ ] **Step 4: 验证所有文档能解析**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/rlbox
eval "$(rbenv init - bash)"
bundle exec rake docs:lint 2>&1 | tail -20
```

Expected: 输出 `✅ All docs checks passed.` 或等价成功信息。

- [ ] **Step 5: Commit P1.7**

Run:
```bash
git add docs/decisions/ADR-017-database-naming-and-db-init.md docs/decisions/INDEX.md CLAUDE.md
git commit -m "docs(ADR-017): formalize database naming convention across rlbox ecosystem

<slug>_development / <slug>_test + app_user/postgres + ENV fallback.
Decouples slug (tech identifier) from appname.txt (Chinese display name).
Migration table lists which project needs which change (P2 executes)."
```

Expected: 3 files changed.

### Task P1.8: 一把梭验收 + 主 commit

- [ ] **Step 1: 用新 bin/db_init 跑 DROP=1 重建**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/rlbox
eval "$(rbenv init - bash)"
DROP=1 bin/db_init 2>&1 | tail -40
```

Expected: 看到 5 个 Step 的 ✓ 标记（app_user 建好 + dev/test DB 建好 + migrate + reset_baseline + RLS self-check）。

- [ ] **Step 2: lint_schema 必须 0 ERROR**

Run:
```bash
bundle exec rake validator:lint_schema
echo "exit: $?"
```

Expected: `exit: 0`，并且输出包含 `✅ All schema integrity checks passed.`（或等价成功文案）。

- [ ] **Step 3: rake test 全绿**

Run:
```bash
bundle exec rake test 2>&1 | tail -20
```

Expected: 0 failures, 0 errors。如果有 RSpec:

```bash
bundle exec rspec 2>&1 | tail -10
```

Expected: all passing。

- [ ] **Step 4: 手动访问首页**

Run:
```bash
bin/dev &
sleep 5
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/
kill %1
```

Expected: `200`（或 302 到登录页，只要不是 500）。

- [ ] **Step 5: 推送 branch**

Run:
```bash
git push -u origin chore/tech-debt-cleanup-p1
```

Expected: branch 推上去。用户可以开 PR merge 或本地 fast-forward 到 main。

- [ ] **Step 6: P1 阶段完成打卡**

不额外 commit。P1.1~P1.7 已各自 commit，branch 有 7 个 commit 记录。

---

## Phase P2: 派生项目同步（5 家，各自独立 PR，~2h）

**策略：** 每家按相同 5 步流程（改 database.yml + DROP=1 重建 + lint_schema 0 error + test + push PR），差异仅在 database.yml 改哪几行。各家独立 branch + 独立 PR，互不影响，可并行执行。

**通用前置条件：**
- rlbox P1 已全部完成（ADR-017 已 commit），派生项目才可引用它
- rbenv 在 PATH 中: `eval "$(rbenv init - bash)"`

### Task P2.1: Goomart 同步（改动最多：database 名 + username + password）

**仓库：** `/Volumes/SengclawWorkspace/code/Goomart`
**目标:** database `goomart_db` → `goomart_development`；username `goomart` → `app_user`；password `goomart` → `postgres`。

- [ ] **Step 1: 切 branch**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/Goomart
git checkout main
git pull
git status  # 必须 clean
git checkout -b chore/adr-017-database-naming
```

Expected: 在新 branch。

- [ ] **Step 2: 备份当前 DB（保险）**

Run:
```bash
pg_dump -h localhost -U postgres goomart_db > /tmp/goomart_pre_adr017_backup.sql 2>/dev/null || echo "DB not exist, skip backup"
```

Expected: 文件存在或明确跳过。

- [ ] **Step 3: 改 config/database.yml**

Edit `config/database.yml`:

development 段:
- Find: `database: <%= ENV.fetch('WORKTREE_DEV_DB', 'goomart_db') %>`
- Replace: `database: <%= ENV.fetch('WORKTREE_DEV_DB', 'goomart_development') %>`
- Find: `username: goomart`
- Replace: `username: app_user`
- Find: `password: goomart`
- Replace: `password: postgres`

test 段:
- Find: `database: <%= ENV.fetch('WORKTREE_TEST_DB', 'goomart_test') %>`
- Replace: `database: <%= ENV.fetch('WORKTREE_TEST_DB', 'goomart_test') %>`（已正确，确认即可）
- Find: `username: goomart`
- Replace: `username: app_user`
- Find: `password: goomart`
- Replace: `password: postgres`

- [ ] **Step 4: DROP=1 bin/db_init 重建到新名字**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/Goomart
eval "$(rbenv init - bash)"
DROP=1 bin/db_init 2>&1 | tail -30
```

Expected: 创建 `goomart_development` + `goomart_test`（旧的 `goomart_db` 会被 DROP）。

- [ ] **Step 5: 验证新 DB 存在 + lint_schema 0 error**

Run:
```bash
psql -h localhost -U postgres -l | grep -E "goomart_(development|test)"
bundle exec rake validator:lint_schema
echo "exit: $?"
```

Expected: 两行 DB 都在；lint_schema exit 0。

- [ ] **Step 6: rake test 全绿**

Run:
```bash
bundle exec rake test 2>&1 | tail -10
```

Expected: 0 failures, 0 errors。如果项目是 RSpec：

```bash
bundle exec rspec 2>&1 | tail -10
```

Expected: all passing。

- [ ] **Step 7: 清理旧 DB（可选，完成验证后执行）**

Run:
```bash
dropdb -h localhost -U postgres --if-exists goomart_db
```

Expected: 成功。

- [ ] **Step 8: Commit + push + PR**

Run:
```bash
git add config/database.yml
git commit -m "chore(db): adopt ADR-017 database naming convention

- goomart_db → goomart_development (Rails-standard _development suffix)
- username goomart → app_user (unified across rlbox ecosystem)
- password goomart → postgres (unified)

Local migration: DROP=1 bin/db_init rebuilt into new DBs.
Per rlbox/docs/decisions/ADR-017-database-naming-and-db-init.md"
git push -u origin chore/adr-017-database-naming
```

Expected: branch 推上去，CI 通过后可 merge。

### Task P2.2: planet 同步（改动：只 database 名）

**仓库：** `/Volumes/SengclawWorkspace/code/planet`
**目标:** database `planet_db` → `planet_development`。username/password 已经是 `app_user/postgres`，无需改。

- [ ] **Step 1: 切 branch + 备份**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/planet
git checkout main && git pull
git checkout -b chore/adr-017-database-naming
pg_dump -h localhost -U postgres planet_db > /tmp/planet_pre_adr017_backup.sql 2>/dev/null || echo "skip"
```

- [ ] **Step 2: 改 config/database.yml**

Edit `config/database.yml`:
- Find: `database: <%= ENV.fetch('WORKTREE_DEV_DB', 'planet_db') %>`
- Replace: `database: <%= ENV.fetch('WORKTREE_DEV_DB', 'planet_development') %>`

test 段 `planet_test` 保持不变。

- [ ] **Step 3: DROP=1 重建**

Run:
```bash
eval "$(rbenv init - bash)"
DROP=1 bin/db_init 2>&1 | tail -20
```

Expected: 创建 `planet_development` + `planet_test`（旧 `planet_db` DROP）。

- [ ] **Step 4: 验证**

Run:
```bash
bundle exec rake validator:lint_schema
echo "exit: $?"
bundle exec rake test 2>&1 | tail -10
```

Expected: 两个都 exit 0。

- [ ] **Step 5: 清理旧 DB**

Run:
```bash
dropdb -h localhost -U postgres --if-exists planet_db
```

- [ ] **Step 6: Commit + push**

Run:
```bash
git add config/database.yml
git commit -m "chore(db): adopt ADR-017 database naming convention

planet_db → planet_development (Rails-standard _development suffix).
username/password already match ADR-017 (app_user/postgres)."
git push -u origin chore/adr-017-database-naming
```

### Task P2.3: IdleSwap 同步（改动：只 database 名）

**仓库：** `/Volumes/SengclawWorkspace/code/IdleSwap`
**目标:** database `idleswap_db` → `idleswap_development`。

- [ ] **Step 1: 切 branch + 备份**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/IdleSwap
git checkout main && git pull
git checkout -b chore/adr-017-database-naming
pg_dump -h localhost -U postgres idleswap_db > /tmp/idleswap_pre_adr017_backup.sql 2>/dev/null || echo "skip"
```

- [ ] **Step 2: 改 config/database.yml**

Edit `config/database.yml`:
- Find: `database: <%= ENV.fetch('WORKTREE_DEV_DB', 'idleswap_db') %>`
- Replace: `database: <%= ENV.fetch('WORKTREE_DEV_DB', 'idleswap_development') %>`

test 段 `idleswap_test` 保持不变。

- [ ] **Step 3: DROP=1 重建**

Run:
```bash
eval "$(rbenv init - bash)"
DROP=1 bin/db_init 2>&1 | tail -20
```

- [ ] **Step 4: 验证**

Run:
```bash
bundle exec rake validator:lint_schema
echo "exit: $?"
bundle exec rake test 2>&1 | tail -10
```

Expected: 两个都 exit 0。

- [ ] **Step 5: 清理旧 DB + commit + push**

Run:
```bash
dropdb -h localhost -U postgres --if-exists idleswap_db
git add config/database.yml
git commit -m "chore(db): adopt ADR-017 database naming convention

idleswap_db → idleswap_development."
git push -u origin chore/adr-017-database-naming
```

### Task P2.4: Kangoo 同步（改动最少：只确认 ENV.fetch 存在）

**仓库：** `/Volumes/SengclawWorkspace/code/Kangoo`
**目标:** Kangoo 的 dev DB 已经是 `kangoo_development`（符合 ADR-017）。只需确认 `ENV.fetch` fallback 在位；如果在位就零改动，只做验证。

- [ ] **Step 1: 切 branch**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/Kangoo
git checkout main && git pull
git checkout -b chore/adr-017-database-naming
```

- [ ] **Step 2: 检查 database.yml 是否合 ADR-017**

Run:
```bash
cat config/database.yml
```

检查项：
- dev 段 `database:` 值是否为 `<%= ENV.fetch('WORKTREE_DEV_DB', 'kangoo_development') %>`
- test 段 `database:` 值是否为 `<%= ENV.fetch('WORKTREE_TEST_DB', 'kangoo_test') %>`
- username: app_user
- password: postgres

如果有任一项不符，按 ADR-017 修正。如果全部符合，跳到 Step 4。

- [ ] **Step 3（条件执行）: 补齐 ENV.fetch**

如 Step 2 发现 database 是硬编码 `kangoo_development` 而没 ENV.fetch，改为:

Edit `config/database.yml`:
- Find: `database: kangoo_development`
- Replace: `database: <%= ENV.fetch('WORKTREE_DEV_DB', 'kangoo_development') %>`
- Find: `database: kangoo_test`
- Replace: `database: <%= ENV.fetch('WORKTREE_TEST_DB', 'kangoo_test') %>`

- [ ] **Step 4: DROP=1 重建（幂等验证）**

Run:
```bash
eval "$(rbenv init - bash)"
DROP=1 bin/db_init 2>&1 | tail -20
```

Expected: 重建成功。

- [ ] **Step 5: 验证**

Run:
```bash
bundle exec rake validator:lint_schema
echo "exit: $?"
bundle exec rake test 2>&1 | tail -10
```

Expected: 两个都 exit 0。

- [ ] **Step 6: Commit（如有改动）或记录无改动**

如 Step 3 有改动:
```bash
git add config/database.yml
git commit -m "chore(db): add ENV.fetch fallback per ADR-017

Ensures WORKTREE_DEV_DB / WORKTREE_TEST_DB env overrides work
for box-using-git-worktrees isolation (ADR-011)."
git push -u origin chore/adr-017-database-naming
```

如无改动，直接记录 "Kangoo already compliant with ADR-017" 在 commit log 或跳过 push。

### Task P2.5: duvy 同步（改动：database 名 + password）

**仓库：** `/Volumes/SengclawWorkspace/code/duvy`
**目标:** database `duvy_db` → `duvy_development`；password `duvy` → `postgres`。

- [ ] **Step 1: 切 branch + 备份**

Run:
```bash
cd /Volumes/SengclawWorkspace/code/duvy
git checkout main && git pull
git checkout -b chore/adr-017-database-naming
pg_dump -h localhost -U postgres duvy_db > /tmp/duvy_pre_adr017_backup.sql 2>/dev/null || echo "skip"
```

- [ ] **Step 2: 改 config/database.yml**

Edit `config/database.yml`:

development 段:
- Find: `database: <%= ENV.fetch('WORKTREE_DEV_DB', 'duvy_db') %>`
- Replace: `database: <%= ENV.fetch('WORKTREE_DEV_DB', 'duvy_development') %>`
- Find (dev): `password: duvy`
- Replace: `password: postgres`

test 段:
- `duvy_test` 保持不变
- Find (test): `password: duvy`
- Replace: `password: postgres`

- [ ] **Step 3: DROP=1 重建**

Run:
```bash
eval "$(rbenv init - bash)"
DROP=1 bin/db_init 2>&1 | tail -20
```

Expected: 创建 `duvy_development` + `duvy_test`。

- [ ] **Step 4: 验证**

Run:
```bash
bundle exec rake validator:lint_schema
echo "exit: $?"
bundle exec rake test 2>&1 | tail -10
```

Expected: 两个都 exit 0。

- [ ] **Step 5: 清理旧 DB + commit + push**

Run:
```bash
dropdb -h localhost -U postgres --if-exists duvy_db
git add config/database.yml
git commit -m "chore(db): adopt ADR-017 database naming convention

- duvy_db → duvy_development
- password duvy → postgres (unified across rlbox ecosystem)"
git push -u origin chore/adr-017-database-naming
```

---

## Phase P3: 生态验收（5 min）

### Task P3.1: 6 家齐步 lint_schema 0 error

- [ ] **Step 1: 扫 6 家**

Run:
```bash
for d in rlbox Goomart planet IdleSwap Kangoo duvy; do
  echo "=== $d ==="
  cd /Volumes/SengclawWorkspace/code/$d
  eval "$(rbenv init - bash)"
  bundle exec rake validator:lint_schema 2>&1 | tail -3
  echo ""
done
```

Expected: 6 家全部 `✅ All schema integrity checks passed.`（或 exit 0）。

### Task P3.2: TODO.md 记录

- [ ] **Step 1: 更新个人 TODO.md**

Edit `~/clacky_workspace/TODO.md`，在对应日期下追加:

```markdown
## 2026-05-03 完成
- ✅ rlbox 生态技术债清理（7 项）：本机 DB 清污染、RLS policy 4-op 迁移、sessions 去 data_version、lint_schema 文案精修、bin/db_init 反向同步 Goomart 183 行版、ADR-017 database 命名约定、5 派生项目统一 database.yml
- Spec: rlbox/docs/architecture/2026-05-03-tech-debt-cleanup-spec.md
- Plan: rlbox/docs/architecture/2026-05-03-tech-debt-cleanup-plan.md
```

Note: 本步手动执行，不产生代码 commit。

---

## 自检清单

**Spec 覆盖：**
- [x] 债 #1 本机 DB 污染 → P0
- [x] 债 #2 RLS policy 旧 FOR ALL → P1.5
- [x] 债 #3 sessions data_version 列 → P1.3 + P1.4
- [x] 债 #4 lint_schema 文案 → P1.6
- [x] 债 #5 database.yml 默认值 → P1.2
- [x] 债 #6 bin/db_init 落后 → P1.1
- [x] 债 #7 5 派生项目不统一 → P2.1-P2.5

**Non-Goals 合规：**
- [x] 不重构 RLS 业务语义（只做 format 迁移）
- [x] 不动 agent_tasks / linear_installations / project_mappings
- [x] 不碰 production DATABASE_URL

**执行顺序依赖:**
- P0 → P1.1（P0 不依赖 P1）
- P1.1 → P1.2（db_init 先在位，再改 yml，才能跑 DROP=1）
- P1.2 → P1.3（先改 yml 建新 DB，再跑 migration）
- P1.3 → P1.4（先删列再改 model，避免中间态）
- P1.4 → P1.5（三件套齐全 + 列删完后，剩下业务表再刷 policy）
- P1.5 → P1.6（先把真实 ERROR 清掉，再改文案）
- P1.6 → P1.7（ADR 引用新文案）
- P1.7 → P1.8（ADR 已存在，验收可引用）
- P1.8 → P2.* （P1 完整后才到派生项目）

**回滚路径:**
- P0: restore /tmp/rlbox_pre_cleanup_backup.sql（`psql -U postgres myapp_development < /tmp/...`）
- P1.1-P1.8: 单个 branch，`git reset --hard HEAD~N` 或 `git branch -D chore/tech-debt-cleanup-p1`
- P2.*: 每家独立 branch，各自 `git reset --hard` + restore backup

---

## Execution Handoff

此 plan 已准备好执行。建议：

1. **Session 1 (1h):** P0 + P1.1~P1.4
2. **Session 2 (1.5h):** P1.5~P1.8
3. **Session 3 (2h):** P2.1~P2.5 + P3

用 `box:executing-plans` skill 逐 task 执行，每个 Step 作为 checkbox 勾选推进，遇到意外立刻暂停让用户决策。

