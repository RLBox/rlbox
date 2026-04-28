---
topic: models-index
updated_at: 2026-04-28
---

# 业务模型索引

> **rlbox 模板库本身无业务模型**。各派生项目 fork 后在此填充自己的 entity pages。

## 新增模型 entity page 规范

每次新建业务模型，都要：
1. 新建 `docs/models/<name>.md`（使用下方模板）
2. 把它加到本文件的表格里
3. 跑 `rake docs:lint` 确认无 broken link

### Entity Page 模板

```markdown
---
topic: model-<name>
updated_at: YYYY-MM-DD
related:
  - architecture/data-version.md
source_files:
  - app/models/<name>.rb
  - db/migrate/..._create_<table>.rb
---

# <ModelName>

## 概述
[一句话描述]

## 字段

| 字段 | 类型 | 说明 |
|---|---|---|
| id | bigint | PK |
| data_version | string | 隔离版本（baseline='0'） |
| ... | ... | ... |
| created_at | datetime | — |
| updated_at | datetime | — |

## 关联

- belongs_to / has_many ...

## 约束 / 验证

- validates ...

## Baseline 数据

- 来源：`app/validators/support/data_packs/v1/<plural>.rb`
- 数量：N 条

## 注意事项

[已知坑、迁移历史等]
```

## 模型表格（各派生项目填充）

| 模型 | 描述 | data_version | 文档 |
|---|---|---|---|
| （派生项目在此添加） | — | — | — |

## 系统模型（不需要 entity page）

| 模型 | 说明 |
|---|---|
| Administrator | 管理员账号 |
| Session | Rails 认证会话 |
| AdminOplog | 管理操作日志 |
| ValidatorExecution | 评测执行记录 |
| ActiveStorage::Blob / Attachment / VariantRecord | 文件存储元数据 |
