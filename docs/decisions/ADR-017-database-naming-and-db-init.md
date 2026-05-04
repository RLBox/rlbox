---
topic: adr-017
updated_at: 2026-05-03
status: accepted
decision_date: 2026-05-03
supersedes: none
related:
  - decisions/ADR-016-lint-schema-consistency.md
  - conventions/environment.md
  - conventions/new-branch.md
---

# ADR-017 数据库命名 & `bin/db_init` 统一

## Status
✅ **Accepted** — 2026-05-03

## Context

rlbox 生态（rlbox 底座 + Goomart / IdleSwap / Kangoo / planet / duvy 五个派生项目）有 6 份 `config/database.yml`，**字段命名、账号、初始化流程全部不统一**，造成了一连串人肉问题：

### 问题 1：数据库名大杂烩

| 项目 | dev DB | test DB | username |
|---|---|---|---|
| rlbox | `myapp_development` | `myapp_test` | `postgres`（superuser） |
| Goomart | `goomart_development` | `goomart_test` | `app_user` |
| IdleSwap | `idleswap_development` | `idleswap_test` | `app_user` |
| Kangoo | `kangoo_development` | `kangoo_test` | `app_user` |
| planet | `planet_development` | `planet_test` | `app_user` |
| duvy | `duvy_development` | `duvy_test` | `app_user` |

**rlbox 是"新 fork 的模板"，却是唯一一个**：
- 数据库名用万金油 `myapp_*`
- 账号用 postgres superuser（RLS FORCE 对 superuser 不生效 → 静默漏洞）

结果：每次从 rlbox fork 新项目，开发者要手工改名、改账号、重建库，容易漏。

### 问题 2：`bin/db_init` 四分五裂

Goomart 早期沉淀了一份非常靠谱的 `bin/db_init`（160 行），功能：
- 自动创建 `app_user`（非 superuser，RLS 能 FORCE）
- 自动创建 dev/test DB 并 chown 给 `app_user`
- `DROP=1` 支持完全重建（事故排查利器）
- 自检：数据库里 `biz_tables > 0` 但 `pg_policies` 数量为 0 → warn（RLS 没装上）
- 自检：`data_version` 列数不等于业务表数 → warn
- 支持 worktree 环境变量 `WORKTREE_DEV_DB / WORKTREE_TEST_DB`（ADR-012 + box-worktree-rails-setup）

其他四个派生项目只是 **复制了 Goomart 的 db_init**，小改品牌字符串。rlbox **底座的 `bin/db_init` 只有 70 行**，没自检，没 DROP 支持，没 worktree 支持——**最原始的源头反而最残缺**。

### 问题 3：worktree 隔离缺失

rlbox 基础 `config/database.yml` 没有 `ENV.fetch('WORKTREE_DEV_DB', ...)` 切换，意味着：
- 用 `git worktree` 开并行分支调试时，两个 worktree 会共享同一张 dev DB
- 一个 worktree 跑 migrate，另一个立即炸
- box-worktree-rails-setup 这个 skill 在 rlbox 上跑会失败（它依赖这个 pattern）

## Decision

**统一到"Goomart 现状"作为生态基线**，并反哺回 rlbox 底座。

### 命名约定

| 字段 | 值 |
|---|---|
| dev DB | `<slug>_development`（其中 `<slug>` 是项目名小写，如 `rlbox`、`goomart`、`duvy`） |
| test DB | `<slug>_test` |
| username | `app_user`（**非 superuser**，保证 RLS `FORCE ROW LEVEL SECURITY` 生效） |
| password | `app_password`（dev/test 环境常量；production 走 ENV） |

### `config/database.yml` 模板

```yaml
development:
  <<: *default
  database: <%= ENV.fetch('WORKTREE_DEV_DB', '<slug>_development') %>
  username: app_user
  password: app_password

test:
  <<: *default
  database: <%= ENV.fetch('WORKTREE_TEST_DB', '<slug>_test') %>
  username: app_user
  password: app_password
```

### `bin/db_init` 统一来源

rlbox 底座维护**唯一一份正版** `bin/db_init`，内容沉淀自 Goomart。派生项目 fork 后**不需要**再自己维护 db_init 脚本，直接用底座版本。

品牌名从 `config/appname.txt` 动态读取（而不是硬编码 "🚀 Goomart"），保证泛化。

### 自检降级策略

rlbox 底座初始只有 2 张业务表（posts + users），fresh install 的时候 `policies.zero?` 很正常。所以自检要：

- **biz_tables > 0 且 policies.zero?** → warn（"你可能忘了跑 rls_policy migration"）
- **policies / biz_tables ratio 明显异常**（如 2 张表只有 1 条 policy）→ warn
- **不 abort**（warn 已经足够刺眼，abort 会让新手 fork 完就卡死）

原则：**让警告响亮，但不阻塞开发流程**。

## Consequences

### 好的

1. **新 fork 零改配置**：`echo "MyApp" > config/appname.txt && bin/db_init` 即可跑起来
2. **RLS 默认生效**：不再遇到"用 postgres 账号 RLS 无效"的坑
3. **worktree 并行开发**：`WORKTREE_DEV_DB=myapp_dev2 bin/dev` 即可开新分支调试
4. **排查利器**：`DROP=1 bin/db_init` 一键重建
5. **lint_schema 启动可信**：`bin/db_init` 末尾自动跑 `validator:lint_schema`，创完库立刻知道 schema 完整性

### 需要注意的

1. **派生项目要迁移**：每个项目需要在自己的分支上把 db_init + database.yml 同步到底座版本（见下方 Migration Path）
2. **rlbox 底座的 `config/database.yml` 是 gitignored**：git 跟踪的是 `config/database.yml.example`（派生项目目录里直接跟踪 `database.yml` 本身）
3. **老的 `myapp_*` 数据库**：rlbox 老开发者要手工 `DROP DATABASE myapp_development; DROP DATABASE myapp_test;` 清理，新开发者无感知

### Migration Path（派生项目）

每个派生项目需要：

```bash
# 1. 拉最新 rlbox 底座的 bin/db_init（作者自己判断是否相关改动）
git fetch rlbox-upstream master
git show rlbox-upstream/master:bin/db_init > bin/db_init
chmod +x bin/db_init

# 2. 把 database.yml 里 WORKTREE_DEV_DB 支持补上（如果还没）
# 3. 跑一次 DROP=1 bin/db_init 确认没问题
DROP=1 bin/db_init

# 4. rake validator:lint_schema 必须全绿
bundle exec rake validator:lint_schema
```

## Implementation

### 反哺 rlbox（已完成）

- `bin/db_init` 从 Goomart 版本 port 回来，泛化品牌字符串
- `config/database.yml.example` 改为 `rlbox_<env>` + `app_user` + `WORKTREE_DEV_DB`
- 见 commit `da71500`（P1.1）、`5fdafa1`（P1.2）

### 派生项目同步（进行中）

- Goomart / IdleSwap / Kangoo / planet / duvy 各自开分支 `chore/adr-017-database-naming`
- 见 2026-05-03-tech-debt-cleanup-plan.md Phase P2

## References

- `bin/db_init`（rlbox 底座，单一可信源）
- `config/database.yml.example`（rlbox 底座模板）
- ADR-016：lint_schema（db_init 收尾会调用它）
- box-worktree-rails-setup skill：依赖本 ADR 的 ENV.fetch pattern
