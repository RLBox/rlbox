# Session Model Data Version Fix

## 问题描述

调用 `/api/tasks/v001_create_post/start` 时返回 500 错误：
```
Application Error: ActiveRecord::StatementInvalid
app/controllers/application_controller.rb:100:in 'ApplicationController#find_session_record'
```

## 根本原因

`Session` 模型继承自 `ApplicationRecord`，自动包含了 `DataVersionable` concern，导致所有查询都会自动添加 `WHERE data_version = ?` 条件。

但 `sessions` 表没有 `data_version` 字段（也不应该有），所以查询失败。

**错误流程**:
1. API 请求 → `ApplicationController#set_current_request_details`
2. → `find_session_record`
3. → `Session.find_by_id(...)` 
4. → DataVersionable 添加 `data_version` scope
5. → SQL 错误：`sessions` 表没有 `data_version` 列

## 解决方案

### 1. Session 模型排除 data_version

**文件**: `app/models/session.rb`

```ruby
class Session < ApplicationRecord
  # 系统模型，排除 data_version 隔离
  default_scope { unscope(where: :data_version) }
  skip_callback :create, :before, :set_data_version

  belongs_to :user
  # ...
end
```

**说明**:
- `default_scope { unscope(where: :data_version) }` - 移除所有查询的 data_version 条件
- `skip_callback :create, :before, :set_data_version` - 创建时不设置 data_version 字段

### 2. API Controller 跳过验证器上下文恢复

**文件**: `app/controllers/api/tasks_controller.rb`

```ruby
module Api
  class TasksController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :restore_validator_context  # 新增：API 不需要恢复验证器上下文
    before_action :authenticate_admin!
    # ...
  end
end
```

**说明**:
- API 请求不应该受 validator context 影响
- API 认证应该始终查找真实的 Session/Administrator，不受 data_version 限制

## 系统模型清单

以下模型应该排除 data_version（已修复）:

| 模型 | 用途 | 状态 |
|------|------|------|
| `Administrator` | 管理员账号 | ✅ 已排除 |
| `AdminOplog` | 操作日志 | ✅ 已排除 |
| `ValidatorExecution` | 验证执行记录 | ✅ 已排除 |
| `Session` | 用户会话 | ✅ 已排除（本次修复）|

**业务模型**（保留 data_version）:
- `User` - 用户账号（测试数据需要隔离）
- `Post` - 帖子（测试数据需要隔离）

## 验证修复

### 测试 Session 查询
```ruby
# Rails console
Session.find_by(id: 'some-id')  # 应该正常工作，不会报错
```

### 测试 API Endpoint
```bash
# 启动会话（需要先登录获取 cookie）
curl -X POST http://localhost:3000/api/tasks/v001_create_post/start \
  -H "Content-Type: application/json" \
  -b "session_cookie"
```

**预期响应**:
```json
{
  "verification": {
    "config": {
      "params": {
        "session_id": "uuid-here"
      }
    }
  },
  "execution_id": "uuid-here",
  "validator_id": "v001_create_post",
  "status": "running",
  "message": "Session created successfully"
}
```

## 关键概念

### DataVersionable 自动包含

`ApplicationRecord` 自动包含 `DataVersionable` concern：
```ruby
# app/models/application_record.rb
class ApplicationRecord < ActiveRecord::Base
  include DataVersionable  # 所有模型都会包含
  self.abstract_class = true
end
```

**影响**:
- 所有继承自 ApplicationRecord 的模型都会自动添加 data_version scope
- 需要手动排除系统模型

### 排除 data_version 的标准模式

```ruby
class SystemModel < ApplicationRecord
  # 1. 移除 default scope 中的 data_version 条件
  default_scope { unscope(where: :data_version) }
  
  # 2. 跳过 set_data_version 回调
  skip_callback :create, :before, :set_data_version
  
  # ... 其他代码
end
```

**注意**: 必须同时使用这两个配置，缺一不可。

## 相关文件

**修改文件**:
- `app/models/session.rb` - 添加 data_version 排除配置
- `app/controllers/api/tasks_controller.rb` - 跳过 validator context 恢复

**相关文档**:
- `DATA_VERSION_FIX.md` - 之前的 data_version 修复记录
- `VALIDATION_API_FIX.md` - API endpoints 实现文档

修复完成时间: 2026-04-15
