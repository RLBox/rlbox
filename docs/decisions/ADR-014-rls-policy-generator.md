---
topic: adr-014
updated_at: 2026-05-03
status: accepted
decision_date: 2026-05-03
supersedes: none
related:
  - architecture/data-version.md
  - conventions/adding-models.md
  - decisions/ADR-001-all-business-tables-have-data-version.md
---

# ADR-014 `rails g rls_policy` Generator

## Status
✅ **Accepted** — 2026-05-03

## Context

rlbox 生态（Goomart / IdleSwap / Kangoo / planet / duvy）的 RLS（Row-Level Security）由两条 base migration 建立：

1. `enable_rls_on_business_tables.rb` — 扫描当时已存在的业务表，为每张表装上 1 条 `FOR ALL` policy
2. `split_rls_policies_by_operation.rb` — 把 `FOR ALL` 拆成 4 条（select / insert / update / delete），并给 INSERT/UPDATE/DELETE 加上 `app.baseline_loading='on'` 豁免

**两条 migration 都是"快照式扫描"**：跑的时候扫一次 `connection.tables`，写入 policy，然后结束。**后来新增的业务表（次日加的 `comments` / `likes`、迭代加的 `feed_products` 等）不会被回补。**

### 事故案例：planet 的 `comments` / `likes`

planet 项目在 split migration 之后新增了 `comments` 和 `likes` 表，结果：

- ✅ 表有 `data_version` 列（`rails g model` 的默认）
- ✅ 模型 include DataVersionable（应用层 default_scope 生效）
- ❌ 数据库层：`comments_version_policy`（旧的 FOR ALL）还在，`*_{select,insert,update,delete}_policy` 从未创建
- ❌ 结果：agent 在自己 session 里能 UPDATE/DELETE **baseline (data_version='0') 行**，彻底污染底座

`rake validator:lint_schema` 会把这种情况标为 ERROR（见 ADR-014 关联的 lint_schema 反哺提交），但 **lint 只是发现问题，不提供修复**。每个 agent 还得手写一个"backfill migration"—— 几乎重复相同的 90 行 DDL，改 3 处表名，容易抄错。

### 需求

提供一个 **单表级** 的 generator：
- 输入：表名（复数，和 PG 里存的一致）
- 输出：幂等的 migration 文件，装 4 条 op-split policy
- 安全：即使反复跑也不报错（先 DROP IF EXISTS）
- 兼容：同时 DROP 旧的 `<table>_version_policy` (FOR ALL)

## Decision

新增 `lib/generators/rls_policy/`：

```
rails_policy_generator.rb      # 继承 ActiveRecord::Generators::Base
templates/migration.rb.tt      # ERB 模板
USAGE                          # help 文档
```

### 使用方式

```bash
# 场景 1：新业务表（rails g model 后立即装 policy）
bin/rails g model comment body:text post:references
bin/rails g rls_policy comments
bin/rails db:migrate

# 场景 2：回补老表（lint_schema 报错时）
bin/rails g rls_policy feed_products
bin/rails db:migrate
bin/rake validator:lint_schema  # 应当变绿
```

### 生成内容契约

- class 名：`AddRlsPoliciesFor<Table>`
- 文件名：`db/migrate/<ts>_add_rls_policies_for_<table>.rb`
- 幂等：up 先 DROP 旧+新 policies 再 CREATE
- down：DROP + DISABLE RLS（恢复到"无 RLS"状态，不恢复 FOR ALL 旧版——反向操作方向不唯一，保守选择）

### Pre-flight 检查（非致命）

Generator 运行时会：
- 如果表不存在 → 输出 warning（不阻塞，因为可能先 gen migration 再 gen model）
- 如果表存在但无 `data_version` 列 → 输出 warning（migration 会在 db:migrate 阶段失败，给 agent 明确错误）

## Consequences

### Positive
- **单一事实源**：4-op policy 的 DDL 只在 template 里写一次，未来要统一升级（比如加新 op），改 template 就好
- **Lint → Fix 闭环**：`lint_schema` 报的每条 ERROR 都附带 `Run rails g rls_policy X` 建议，agent 照做即可
- **新表不再漏**：`docs/conventions/adding-models.md` 会把 `rails g rls_policy` 写进标准流程

### Negative / Known issues
- Generator 是 rlbox 底座的东西，派生项目**不能**对 template 做 per-project 定制（想变 policy 语义只能改 base migration 文件）—— 目前这不是问题，因为 4-op policy 就是通用约定
- 依然需要人记得跑。比 `rails g model` 自动带上 `data_version` 列要弱一级。未来可考虑 hook 进 model generator（改 ApplicationGenerator 模板）

### Migration path for existing forks

1. 各派生项目 `git pull` rlbox → 自动拿到 generator
2. `bin/rake validator:lint_schema` 看报错
3. 对每个报错的表跑 `bin/rails g rls_policy <table>`
4. `bin/rails db:migrate && bin/rake validator:lint_schema` 再验证

（**禁止**再手写 `backfill_rls_policies_for_*.rb` 风格的 migration。这类文件以后只出现在 git history 里。）

## Related

- [ADR-001](ADR-001-all-business-tables-have-data-version.md) — 所有业务表都有 `data_version`
- [architecture/data-version.md](../architecture/data-version.md) — 双保险架构
- [conventions/adding-models.md](../conventions/adding-models.md) — 新增业务表标准流程
- ADR-015 — data pack `depends_on` 加载顺序（同期反哺）
