# 🌿 新分支开发指南

## 📋 概述

本文档说明如何在新分支环境下快速初始化数据库和开发环境。

---

## 🚀 快速开始

### 新分支初始化（一条命令）

```bash
bin/db_init
```

**该命令会自动完成：**
1. ✅ 创建数据库角色 `app_user`（如不存在）
2. ✅ 运行数据库迁移（`db:migrate`）
3. ✅ 加载基线验证数据（`validator:reset_baseline`）

**特点：**
- 🔄 **可重复执行** - 安全幂等，多次运行不会出错
- 🛡️ **自动容错** - 角色已存在时自动跳过
- 📊 **统一流程** - 与生产环境 `deploy.sh` 保持一致

---

## 🔍 详细说明

### 环境背景

我们的开发环境特点：
- 每个分支基于主干环境 fork，**不是**全新环境
- 数据库使用 RLS（Row Level Security），需要 `app_user` 角色
- 新分支首次运行迁移时，`app_user` 角色可能不存在

### 为什么需要 bin/db_init？

**问题：** 直接运行 `bin/rails db:migrate` 会报错：
```
PG::UndefinedObject: ERROR:  role "app_user" does not exist
```

**原因：** RLS 迁移脚本依赖 `app_user` 角色，但新分支环境尚未创建该角色。

**解决：** `bin/db_init` 在运行迁移前自动创建 `app_user` 角色。

---

## 📖 使用场景

### 场景 1：新建分支首次初始化

```bash
# 1. 切换到新分支
git checkout -b feature/new-feature

# 2. 初始化数据库
bin/db_init

# 3. 启动服务
bin/dev
```

### 场景 2：从主干合并后更新数据库

```bash
# 1. 合并主干代码
git merge origin/master

# 2. 更新数据库（运行新迁移）
bin/db_init

# 3. 启动服务
bin/dev
```

### 场景 3：数据库损坏需要重置

```bash
# 如果数据库出现问题，可以重新初始化
bin/db_init

# validator:reset_baseline 会清空数据并重新加载基线数据
# 适用于开发环境，生产环境请勿使用
```

---

## ⚙️ 与生产环境的关系

### 生产环境（deploy.sh）

生产环境使用 `deploy.sh` 脚本部署，流程如下：

```bash
# deploy.sh 的执行顺序
1. 手动创建 app_user 角色（docker exec psql）
2. 运行 db:prepare（创建数据库 + 迁移）
3. 运行 validator:reset_baseline（加载数据）
4. 重新授予 app_user 权限
5. 启用 RLS 强制策略
```

### 开发环境（bin/db_init）

开发环境使用 `bin/db_init` 脚本，流程如下：

```bash
# bin/db_init 的执行顺序
1. 自动创建 app_user 角色（Rails 内部）
2. 运行 db:migrate（只运行未执行的迁移）
3. 运行 validator:reset_baseline（加载数据）
```

### 关键区别

| 项目 | 生产环境 (deploy.sh) | 开发环境 (bin/db_init) |
|------|---------------------|----------------------|
| **数据库操作** | `db:prepare`（创建+迁移+加载schema） | `db:migrate`（仅迁移） |
| **角色创建** | 手动执行 SQL（docker exec） | Rails 自动执行（ActiveRecord） |
| **适用场景** | 全新部署 / 重新部署 | 增量更新 / 日常开发 |
| **安全策略** | 完整的 RLS 配置流程 | 基础角色创建 |

**兼容性：** `bin/db_init` 的设计确保与 `deploy.sh` 完全兼容，不会相互干扰。

---

## 🛠️ 技术细节

### app_user 角色的作用

`app_user` 是用于 RLS（行级安全）策略的数据库角色：

```sql
-- 创建角色
CREATE ROLE app_user WITH LOGIN NOSUPERUSER;

-- 授予权限
GRANT CONNECT ON DATABASE dbname TO app_user;
GRANT USAGE, CREATE ON SCHEMA public TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES TO app_user;
```

**用途：**
- 实现多会话数据隔离
- 控制用户只能看到自己会话的数据
- 通过 `current_setting('app.data_version')` 区分不同会话

### bin/db_init 实现原理

脚本分三个步骤执行：

**步骤 1：创建 app_user 角色**
```ruby
ActiveRecord::Base.connection.execute(<<~SQL)
  DO $$
  BEGIN
     IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user WITH LOGIN NOSUPERUSER;
        -- 授予权限...
     END IF;
  END $$;
SQL
```

**步骤 2：运行数据库迁移**
```bash
bin/rails db:migrate
```

**步骤 3：加载基线数据**
```bash
bin/rails validator:reset_baseline
```

---

## ❓ 常见问题

### Q1: bin/db_init 和 db:migrate 有什么区别？

**A:** `bin/db_init` 是对 `db:migrate` 的增强封装：

```bash
# 只运行迁移（可能报错）
bin/rails db:migrate

# 自动处理 app_user + 迁移 + 数据加载
bin/db_init  # 推荐使用
```

### Q2: 可以重复执行 bin/db_init 吗？

**A:** 可以，脚本是幂等的：
- ✅ app_user 已存在 → 跳过创建
- ✅ 迁移已执行 → 跳过
- ⚠️ validator:reset_baseline → 会清空数据重新加载（开发环境可接受）

### Q3: 生产环境可以使用 bin/db_init 吗？

**A:** **不推荐**。生产环境应使用标准的 `deploy.sh` 脚本：
- `deploy.sh` 有完整的安全检查和权限配置
- `bin/db_init` 主要为开发环境设计
- 生产环境需要更严格的部署流程

### Q4: 报错 "permission denied" 怎么办？

**A:** 检查数据库用户权限：

```bash
# 查看当前用户权限
bin/rails runner "puts ActiveRecord::Base.connection.execute('SELECT current_user').first['current_user']"

# 确保用户有 CREATE ROLE 权限
# 开发环境默认应该有此权限
```

如果权限不足，可以：
1. 手动创建 app_user（参考 `db/init_production_roles.sql`）
2. 然后运行 `bin/rails db:migrate`

### Q5: validator:reset_baseline 会影响我的开发数据吗？

**A:** **会清空数据**。该命令会：
- 清空所有业务表数据
- 重新加载 `app/validators/support/data_packs/v1/` 中的基线数据

**建议：**
- 首次初始化时使用 `bin/db_init`
- 后续只需运行 `bin/rails db:migrate`（不加载数据）
- 需要重置数据时再手动运行 `rake validator:reset_baseline`

---

## 📚 相关文档

- `deploy.sh` - 生产环境部署脚本
- `db/init_production_roles.sql` - 生产环境角色初始化 SQL 模板
- `docs/MULTI_SESSION_IMPLEMENTATION.md` - 多会话隔离实现文档
- `lib/tasks/validator.rake` - 数据包加载任务定义

---

## 🔗 快速链接

**常用命令：**
```bash
# 新分支初始化
bin/db_init

# 仅运行迁移（跳过数据加载）
bin/rails db:migrate

# 仅加载基线数据（会清空现有数据）
rake validator:reset_baseline

# 启动开发服务器
bin/dev

# 运行测试
rake test
```

**数据库操作：**
```bash
# 查看迁移状态
bin/rails db:migrate:status

# 回滚最后一次迁移
bin/rails db:rollback

# 查看当前数据统计
bin/rails runner "puts 'Cities: ' + City.count.to_s + ', Flights: ' + Flight.count.to_s"
```

---

**更新日期:** 2026-01-28  
**维护团队:** Clacky AI Development Team
