---
topic: new-branch
updated_at: 2026-04-28
related:
  - architecture/data-version.md
  - decisions/ADR-004-rls-requires-bin-db-init.md
source_files:
  - bin/db_init
  - bin/setup
  - config/database.yml
supersedes: ../archive/NEW_BRANCH_GUIDE.md
---

# 🌿 新分支 / 新机器初始化指南

## 🚀 TL;DR

**新克隆项目**：
```bash
bin/setup          # 自动检测：若 app_user 不存在 → 转发到 bin/db_init；否则 db:prepare
bin/dev            # 启动
```

**已有环境想重新初始化**（RLS 坏了 / 想换分支 / baseline 乱了）：
```bash
bin/db_init          # 幂等：已存在的资源会跳过
```

**核爆重来**（连数据库带角色全删掉）：
```bash
DROP=1 bin/db_init   # 删 dev+test 两个库 + 重建角色 + 全套流程
```

---

## 📚 为什么不是 `bin/rails db:setup`？

rlbox 启用了 PostgreSQL **Row-Level Security (RLS)** 作为 `data_version` 隔离的第二层防御。RLS 生效需要三件事同时满足：

1. **角色**：Rails 必须以 NOSUPERUSER 角色（`app_user`）连库（superuser 会绕过 RLS）
2. **数据库 GUC 参数**：`ALTER DATABASE ... SET app.data_version='0'`
3. **表 RLS**：`ENABLE ROW LEVEL SECURITY` + `FORCE` + `CREATE POLICY`

其中 **第 1、2 步需要 superuser 权限**，migration 以 app_user 身份跑不动——所以只能用 `bin/db_init` 编排（它以 superuser 身份 psql 执行关键 SQL）。

详细决策记录：**[ADR-004](../decisions/ADR-004-rls-requires-bin-db-init.md)**。

---

## 🔧 `bin/db_init` 做了什么

读 `config/database.yml` 动态解析库名（不硬编码），然后：

| Step | 身份 | 动作 |
|---|---|---|
| 1 | superuser | `CREATE ROLE app_user WITH LOGIN NOSUPERUSER CREATEDB INHERIT PASSWORD '…'`（幂等） |
| 2 | superuser | 创建 dev/test 数据库，owner=app_user；`ALTER DATABASE ... SET app.data_version='0'` |
| 3 | app_user | `bin/rails db:migrate` + `bin/rails db:test:prepare`（RLS policy 在这里生效） |
| 4 | app_user | `bin/rails validator:reset_baseline`（加载 `app/validators/support/data_packs/v1/`） |
| 5 | app_user | 自检：`current_user='app_user'` / `is_super=false` / policy 数量 ≥ N |

**幂等保证**：每步都用 `IF NOT EXISTS` / `ALTER ... OWNER TO`，重跑只会把偏移校准回来，不会炸。

---

## ⚙️ 环境变量

| 变量 | 默认 | 用途 |
|---|---|---|
| `PGHOST` | `localhost` | PG 主机 |
| `PGPORT` | `5432` | PG 端口 |
| `PGSUPERUSER` | `postgres` | **superuser 身份**，用于执行 Step 1、2 |
| `PGSUPERPASS` | （空） | superuser 密码（本地 trust 无需） |
| `DB_PASSWORD` | `app_pass` | 要给 `app_user` 设的密码；同时写进 database.yml |
| `DROP` | 未设 | `DROP=1` 会先 DROP 两个库 + DROP 角色再重建 |

---

## 🔄 典型场景

### 场景 A：新同事 clone 项目
```bash
git clone ...
cd project
bin/setup              # 首次自动走 db_init
bin/dev
```

### 场景 B：已有环境，换到新分支拉了新 migration
```bash
git checkout feature/xxx
bin/rails db:migrate   # 不需要 db_init；app_user 已存在
```

### 场景 C：RLS 权限坏了 / 想重置 baseline
```bash
bin/db_init            # 幂等校准
```

### 场景 D：evaluator 自动化想强制干净环境
```bash
DROP=1 bin/db_init
```

---

## ✅ 初始化完成后的自检

`bin/db_init` 末尾会自动跑下列检查：

```
✓ current_user = app_user                      # Rails 是 NOSUPERUSER 身份
✓ is_super = false                              # 不会绕过 RLS
✓ current_setting('app.data_version') = '0'     # baseline 默认可见
✓ pg_policy 数量 ≥ N                             # 所有业务表都有 policy
```

---

## ❓ FAQ

### Q: `bin/rails db:setup` / `db:reset` 还能用吗？
**不能单独用**。它们不会创建 app_user、不会注册 GUC 参数。**永远走 `bin/db_init` 或 `bin/setup`**。

### Q: migration `..._configure_app_data_version_parameter.rb` 为什么是 no-op？
因为 `ALTER DATABASE SET app.data_version='0'` 需要 superuser，migration 以 app_user 身份跑会报 `PG::InsufficientPrivilege`。这步改由 `bin/db_init` 的 Step 2 处理。保留 migration 文件只为占版本号，**不要删**。

### Q: `validator:reset_baseline` 会洗掉我的开发数据吗？
**会**。它清空所有 `data_version='0'` 的业务表记录并重新加载 baseline。
日常开发：用 `bin/rails db:migrate`（只跑新 migration）即可，不需要 reset_baseline。
只有想"回到初始状态"时才跑 `bin/db_init` / `rake validator:reset_baseline`。

---

## 🔗 相关文档

- [architecture/data-version.md](../architecture/data-version.md) — RLS + data_version 隔离原理
- [decisions/ADR-004-rls-requires-bin-db-init.md](../decisions/ADR-004-rls-requires-bin-db-init.md) — 为什么 RLS 不能纯靠 migration
- [conventions/environment.md](./environment.md) — 环境变量与平台约定
