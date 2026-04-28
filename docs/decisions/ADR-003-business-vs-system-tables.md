---
topic: adr-003
updated_at: 2026-04-28
status: accepted
decision_date: 2026-04-28
related:
  - decisions/ADR-001-all-business-tables-have-data-version.md
---

# ADR-003 业务表 vs 系统表的判断准则

## Status
✅ **Accepted** — 2026-04-28

## Context

`data_version` 隔离机制要求区分两类表：
- **业务表**：参与隔离（有 data_version 列 + DataVersionable concern）
- **系统表**：不参与隔离（用三件套排除）

## Decision

### 判断准则（出题人视角）

> **如果我能出一道题让 Agent 新建/修改/删除这张表的记录，它就是业务表。**

### 系统表白名单（当前）

| 表 | 理由 |
|---|---|
| `administrators` | 只有运维人员管理，Agent 不会操作 |
| `sessions` | Rails 内置认证会话，Agent 操作的是业务（不是会话） |
| `admin_oplogs` | 只追踪管理操作，只读 |
| `validator_executions` | 评测系统内部，Agent 不应操作 |
| `active_storage_*` | 存储元数据，不是业务记录 |

所有其他表默认是**业务表**。

### 三件套只许系统表用

```ruby
# ✅ 系统表才可以
class Administrator < ApplicationRecord
  data_version_excluded!
  default_scope { unscope(where: :data_version) }
  skip_callback :create, :before, :set_data_version
end

# ❌ 业务表绝不用
class Category < ApplicationRecord
  data_version_excluded!   # WRONG！
end
```

## Consequences

### Positive
- 规则简单，无歧义：只有白名单里的才是系统表
- 防止"Category 看起来像字典"的错误分类

### Negative
- 系统表白名单需要人工维护（但变化极少）

## Implementation
- `rake docs:lint` 的 `check_code_antipatterns` 规则会静态扫描系统表以外的 ApplicationRecord 子类，发现三件套立刻报错
- 详见 [architecture/data-version.md §4](../architecture/data-version.md)
