> ⚠️ **Archived** — 一次性修复笔记，仅保留作历史参考，勿模仿。

# Data Version 问题修复记录

## 问题描述

访问 `/admin/validation_tasks` 时出现错误：
```
NoMethodError: undefined method 'data_version_excluded!' for class Administrator
```

## 根本原因

1. **ApplicationRecord 包含了 DataVersionable concern**：
   - `app/models/application_record.rb` 中 `include DataVersionable`
   - 这导致所有继承自 `ApplicationRecord` 的模型都会自动应用 data_version 机制

2. **系统模型不应该使用 data_version 机制**：
   - `Administrator`、`AdminOplog`、`ValidatorExecution` 是系统级别的模型
   - 它们需要全局可见，不应该受到 data_version 的隔离限制

3. **data_version_excluded! 方法不存在**：
   - rlbox 项目中的 `DataVersionable` concern 没有提供 `data_version_excluded!` 类方法
   - 需要手动使用 `default_scope` 和 `skip_callback` 来排除

## 解决方案

### 修改的文件

#### 1. app/models/administrator.rb
```ruby
class Administrator < ApplicationRecord
  # System model — globally visible, not scoped per validator session
  # 不使用 data_version 机制：移除 default_scope 和 before_create 回调
  default_scope { unscope(where: :data_version) }
  skip_callback :create, :before, :set_data_version
  
  # ... 其他代码保持不变
end
```

#### 2. app/models/admin_oplog.rb
```ruby
class AdminOplog < ApplicationRecord
  # System model — audit trail should be globally visible
  # 不使用 data_version 机制：移除 default_scope 和 before_create 回调
  default_scope { unscope(where: :data_version) }
  skip_callback :create, :before, :set_data_version
  
  # ... 其他代码保持不变
end
```

#### 3. app/models/validator_execution.rb
已经正确配置（在迁移时已包含）：
```ruby
class ValidatorExecution < ApplicationRecord
  # ValidatorExecution 是系统模型，不使用 data_version 机制
  default_scope { unscope(where: :data_version) }
  skip_callback :create, :before, :set_data_version
  
  # ... 其他代码保持不变
end
```

## 工作原理

### DataVersionable 机制
当一个模型 `include DataVersionable` 时，会自动：
1. 添加 `before_create :set_data_version` 回调
2. 添加 `default_scope { where(data_version: DataVersionable.current_versions) }`

### 排除系统模型
系统模型需要：
1. 使用 `unscope(where: :data_version)` 移除 default_scope 的过滤
2. 使用 `skip_callback :create, :before, :set_data_version` 跳过自动设置版本号

## 验证

所有修改的文件通过 Ruby 语法检查：
```bash
cd /Users/zoey/rlbox
ruby -c app/models/administrator.rb
ruby -c app/models/admin_oplog.rb
# Syntax OK
```

## 下一步

1. **重启 Rails 服务器**（如果正在运行）
2. **访问验证任务管理页面**：`http://localhost:3000/admin/validation_tasks`
3. **确认页面正常加载**

## 相关文件

- `app/models/concerns/data_versionable.rb` - Data version 机制实现
- `app/models/application_record.rb` - 全局包含 DataVersionable
- `app/validators/base_validator.rb` - 验证器基类，使用 data_version 隔离测试数据

修复时间: 2026-04-15 15:32
