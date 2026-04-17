# Execute Verify Method Fix

## 问题描述

用户点击 "Verify" 按钮后报错：
```
POST /api/verify/run - HTTP 500
undefined method 'run' for an instance of V001CreatePostValidator
```

## 根本原因

API Controller 调用了不存在的 `validator.run` 方法。

**文件**: `app/controllers/api/tasks_controller.rb:99`

```ruby
# ❌ 错误：run 方法不存在
result = validator.run
```

BaseValidator 没有 `run` 方法，正确的方法是 `execute_verify`。

## 可用方法对比

### BaseValidator 提供的公共方法

```ruby
# ✅ 准备阶段
def execute_prepare
  # 生成 data_version
  # 设置 PostgreSQL session 变量
  # 调用 prepare 方法
  # 保存执行状态
end

# ✅ 验证阶段
def execute_verify(cleanup: true)
  # 恢复执行状态（包括 @data_version）
  # 设置 PostgreSQL session 变量
  # 调用 verify 方法
  # 计算分数和断言
  # 更新 ValidatorExecution 记录
end

# ❌ 不存在
def run
  # 该方法不存在！
end

# ❌ 不存在
def set_data_version
  # 该方法不存在！
end
```

## execute_verify 详解

**位置**: `app/validators/base_validator.rb:295-353`

### 方法签名

```ruby
def execute_verify(cleanup: true)
```

### 参数

- `cleanup` (Boolean, default: true)
  - `true`: 验证后删除测试数据（自动化测试用）
  - `false`: 验证后保留测试数据（手动测试用，方便检查）

### 执行流程

```ruby
def execute_verify(cleanup: true)
  result = {
    execution_id: @execution_id,
    status: 'unknown',
    score: 0,
    assertions: [],
    errors: []
  }
  
  begin
    # 1. 恢复执行状态（从 validator_executions 表）
    restore_execution_state
    # → 恢复 @data_version, @prepare_result 等
    
    # 2. 恢复 PostgreSQL 会话变量
    ActiveRecord::Base.connection.execute(
      "SET SESSION app.data_version = '#{@data_version}'"
    )
    
    # 3. 执行验证逻辑（调用子类的 verify 方法）
    verify
    
    # 4. 计算结果
    result[:status] = @errors.empty? ? 'passed' : 'failed'
    result[:score] = @score
    result[:assertions] = @assertions
    result[:errors] = @errors
    
    # 5. 更新 ValidatorExecution 记录
    # 更新字段: validator_id, score, status, verify_result
    ActiveRecord::Base.connection.execute(
      "UPDATE validator_executions SET ..."
    )
    
  rescue StandardError => e
    result[:status] = 'error'
    result[:errors] << "验证执行出错: #{e.message}"
  end
  
  # 6. 可选：回滚到基线状态（删除测试数据）
  rollback_to_baseline if cleanup
  
  result
end
```

### 返回格式

```ruby
{
  execution_id: "uuid-here",
  status: "passed" | "failed" | "error",
  score: 1.0,  # 0.0 - 1.0
  assertions: [
    {
      description: "A post titled \"Hello World\" exists",
      weight: 50,
      passed: true
    },
    {
      description: "Post status is published",
      weight: 50,
      passed: true
    }
  ],
  errors: []  # 错误消息数组
}
```

## 解决方案

### 修改前

**文件**: `app/controllers/api/tasks_controller.rb:verify`

```ruby
# 创建验证器实例
validator = validator_class.new(session_id)

# ❌ 错误 1: 手动设置 @data_version（不需要）
data_version = execution.state&.dig('data_version')
if data_version
  validator.instance_variable_set(:@data_version, data_version)
end

# ❌ 错误 2: 调用不存在的 run 方法
result = validator.run

# ❌ 错误 3: 手动更新 execution（重复操作）
execution.update!(
  status: result[:passed] ? 'passed' : 'failed',
  score: result[:score],
  verify_result: result,
  is_active: false
)
```

### 修改后

```ruby
# 创建验证器实例
validator = validator_class.new(session_id)

# ✅ 正确：使用 execute_verify
# cleanup: false 保留测试数据，方便手动检查
result = validator.execute_verify(cleanup: false)

# ✅ execute_verify 已经自动完成：
#   1. restore_execution_state → 恢复 @data_version
#   2. SET SESSION app.data_version
#   3. 调用 verify 方法
#   4. 计算 score 和 assertions
#   5. 更新 ValidatorExecution (validator_id, score, status, verify_result)

# ✅ 只需要补充设置 is_active = false
execution.update!(is_active: false)
```

## 关键变化

### 变化 1: 使用 execute_verify 而不是 run

```ruby
# 旧代码
result = validator.run  # NoMethodError

# 新代码
result = validator.execute_verify(cleanup: false)
```

### 变化 2: 不需要手动恢复 data_version

```ruby
# 旧代码 (不需要)
data_version = execution.state&.dig('data_version')
validator.instance_variable_set(:@data_version, data_version)

# 新代码
# execute_verify 内部会调用 restore_execution_state 自动恢复
```

### 变化 3: 不需要手动更新大部分字段

```ruby
# 旧代码 (部分重复)
execution.update!(
  status: result[:passed] ? 'passed' : 'failed',
  score: result[:score],
  verify_result: result,
  is_active: false
)

# 新代码 (execute_verify 已更新 status, score, verify_result)
execution.update!(is_active: false)
```

### 变化 4: cleanup 参数控制数据清理

```ruby
# 自动化测试（删除测试数据）
result = validator.execute_verify(cleanup: true)

# 手动测试（保留测试数据）
result = validator.execute_verify(cleanup: false)
```

## 为什么设计成 execute_verify？

### 设计理由

1. **状态恢复**: verify 阶段需要恢复 prepare 阶段的状态
2. **原子操作**: 验证和结果保存应该一起完成
3. **简化 API**: 调用者不需要关心内部细节
4. **一致性**: 与 `execute_prepare` 保持命名一致

### 对比其他可能的设计

```ruby
# ❌ 设计 1: 分离的方法（容易出错）
validator.restore_state
validator.verify
result = validator.get_result
validator.save_result

# ❌ 设计 2: 简单的 run（语义不清）
result = validator.run

# ✅ 设计 3: execute_verify（清晰且原子）
result = validator.execute_verify(cleanup: false)
```

## 响应格式调整

### API 响应格式

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

注意：
- `passed` 字段由 `result[:status] == 'passed'` 派生
- 前端期望 `passed` 布尔值，而 `execute_verify` 返回 `status` 字符串

## 测试验证

### 手动测试流程

1. 刷新页面: `http://localhost:3000/admin/validation_tasks/v001_create_post`
2. 点击 "启动新会话"
3. 创建一个帖子:
   - Title: "Hello World"
   - Content: "Test content"
   - Status: "published"
4. 点击 "Verify"
5. 应该看到:
   - Score: 1.0 (100%)
   - Status: Passed
   - Assertions: 2个绿色的断言

### 数据库验证

```bash
bin/rails runner "
execution = ValidatorExecution.last
puts 'Status: ' + execution.status
puts 'Score: ' + execution.score.to_s
puts 'Result: ' + execution.verify_result.to_json
"
```

预期输出:
```
Status: passed
Score: 1.0
Result: {"execution_id":"...","status":"passed","score":1.0,"assertions":[...],"errors":[]}
```

## 完整的验证流程

```
1. 用户点击 "Start New Session"
   → POST /api/tasks/v001_create_post/start
   → validator.execute_prepare
   → 保存 execution (execution_id, state, validator_id, user_id, status='running', is_active=true)
   
2. 用户执行测试操作（创建帖子）
   → 数据带有 data_version 标记
   
3. 用户点击 "Verify"
   → POST /api/verify/run
   → validator.execute_verify(cleanup: false)
     a. restore_execution_state → 恢复 @data_version
     b. SET SESSION app.data_version = '...'
     c. verify → 运行断言
     d. 计算分数和结果
     e. 更新 ValidatorExecution (validator_id, score, status, verify_result)
   → execution.update!(is_active: false)
   → 返回验证结果
   
4. 前端显示结果
   → 显示分数、断言列表、状态
```

## 相关文件

**修改文件**:
- `app/controllers/api/tasks_controller.rb` - verify action

**相关文件**:
- `app/validators/base_validator.rb` - execute_verify 方法
- `app/models/validator_execution.rb` - 模型定义

## 修复完成时间

2026-04-15

## 后续优化建议

1. **统一方法命名**:
   - 考虑添加 `run` 方法作为 `execute_verify` 的别名
   - 或者在文档中明确说明只使用 `execute_*` 系列方法

2. **改进错误处理**:
   - execute_verify 内部捕获了异常，但返回格式相同
   - 考虑添加更详细的错误分类

3. **文档完善**:
   - 在 BaseValidator 类注释中列出所有公共方法
   - 提供标准的 API Controller 使用示例
   - 说明 cleanup 参数的使用场景
