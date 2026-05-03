---
topic: adr-016
updated_at: 2026-05-03
status: accepted
decision_date: 2026-05-03
supersedes: none
related:
  - decisions/ADR-014-rls-policy-generator.md
  - architecture/data-version.md
---

# ADR-016 `rake validator:lint_schema` 三路一致性校验

## Status
✅ **Accepted** — 2026-05-03

## Context

rlbox 的 data_version 隔离由**三个独立数据源**共同维护：

| 数据源 | 位置 | 作用 |
|---|---|---|
| A. 模型层 | `include DataVersionable` 的 Ruby class | default_scope 过滤；callback 写入 `data_version` |
| B. 数据库列 | 表的 `data_version VARCHAR NOT NULL DEFAULT '0'` 列 | 存储 session id |
| C. RLS policy | `pg_policies` 里 4 条 op-split policy | 写保护 baseline，跨 session 拒绝读 |

**三者任一不对齐都会悄悄出 bug，而且 CI 完全看不出来**：

| 不一致 | 后果 | 历史实例 |
|---|---|---|
| A ⊄ B | 模型 include 了 concern 但表没列 → 启动时炸 | — |
| B ⊄ A | 表有列但模型没 include → SELECT 跨 session 泄数据 | rlbox main: `reviews` 表有列但 `Review` 模型没 include |
| B ⊄ C | 表有列但没 4 op policy → baseline 可被 UPDATE/DELETE | planet: `comments` / `likes`；rlbox main: 大批老表只有旧 `FOR ALL` 一条 |
| C ⊄ B | 有 policy 但列没了 → 孤儿 policy | 清理不彻底时出现 |

历史上出过多次事故后，各派生项目**各自实现**了一个 `lint_schema` task（IdleSwap / Kangoo / planet / duvy 都有），但实现分裂：
- 某些版本只 check A 和 B，不管 C
- RLS 检查在"没启用 RLS"的项目里报错（不 friendly）
- rlbox 底座完全没有这个工具 → 派生项目复制-修改的源头空着

### 为什么要反哺到 rlbox

1. **Goomart** 从 rlbox 直接 fork，没有 lint_schema → 和 rlbox 一样有悄悄漏洞
2. **未来每个新 fork** 都会重复相同的"发现漏洞 → 各自实现 lint → 复制到别处"的循环
3. rlbox 已经有 `validator:lint`、`validator:validate_packs` 等一套 lint 生态，`lint_schema` 属于同一类工具，应该并入

## Decision

把 duvy 版的 `lint_schema` 泛化后反哺进 rlbox，放在 `lib/tasks/validator.rake` 最后。

### 命令

```bash
bin/rake validator:lint_schema
```

### 输出（对齐时）

```
=== Schema Lint ===

  Registered models  : 13
  Tables w/ column   : 13
  Tables w/ 4 polices: 13
  RLS enabled?       : yes

  ✅ All aligned.
```

### 输出（有问题时）

```
=== Schema Lint ===

  Registered models  : 13
  Tables w/ column   : 14
  Tables w/ 4 polices: 12
  RLS enabled?       : yes

  ✗ ERROR: Table 'reviews' has `data_version` column but no model includes DataVersionable for it
  ✗ ERROR: Table 'comments' has `data_version` column but only 1 RLS policy(ies), expected 4
           (select/insert/update/delete). Run `rails g rls_policy comments` to backfill.
```

### RLS 可选性：分级告警

rlbox 底座目前**不预装 RLS migration**（每个 fork 自己加）。如果强制把"缺 policy"标为 ERROR，rlbox 主干会一片红。

所以 lint 做了**项目级自适应**：

- 扫描 `pg_policies`，判断项目是否启用 RLS（任一业务表有 policy 即为 yes）
- **RLS 启用的项目**（IdleSwap / Kangoo / planet / duvy）：缺 policy → **ERROR**
- **RLS 未启用的项目**（rlbox 主干 / Goomart 如果没装）：缺 policy → **WARNING**（不阻塞）

升级路径：项目一旦装了任意一条 4-op policy，就"升格"为 RLS 项目，之后加新表漏 policy 会立刻 ERROR。

### 和 ADR-014 的协同

ERROR 信息直接给出修复命令：

```
Run `rails g rls_policy <table>` to backfill.
```

形成闭环：`lint_schema` 发现 → `rails g rls_policy` 修复 → `lint_schema` 验证。

## Consequences

### Positive
- **统一入口**：所有 fork 的 agent 都能 `bin/rake validator:lint_schema` 检测三路对齐
- **CI 集成**：可以加进 pre-commit 或 CI pipeline（`exit 1` on errors）
- **发现 rlbox 自身 bug**：上线首跑就发现 rlbox 主干有 `reviews` 表漏注册、`sessions` schema drift、大批表只有旧 FOR ALL policy —— 这些都要后续单独修
- **反哺链条正常化**：以后派生项目发现新的校验维度，也应反哺回 rlbox，而不是各自改

### Negative
- **快照一次**：只检查当前 DB 状态，不会发现"这次 migration 没 backfill"的问题 → 需要另一种 lint（扫 migration 文件）来补。暂不做。
- **RLS 分级的复杂性**：agent 可能误以为"WARNING = 不重要"。RLS 项目必须依赖此命令 ERROR 阻断 CI，不然升级过程中会漏

### Migration path for existing forks

1. `git pull` rlbox
2. `bin/rake validator:lint_schema` 看本项目现状
3. 对 ERROR 逐一修复（大概率是 `rails g rls_policy X`）
4. 把 `validator:lint_schema` 加入 CI 脚本（参考 `config/validator_lint_rules.yml`）

### Future work

- 扫 migration 文件找"新建业务表但没 create policy"的遗漏（补 B ⊄ C 快照漏洞）
- 提供 `--fix` 选项自动调起 generator（暂不做，风险高）

## Related

- [architecture/data-version.md](../architecture/data-version.md) — 三路一致性是"双保险 + callback"架构的 invariant
- [ADR-014](ADR-014-rls-policy-generator.md) — lint → fix 闭环的"fix"半边
- [ADR-015](ADR-015-data-pack-depends-on.md) — 同期反哺
