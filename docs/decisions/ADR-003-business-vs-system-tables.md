---
topic: adr-003
updated_at: 2026-05-03
status: accepted
decision_date: 2026-04-28
related:
  - decisions/ADR-001-all-business-tables-have-data-version.md
---

# ADR-003 业务表 vs 系统表的判断准则

## Status
✅ **Accepted** — 2026-04-28（2026-05-03 修订：三件套 → 二件套 + 富版 macro）

## Context

`data_version` 隔离机制要求区分两类表：
- **业务表**：参与隔离（有 data_version 列 + DataVersionable concern）
- **系统表**：不参与隔离（用 `data_version_excluded!` 宏排除）

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

### 系统表模板（2026-05-03 修订版：二件套）

```ruby
# ✅ 系统表
class Administrator < ApplicationRecord
  data_version_excluded!                               # 富版 macro，内部已 skip_callback ×3
  default_scope { unscope(where: :data_version) }      # 必需——ApplicationRecord default_scope
                                                       # 会被 has_many 继承，用来抵消
end

# ❌ 业务表绝不用
class Category < ApplicationRecord
  data_version_excluded!   # WRONG！
end
```

### 为什么是二件套不是三件套（2026-05-03 订正）

历史上这个模式被称作"三件套"：
1. `data_version_excluded!`
2. `default_scope { unscope(where: :data_version) }`
3. `skip_callback :create, :before, :set_data_version`

2026-05-03 tech-debt-cleanup P1.9 把 `data_version_excluded!` 升级为**富版**宏——
内部自动做三次 `skip_callback`（create + update + destroy）：

```ruby
def data_version_excluded!
  DataVersionable.register_excluded(self)
  DataVersionable.unregister_model(self)
  skip_callback :create,  :before, :set_data_version
  skip_callback :update,  :before, :prevent_baseline_mutation!
  skip_callback :destroy, :before, :prevent_baseline_mutation!
end
```

所以第 3 件**不再需要手写**——手写反而会触发 "callback has not been defined"
崩溃（因为宏已经 skip 过了）。

但第 2 件 `default_scope { unscope(where: :data_version) }` **仍需手写**：
ApplicationRecord 的 `default_scope { where(data_version: ...) }` 会被 `has_many`
关联通过 "default values from scope" 继承；新 build 对象会自动被赋 `data_version=`
属性。对于 drop 了 data_version 列的系统表（如 sessions，见 ADR-017 P1.3），
这会直接抛 `ActiveModel::UnknownAttributeError`。

### 为什么富版 macro 还带 `prevent_baseline_mutation!`

富版还增加了 Ruby 层的 baseline 写保护：
- `before_update :prevent_baseline_mutation!`
- `before_destroy :prevent_baseline_mutation!`

这是跟 DB 层 RLS policy（ADR-015）配合的**第二道闸**——
防止应用代码不小心 `Post.find(1).update!(...)` 改到 baseline 行。
data pack 加载流程用 `DataVersionable.allow_baseline_mutation do ... end` 作用域打开。

## Consequences

### Positive
- 规则简单，无歧义：只有白名单里的才是系统表
- 防止"Category 看起来像字典"的错误分类
- 富版 macro 少 1 行样板代码，业务表额外得到 Ruby 层 baseline 写保护

### Negative
- 系统表白名单需要人工维护（但变化极少）
- 升级到富版 macro 需要派生项目**删掉**老三件套里的 `skip_callback` 行（见 P1.11 Goomart 回滚示例）

## Implementation
- `rake docs:lint` 的 `check_code_antipatterns` 规则会静态扫描系统表以外的 ApplicationRecord 子类，发现 `data_version_excluded!` 立刻报错
- 详见 [architecture/data-version.md §4](../architecture/data-version.md)
- 升级历史：2026-05-03 tech-debt-cleanup P1.9/P1.10 把 rlbox 底座 `DataVersionable` 从 150 行精简版升级到 182 行富版（反向从 planet 移植），并把 4 个系统表（Session / Administrator / AdminOplog / ValidatorExecution）从三件套改为二件套
