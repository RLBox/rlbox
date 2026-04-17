# Validation Tasks API Implementation

## 问题描述

前端错误报告显示：
1. `POST /api/tasks//start - HTTP 500` - URL 中有双斜杠
2. `启动任务Failed: Unexpected token '<', "<!-- BEGIN"... is not valid JSON` - 返回了 HTML 而不是 JSON

## 根本原因

1. **JavaScript 变量错误**: `taskId` 使用了 `@task[:task_id]`（为 `nil`），导致 URL 变成 `/api/tasks//start`
2. **缺少 API routes**: `/api/tasks/:id/start` 和 `/api/verify/run` 路由不存在
3. **缺少 API controller**: `Api::TasksController` 不存在

## 解决方案

### 1. 修复 JavaScript 变量

**文件**: `app/views/admin/validation_tasks/show.html.erb:264`

```javascript
// 修改前
const taskId = '<%= @task[:task_id] %>';  // 使用 UUID 格式调用 API

// 修改后
const taskId = '<%= @task[:validator_id] %>';  // 使用 validator_id 调用 API
```

### 2. 添加 API 路由

**文件**: `config/routes.rb`

```ruby
namespace :api do
  # Validation tasks API
  post 'tasks/:task_id/start', to: 'tasks#start'
  post 'verify/run', to: 'tasks#verify'
  delete 'sessions/:session_id', to: 'tasks#remove_session'
  delete 'sessions', to: 'tasks#clear_all_sessions'
  
  # ... existing v1 routes
end
```

### 3. 创建 API Controller

**文件**: `app/controllers/api/tasks_controller.rb`

实现了四个 endpoints：

#### POST /api/tasks/:task_id/start
启动新的验证会话
- 查找验证器类
- 生成 session_id（UUID）
- 创建验证器实例并执行 **execute_prepare**（自动设置 data_version）
- 创建 ValidatorExecution 记录
- 返回 session_id

**关键代码**:
```ruby
# 创建验证器实例
validator = validator_class.new(session_id)

# 执行 prepare 阶段（会自动设置 data_version 并保存基础记录）
prepare_result = validator.execute_prepare
# execute_prepare 会通过 save_execution_state 自动创建 ValidatorExecution 记录
# 但只包含: execution_id, state (validator_class, timestamp, data_version)

# 找到已创建的记录并更新元数据字段
execution = ValidatorExecution.find_by!(execution_id: session_id)
execution.update!(
  validator_id: task_id,
  user_id: current_admin.id,
  status: 'running',
  is_active: true
)
```

**重要**: `execute_prepare` 会自动保存 ValidatorExecution 记录（通过 `save_execution_state`），所以不能使用 `create!`，必须使用 `find_by! + update!`。

**响应格式**:
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

#### POST /api/verify/run
运行验证
- 参数: `task_id`, `session_id`
- 查找 ValidatorExecution 记录
- 创建验证器实例
- 调用 **execute_verify** 恢复数据版本并运行验证
- 更新 execution 记录为非活跃状态
- 返回验证结果

**关键代码**:
```ruby
# 创建验证器实例
validator = validator_class.new(session_id)

# 运行验证（会自动 restore_execution_state 恢复 @data_version）
# cleanup: false 表示不删除测试数据（用于手动测试）
result = validator.execute_verify(cleanup: false)

# execute_verify 已经更新了 validator_id, score, status, verify_result
# 我们只需要补充设置 is_active = false
execution.update!(is_active: false)
```

**重要**: 
- 使用 `execute_verify` 而不是 `run`（该方法不存在）
- `execute_verify` 会自动调用 `restore_execution_state` 恢复 `@data_version`
- `execute_verify` 会自动更新 ValidatorExecution 记录（validator_id, score, status, verify_result）
- `cleanup: false` 保留测试数据，方便手动检查

**响应格式**:
```json
{
  "score": 1.0,
  "passed": true,
  "assertions": [
    {
      "description": "A post titled \"Hello World\" exists",
      "weight": 50,
      "passed": true
    }
  ],
  "errors": [],
  "execution_id": "uuid-here"
}
```

#### DELETE /api/sessions/:session_id
移除指定会话
- 软删除：将 `is_active` 设为 false

#### DELETE /api/sessions
清除所有会话
- 可选参数: `task_id`
- 批量更新 `is_active` 为 false

### 关键实现细节

1. **数据版本设置**: 
   ```ruby
   # ❌ 错误：set_data_version 方法不存在
   validator.set_data_version
   
   # ✅ 正确：使用 execute_prepare
   prepare_result = validator.execute_prepare
   # execute_prepare 内部会：
   #   1. 生成 @data_version = SecureRandom.hex(8)
   #   2. 执行 SET SESSION app.data_version = '...'
   #   3. 调用 prepare 方法
   #   4. 返回格式化的结果
   ```

2. **验证器查找**:
   ```ruby
   def find_validator_class(validator_id)
     # 扫描 app/validators/**/*_validator.rb
     # 推导类名: v001_create_post_validator.rb -> V001CreatePostValidator
     # 匹配 validator_id
   end
   ```

3. **认证**:
   - 使用 `before_action :authenticate_admin!`
   - 检查 `session[:current_admin_id]`
   - 跳过 `restore_validator_context`（API 不需要）

4. **错误处理**:
   - 验证失败时捕获异常
   - 更新 execution 状态为 failed
   - 返回友好的错误消息

## 测试方法

### 1. 启动会话
```bash
curl -X POST http://localhost:3000/api/tasks/v001_create_post/start \
  -H "Content-Type: application/json" \
  -b "session_cookie_here"
```

### 2. 运行验证
```bash
curl -X POST http://localhost:3000/api/verify/run \
  -H "Content-Type: application/json" \
  -d '{"task_id": "v001_create_post", "session_id": "uuid-here"}' \
  -b "session_cookie_here"
```

## 使用流程

1. **用户点击 "Start New Session"**
   - 前端调用 `POST /api/tasks/v001_create_post/start`
   - 后端调用 `execute_prepare` 设置 data_version
   - 创建 ValidatorExecution 记录
   - 返回 session_id
   - 前端显示新会话在列表中

2. **用户执行测试操作**（如创建帖子）
   - 用户在应用中手动操作
   - 数据带有 data_version 标记

3. **用户点击 "Verify"**
   - 前端调用 `POST /api/verify/run`
   - 后端运行 validator.verify
   - 返回评分和断言结果
   - 前端显示验证结果

## 文件清单

**新增文件**:
- `app/controllers/api/tasks_controller.rb` - API controller（6.7KB）

**修改文件**:
- `config/routes.rb` - 添加 API routes
- `app/views/admin/validation_tasks/show.html.erb` - 修复 taskId 变量

## 后续问题修复 (2026-04-15)

### 问题 1: Session 模型 SQL 错误
**错误**: `ActiveRecord::StatementInvalid` 在 `find_session_record`
**原因**: Session 继承 ApplicationRecord，自动包含 DataVersionable
**修复**: Session 模型排除 data_version（见 SESSION_DATA_VERSION_FIX.md）

### 问题 2: set_data_version 方法不存在
**错误**: `undefined method 'set_data_version' for V001CreatePostValidator`
**原因**: 调用了不存在的方法
**修复**: 使用 `execute_prepare` 方法代替
- `execute_prepare` 会自动生成 data_version
- 自动设置 PostgreSQL session 变量
- 执行 prepare 并返回格式化结果

### 问题 3: Execution has already been taken
**错误**: `Validation failed: Execution has already been taken`
**原因**: `execute_prepare` 会自动保存 ValidatorExecution 记录，API controller 再次 `create!` 导致唯一性冲突
**修复**: 使用 `find_by! + update!` 而不是 `create!`
```ruby
# ❌ 错误：重复创建
prepare_result = validator.execute_prepare
execution = ValidatorExecution.create!(execution_id: session_id, ...)

# ✅ 正确：更新已存在的记录
prepare_result = validator.execute_prepare
execution = ValidatorExecution.find_by!(execution_id: session_id)
execution.update!(validator_id: task_id, user_id: current_admin.id, ...)
```
详见: EXECUTE_PREPARE_AUTO_SAVE_FIX.md

### 问题 4: undefined method 'run'
**错误**: `undefined method 'run' for V001CreatePostValidator`
**原因**: 调用了不存在的 `run` 方法
**修复**: 使用 `execute_verify` 方法
```ruby
# ❌ 错误：run 方法不存在
result = validator.run

# ✅ 正确：使用 execute_verify
result = validator.execute_verify(cleanup: false)
# execute_verify 会自动：
#   1. restore_execution_state 恢复 @data_version
#   2. SET SESSION app.data_version = '...'
#   3. 调用 verify 方法
#   4. 计算分数和断言结果
#   5. 更新 ValidatorExecution 记录
#   6. 返回 { execution_id, status, score, assertions, errors }
```

## 后续优化建议

1. **添加速率限制**: 防止 API 滥用
2. **添加日志**: 记录 API 调用和验证执行
3. **改进错误消息**: 更详细的诊断信息
4. **添加超时处理**: verify 阶段超时自动失败
5. **添加 WebSocket 通知**: 实时更新验证状态

修复完成时间: 2026-04-15

