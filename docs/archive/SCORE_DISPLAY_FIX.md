> ⚠️ **Archived** — 一次性修复笔记，仅保留作历史参考，勿模仿。

# Score Display Fix - 10000% Issue

## 问题描述

验证结果显示 "10000%" 而不是 "100%"，权重显示 "+50分" 正确。

**截图问题**:
- 总得分显示: 10000%
- 断言 1: 权重 50%, +50分
- 断言 2: 权重 50%, +50分

## 根本原因

**前后端数据格式不一致**:

### 后端 (BaseValidator)

`execute_verify` 返回的 `score` 是累加的权重总和（0-100）：

```ruby
# app/validators/base_validator.rb:543
def add_assertion(name, weight:)
  # ...
  @score += weight  # 累加权重: 50 + 50 = 100
end

# app/validators/base_validator.rb:320
result[:score] = @score  # 返回 100（不是 1.0）
```

### 前端 (View)

前端认为 `score` 是比例（0-1.0），所以乘以 100：

```javascript
// app/views/admin/validation_tasks/show.html.erb:445
const scorePercent = (data.score * 100).toFixed(0);
// 如果 data.score = 100，则 scorePercent = 10000
```

### 导致的问题

```
后端返回: score = 100 (权重总和)
前端计算: 100 * 100 = 10000
显示结果: 10000%
```

## 解决方案

### 修改后端：归一化 score 为 0-1.0

**文件**: `app/validators/base_validator.rb:295-357`

```ruby
def execute_verify(cleanup: true)
  # ...
  
  # 执行验证
  verify
  
  # ✅ 计算总权重和归一化分数
  total_weight = @assertions.sum { |a| a[:weight] }
  normalized_score = total_weight > 0 ? (@score.to_f / total_weight).round(4) : 0.0
  
  # 计算结果
  result[:status] = @errors.empty? ? 'passed' : 'failed'
  result[:score] = normalized_score  # 归一化为 0-1.0 (100 / 100 = 1.0)
  result[:assertions] = @assertions
  result[:errors] = @errors
  
  # 保存到数据库时也使用归一化分数
  ActiveRecord::Base.connection.execute(
    "UPDATE validator_executions SET " \
    "score = #{normalized_score}, " \
    "..."
  )
end
```

### 关键改动

**修改前**:
```ruby
result[:score] = @score  # 100
```

**修改后**:
```ruby
total_weight = @assertions.sum { |a| a[:weight] }  # 50 + 50 = 100
normalized_score = (@score.to_f / total_weight).round(4)  # 100 / 100 = 1.0
result[:score] = normalized_score  # 1.0
```

### 前端保持不变

前端的计算逻辑正确，不需要修改：

```javascript
const scorePercent = (data.score * 100).toFixed(0);
// data.score = 1.0 → scorePercent = 100
```

## 验证结果

### 示例计算

**v001_create_post_validator**:
- 断言 1: weight = 50, passed = true
- 断言 2: weight = 50, passed = true

**后端计算**:
```
@score = 50 + 50 = 100
total_weight = 50 + 50 = 100
normalized_score = 100 / 100 = 1.0
```

**前端显示**:
```
scorePercent = 1.0 * 100 = 100
显示: 100%
```

### 部分通过的情况

假设只有断言 1 通过：
```
@score = 50
total_weight = 100
normalized_score = 50 / 100 = 0.5
scorePercent = 0.5 * 100 = 50
显示: 50%
```

## 为什么选择归一化为 0-1.0？

### 优势

1. **标准化**: 机器学习和评分系统通常使用 0-1.0 范围
2. **数据库存储**: `score` 字段类型可以是 `decimal` 或 `float`，不受权重总和限制
3. **前端友好**: 前端只需乘以 100 即可显示百分比
4. **灵活性**: 不同验证器可以有不同的权重分配（如 30/70, 40/60），前端不需要关心总权重

### 对比方案

**方案 1: 后端归一化（已采用）**
```ruby
# 后端
result[:score] = normalized_score  # 0-1.0

# 前端
const scorePercent = (data.score * 100).toFixed(0);
```

**方案 2: 前端不乘以 100（未采用）**
```ruby
# 后端
result[:score] = @score  # 0-100

# 前端
const scorePercent = data.score.toFixed(0);  # 需要判断 score 是比例还是百分比
```

方案 1 更清晰，因为 API 返回值有明确的语义（0-1.0 = 比例）。

## 数据库影响

### ValidatorExecution.score 字段

**迁移前的数据** (如果有):
- 旧记录: `score = 100.0`
- 新记录: `score = 1.0`

**如果需要迁移旧数据**:
```ruby
# db/migrate/xxx_normalize_validator_execution_scores.rb
class NormalizeValidatorExecutionScores < ActiveRecord::Migration[7.2]
  def up
    # 归一化所有大于 1.0 的分数
    execute <<-SQL
      UPDATE validator_executions
      SET score = score / 100.0
      WHERE score > 1.0
    SQL
  end
  
  def down
    execute <<-SQL
      UPDATE validator_executions
      SET score = score * 100.0
      WHERE score <= 1.0
    SQL
  end
end
```

## 测试验证

### 手动测试

1. 刷新页面: `http://localhost:3000/admin/validation_tasks/v001_create_post`
2. 点击 "启动新会话"
3. 创建帖子 (Title: "Hello World", Status: "published")
4. 点击 "Verify"
5. **预期结果**: 显示 "100%" 而不是 "10000%"

### 单元测试

```ruby
# spec/validators/base_validator_spec.rb
RSpec.describe BaseValidator do
  describe '#execute_verify' do
    it 'normalizes score to 0-1.0 range' do
      validator = V001CreatePostValidator.new
      # ... setup ...
      result = validator.execute_verify(cleanup: false)
      
      expect(result[:score]).to be_between(0.0, 1.0)
      expect(result[:score]).to eq(1.0) if all_assertions_passed
    end
  end
end
```

## 相关文件

**修改文件**:
- `app/validators/base_validator.rb` - execute_verify 方法

**相关文件**:
- `app/views/admin/validation_tasks/show.html.erb` - 前端显示逻辑（不需要修改）
- `app/validators/v001_create_post_validator.rb` - 示例验证器（不需要修改）

## 修复完成时间

2026-04-15

## 后续建议

1. **添加注释**: 在 BaseValidator 中明确说明 score 是 0-1.0 范围
2. **API 文档**: 更新 API 文档说明 score 字段格式
3. **数据迁移**: 如果生产环境有旧数据，运行迁移脚本归一化分数
4. **单元测试**: 添加测试验证 score 始终在 0-1.0 范围内
