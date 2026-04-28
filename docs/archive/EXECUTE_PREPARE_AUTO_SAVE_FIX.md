> ⚠️ **Archived** — 一次性修复笔记，仅保留作历史参考，勿模仿。

# Execute Prepare Auto-Save Issue Fix

## 问题描述

用户点击 "启动新会话" 按钮时报错：
```
Failed to start session: Validation failed: Execution has already been taken
```

## 根本原因

`BaseValidator#execute_prepare` 方法会**自动保存** ValidatorExecution 记录：

**文件**: `app/validators/base_validator.rb:251-291`

```ruby
def execute_prepare
  @data_version = SecureRandom.hex(8)
  ActiveRecord::Base.connection.execute("SET SESSION app.data_version = '#{@data_version}'")
  @prepare_result = prepare
  
  # ... 构造返回格式 ...
  
  save_execution_state  # ← 这里会保存记录！
  
  result
end
```

**保存方法**: `app/validators/base_validator.rb:473-495`

```ruby
def save_execution_state
  state = {
    validator_class: self.class.name,
    timestamp: Time.current.to_s,
    data: { data_version: @data_version, ... }
  }
  
  # 使用 UPSERT 直接插入数据库
  ActiveRecord::Base.connection.execute(
    "INSERT INTO validator_executions (execution_id, state, created_at, updated_at) " \
    "VALUES (...) " \
    "ON CONFLICT (execution_id) DO UPDATE SET state = EXCLUDED.state, updated_at = NOW()"
  )
end
```

**冲突场景**:

1. API Controller 调用 `validator.execute_prepare`
   - `execute_prepare` 内部调用 `save_execution_state`
   - 插入记录: `execution_id = 'ace420d4-...'`（只有 execution_id, state 字段）

2. API Controller 尝试 `ValidatorExecution.create!(...)`
   - 尝试插入相同的 `execution_id`
   - **触发唯一性验证失败**: `execution_id` 已存在

## 日志证据

```
Started POST "/api/tasks/v001_create_post/start"

# 1. execute_prepare 自动保存（UPSERT）
INSERT INTO validator_executions (execution_id, state, created_at, updated_at) 
VALUES ('ace420d4-...', '{"validator_class":"V001CreatePostValidator",...}', NOW(), NOW()) 
ON CONFLICT (execution_id) DO UPDATE SET state = EXCLUDED.state, updated_at = NOW()

# 2. 开始事务，尝试 create!
TRANSACTION BEGIN

# 3. 检查 execution_id 是否存在
ValidatorExecution Exists? SELECT 1 FROM validator_executions 
WHERE execution_id = 'ace420d4-...' LIMIT 1
# 结果: 存在！

# 4. 回滚事务
TRANSACTION ROLLBACK

# 5. 抛出异常
Failed to start validation session: Validation failed: Execution has already been taken
```

## 解决方案

**修改前** (`app/controllers/api/tasks_controller.rb:start`):

```ruby
# 执行 prepare（会自动保存记录）
prepare_result = validator.execute_prepare

# ❌ 错误：尝试 create! 已存在的记录
execution = ValidatorExecution.create!(
  execution_id: session_id,
  validator_id: task_id,
  user_id: current_admin.id,
  status: 'running',
  is_active: true,
  state: { data_version: ..., prepare_result: ... }
)
```

**修改后**:

```ruby
# 执行 prepare（会自动保存记录，但只有 execution_id 和 state）
prepare_result = validator.execute_prepare

# ✅ 正确：找到已创建的记录
execution = ValidatorExecution.find_by!(execution_id: session_id)

# ✅ 更新额外的元数据字段
execution.update!(
  validator_id: task_id,
  user_id: current_admin.id,
  status: 'running',
  is_active: true
)
```

## 关键变化

### 变化 1: 使用 find_by! 而不是 create!

```ruby
# 旧代码
execution = ValidatorExecution.create!(...)

# 新代码
execution = ValidatorExecution.find_by!(execution_id: session_id)
execution.update!(...)
```

### 变化 2: 不需要手动设置 state

`execute_prepare` 已经通过 `save_execution_state` 设置了：
- `state.validator_class`
- `state.timestamp`
- `state.data.data_version`

我们只需要更新：
- `validator_id` - 验证器标识符
- `user_id` - 用户 ID
- `status` - 状态（running/completed/failed）
- `is_active` - 是否活跃

### 变化 3: 简化错误处理

`find_by!` 会在记录不存在时抛出 `ActiveRecord::RecordNotFound`，自动被 `rescue` 捕获并返回 500 错误。

## 为什么 execute_prepare 要自动保存？

**设计理由**:

1. **状态持久化**: prepare 阶段生成的 `data_version` 必须保存，以便 verify 阶段恢复
2. **简化 API**: 调用者不需要手动保存状态，`execute_prepare` 是原子操作
3. **UPSERT 语义**: 使用 `ON CONFLICT DO UPDATE`，支持重复调用（幂等性）

**在 fliggy 中的实现**:

Fliggy 项目也是同样的设计，`execute_prepare` 会自动保存状态到 ValidatorExecution 表。

## 测试验证

### 手动测试

1. 刷新浏览器页面: `http://localhost:3000/admin/validation_tasks/v001_create_post`
2. 点击 "启动新会话" 按钮
3. 应该成功创建会话，显示在 "Active Sessions" 列表中

### 数据库验证

```bash
bin/rails runner "
execution = ValidatorExecution.last
puts 'Execution ID: ' + execution.execution_id
puts 'Validator ID: ' + execution.validator_id.to_s
puts 'User ID: ' + execution.user_id.to_s
puts 'Status: ' + execution.status.to_s
puts 'Is Active: ' + execution.is_active.to_s
puts 'Data Version: ' + execution.state_data['data']['data_version']
"
```

预期输出:
```
Execution ID: <uuid>
Validator ID: v001_create_post
User ID: 1
Status: running
Is Active: true
Data Version: <16-char-hex>
```

## 相关代码

**修改文件**:
- `app/controllers/api/tasks_controller.rb` - API controller start action

**相关文件**:
- `app/validators/base_validator.rb` - execute_prepare 和 save_execution_state
- `app/models/validator_execution.rb` - 模型定义

## 架构说明

### ValidatorExecution 字段分组

**自动管理（by BaseValidator）**:
- `execution_id` - UUID
- `state` - JSONB (包含 validator_class, timestamp, data_version)

**手动管理（by API Controller）**:
- `validator_id` - 验证器标识符（如 v001_create_post）
- `user_id` - 关联的管理员 ID
- `status` - 执行状态（running/completed/failed）
- `is_active` - 会话是否活跃
- `score` - 验证分数（verify 阶段设置）
- `verify_result` - 验证结果 JSON（verify 阶段设置）

### 生命周期

```
1. API Controller 调用 execute_prepare
   ↓
2. execute_prepare 创建基础记录（execution_id + state）
   ↓
3. API Controller 更新元数据（validator_id + user_id + status + is_active）
   ↓
4. 用户执行测试操作
   ↓
5. API Controller 调用 verify
   ↓
6. verify 更新结果（score + verify_result + status）
```

## 修复完成时间

2026-04-15

## 后续优化建议

1. **改进 BaseValidator API**: 
   - 提供 `execute_prepare(metadata: {})` 参数
   - 允许在 prepare 阶段就设置 validator_id, user_id 等
   
2. **统一状态管理**:
   - 考虑将 validator_id, user_id 也存入 state JSONB
   - 或者在 save_execution_state 中接受额外参数

3. **文档完善**:
   - 在 BaseValidator 类注释中说明 execute_prepare 会自动保存
   - 提供标准的 API Controller 使用示例
