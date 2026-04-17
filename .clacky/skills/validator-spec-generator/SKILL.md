---
name: validator-spec-generator
description: 'Generate validator code files for Fliggy AI Agent capability testing. Use this skill when the user asks to generate a validator, create a validator file, make a new validator, or wants to auto-generate validators. Generates app/validators/{module}/xxx_validator.rb with prepare, verify, and simulate methods. Does NOT generate spec files.'
disable-model-invocation: false
user-invocable: true
---

# Validator Generator

## Purpose

自动生成 validator 代码文件，用于 Fliggy AI Agent 能力测试。生成的 validator 包含 prepare、verify、simulate 三个核心方法。

支持按业务模块分类，模块内自动编号。

## When to use this skill

- 用户说"生成 validator"、"创建 validator"、"自动生成验证器"
- 用户说"make a validator"、"generate validator"、"create validator file"
- 用户提供任务描述并要求生成对应的 validator

## Validator Structure Overview

Validator 继承自 `BaseValidator`，包含以下核心部分：

```ruby
class V001HotelValidator < BaseValidator
  self.validator_id = 'v001_hotel_validator'
  self.task_id = 'uuid-here'
  self.title = '任务标题'
  self.timeout_seconds = 300  # 默认 300 秒

  def prepare
    # 返回给 Agent 的任务参数（Hash）
    { task: "任务描述" }
  end

  def verify
    # 使用 add_assertion 验证 Agent 的操作结果
    add_assertion "断言描述", weight: 20 do
      expect(something).to be_truthy
    end
  end

  def simulate
    # （推荐）模拟 AI Agent 的操作，创建符合要求的数据
    # 用于自动化回归测试
  end
  
  private
  
  # （可选）保存执行状态
  def execution_state_data
    { param: @param }
  end
  
  # （可选）恢复执行状态
  def restore_from_state(data)
    @param = data['param']
  end
end
```

**设计理念**：本技能基于 Fliggy 项目中 **300+ 生产级 validator** 的最佳实践，提取共性模式并标准化为模板框架。

## 新的模块化结构（2026-04-17 更新）

### 目录结构

```
~/fliggy/app/validators/
  ├── hotel/
  │   ├── v001_hotel_validator.rb
  │   ├── v002_hotel_validator.rb
  │   └── v003_hotel_validator.rb
  ├── flight/
  │   ├── v001_flight_validator.rb
  │   └── v002_flight_validator.rb
  ├── attraction/
  │   ├── v001_attraction_validator.rb
  │   └── v002_attraction_validator.rb
  └── common/
      ├── v001_common_validator.rb
      └── v002_common_validator.rb
```

### 命名规则

- **目录名**：`{module}/`（小写，如 `hotel/`、`flight/`、`attraction/`）
- **文件名**：`v{编号}_{module}_validator.rb`（如 `v001_hotel_validator.rb`）
- **类名**：`V{编号}{Module}Validator`（如 `V001HotelValidator`，编号为整数，模块名首字母大写）
- **validator_id**：`v{编号}_{module}_validator`（如 `v001_hotel_validator`）

### 参数说明

- **--module**：指定模块名（默认：`common`）
  - 示例：`--module hotel`、`--module flight`、`--module attraction`
  - 如果不指定，默认使用 `common` 模块

- **--number**：手动指定编号（可选）
  - 示例：`--number 005`
  - 如果指定的编号已存在，自动递增到下一个可用编号并提示
  - 如果不指定，自动扫描模块目录，取最大编号 + 1

### 自动编号逻辑

1. 扫描 `~/fliggy/app/validators/{module}/` 目录
2. 找到所有 `v{XXX}_{module}_validator.rb` 文件（如 `v001_hotel_validator.rb`、`v002_hotel_validator.rb`）
3. 提取三位数字编号（001、002、003...）
4. 取最大值 + 1 作为新编号
5. 编号格式：三位数字，从 001 开始（如 001、002、003...）
6. 如果目录不存在或为空，从 001 开始

### 兼容性说明

- **旧项目向后兼容**：如果用户项目仍在使用旧的 `v001_v050/` 目录结构，可以暂时保留
- **新生成默认使用新格式**：所有新生成的 validator 使用模块化结构
- **迁移建议**：建议用户逐步将旧 validator 迁移到新的模块化结构

## Workflow

### 1. 收集信息

询问用户或从用户输入中提取：

**必需信息**：
- **任务标题**（title）：简短描述任务目标（例如：`给张三预订明天深圳欢乐港湾成人票`）
- **任务描述**（task description）：详细说明 Agent 需要完成什么操作
- **验证点**：需要验证哪些方面（例如：订单已创建、城市正确、日期正确等）

**可选信息**：
- **模块名**（--module）：如 `hotel`、`flight`、`attraction`（默认：`common`）
- **编号**（--number）：如 `005`（如果不指定，自动取下一个可用编号）
- **超时时间**：默认 240 秒

### 2. 确定文件路径和类名

#### 示例 1：指定模块为 `hotel`，自动编号

```bash
# 用户输入：生成 validator，模块 hotel
# 系统扫描 ~/fliggy/app/validators/hotel/ 目录
# 发现最大编号为 002
# 新编号：003
```

生成结果：
- **目录**：`~/fliggy/app/validators/hotel/`
- **文件名**：`v003_hotel_validator.rb`
- **类名**：`V003HotelValidator`
- **validator_id**：`v003_hotel_validator`

#### 示例 2：指定模块为 `flight`，手动指定编号 005

```bash
# 用户输入：生成 validator，模块 flight，编号 005
# 系统检查 ~/fliggy/app/validators/flight/v005_flight_validator.rb 是否存在
# 如果不存在，使用 005
# 如果已存在，自动递增到 006 并提示
```

生成结果：
- **目录**：`~/fliggy/app/validators/flight/`
- **文件名**：`v005_flight_validator.rb`
- **类名**：`V005FlightValidator`
- **validator_id**：`v005_flight_validator`

#### 示例 3：不指定模块（默认 `common`）

```bash
# 用户输入：生成 validator（没有指定模块）
# 系统使用默认模块 common
# 扫描 ~/fliggy/app/validators/common/ 目录
```

生成结果：
- **目录**：`~/fliggy/app/validators/common/`
- **文件名**：`v001_common_validator.rb`
- **类名**：`V001CommonValidator`
- **validator_id**：`v001_common_validator`

### 3. 生成 validator 代码

#### A. 文件头部注释

包含：
- 任务编号和标题
- 任务描述（详细说明）
- 复杂度分析（需要执行哪些步骤）
- 评分标准（每个验证点的权重）
- 使用方法（API 调用示例）

```ruby
# frozen_string_literal: true

require_relative '../base_validator'

# 验证用例 hotel_003: 给张三预订明天深圳欢乐港湾成人票（1张，最便宜供应商）
# 
# 任务描述:
#   Agent 需要在系统中搜索深圳欢乐港湾的门票，
#   找到成人票中价格最便宜的供应商并成功创建订单
# 
# 复杂度分析:
#   1. 需要搜索"深圳欢乐港湾"景点（从6个景点中找到）
#   2. 需要选择成人票类型（排除儿童票）
#   3. 需要对比多个供应商的价格（4个供应商）
#   4. 需要选择价格最低的供应商
#   5. 需要填写游玩日期（明天）和数量（1张）
#   6. 需要区分平日票和周末票（根据游玩日期）
#   ❌ 不能一次性提供：需要先搜索景点→选择票种→对比供应商→预订
# 
# 评分标准:
#   - 订单已创建 (15分)
#   - 订单属于张三（用户+联系电话） (15分)
#   - 景点正确（深圳欢乐港湾）(15分)
#   - 票种正确（成人票）(15分)
#   - 游玩日期正确（明天）(10分)
#   - 数量正确（1张）(10分)
#   - 选择了最便宜的供应商 (20分)
# 
# 使用方法:
#   # 准备阶段
#   POST /api/tasks/v003_hotel_validator/start
#   
#   # Agent 通过界面操作完成预订...
#   
#   # 验证结果
#   POST /api/verify/:execution_id/result
```

#### B. 类定义（新格式，无模块命名空间）

```ruby
class V003HotelValidator < BaseValidator
  self.validator_id = 'v003_hotel_validator'
  self.task_id = '生成新的UUID'
  self.title = '给张三预订明天深圳欢乐港湾成人票（1张，最便宜供应商）'
  self.timeout_seconds = 240
```

**重要变化**：
- **不再使用模块命名空间**（如 `V001V050`、`V051V100` 等）
- **类名格式**：`{Module}{编号}Validator`（如 `V001HotelValidator`、`V005FlightValidator`）
- `title` 字段是必需的
- **不需要 `description` 字段**
- `task_id` 使用 `SecureRandom.uuid` 生成

#### C. prepare 方法

返回一个 Hash，包含任务相关的信息：

```ruby
def prepare
  @city = '深圳'
  @check_in_date = Date.current + 1.day  # 明天
  
  # 可以查询基线数据（data_version: 0）
  available_hotels = Hotel.where(city: @city, data_version: 0)
  
  # 返回给 Agent 的任务信息
  {
    task: "请预订明天入住#{@city}的酒店",
    city: @city,
    check_in_date: @check_in_date.to_s,
    hint: "系统中有#{available_hotels.count}家酒店可选"
  }
end
```

**关键点**：
- 设置实例变量（`@city`, `@check_in_date` 等）供 verify 使用
- 返回的 Hash 会传递给 Agent
- 可以包含 `task`、`hint`、具体参数等

#### D. verify 方法

使用 `add_assertion` 验证 Agent 的操作结果：

```ruby
def verify
  # 断言1: 订单已创建
  add_assertion "订单已创建", weight: 25 do
    all_bookings = HotelBooking
      .where(data_version: @data_version)
      .order(created_at: :desc)
      .to_a
    expect(all_bookings).not_to be_empty, "未找到任何订单记录"
    @hotel_booking = all_bookings.first
  end
  
  return unless @hotel_booking  # 如果没有订单，后续断言无法继续
  
  # 断言2: 城市正确
  add_assertion "城市正确", weight: 15 do
    expect(@hotel_booking.hotel.city).to eq(@city),
      "城市错误。期望: #{@city}, 实际: #{@hotel_booking.hotel.city}"
  end
  
  # 断言3: 日期正确
  add_assertion "入住日期正确", weight: 15 do
    expect(@hotel_booking.check_in_date).to eq(@check_in_date),
      "入住日期错误。期望: #{@check_in_date}, 实际: #{@hotel_booking.check_in_date}"
  end
end
```

**关键点**：
- 每个 `add_assertion` 包含描述和权重（weight）
- 权重总和应为 100 分
- 使用 RSpec 的 `expect` 语法
- 提供清晰的错误消息（期望值 vs 实际值）
- 第一个断言通常检查核心实体是否创建
- 如果核心实体不存在，使用 `return` 提前退出

#### E. simulate 方法（可选但推荐）

模拟 AI Agent 的操作，创建符合要求的数据：

```ruby
def simulate
  # 1. 查找测试用户
  user = User.find_by!(email: 'demo@travel01.com', data_version: 0)
  
  # 2. 查找目标酒店
  hotel = Hotel.where(city: @city, data_version: 0).sample
  
  # 3. 创建订单
  booking = HotelBooking.create!(
    hotel_id: hotel.id,
    user_id: user.id,
    check_in_date: @check_in_date,
    check_out_date: @check_in_date + 1.day,
    rooms_count: 1,
    adults_count: 1,
    children_count: 0,
    total_price: 300.0,
    status: 'pending',
    guest_name: '张三',
    guest_phone: '13800138000',
    data_version: @data_version
  )
  
  # 4. 返回操作信息
  {
    action: 'create_hotel_booking',
    booking_id: booking.id,
    hotel_name: hotel.name,
    user_email: user.email
  }
end
```

**关键点**：
- 使用 `data_version: 0` 查询基线数据
- 创建的记录使用 `data_version: @data_version`（执行数据）
- 返回关键操作信息的 Hash

#### F. 私有辅助方法（可选）

```ruby
private

# 保存执行状态数据
def execution_state_data
  {
    city: @city,
    check_in_date: @check_in_date.to_s
  }
end

# 从状态恢复实例变量
def restore_from_state(data)
  @city = data['city']
  @check_in_date = Date.parse(data['check_in_date'])
end
```

### 4. 生成步骤总结

1. **收集信息**：任务标题、描述、验证点、模块名、编号（可选）
2. **确定编号**：
   - 如果用户指定了 `--number`，检查是否已存在
   - 如果已存在，自动递增并提示
   - 如果未指定，扫描目录取最大编号 + 1
3. **确定文件路径**：`~/fliggy/app/validators/{module}/{module}_{编号}_validator.rb`
4. **生成代码**：
   - 文件头部注释（任务说明、复杂度、评分标准）
   - 类定义（validator_id、task_id、title）
   - `prepare` 方法（返回任务参数）
   - `verify` 方法（add_assertion 验证结果）
   - `simulate` 方法（可选，模拟操作）
   - 私有辅助方法（可选，状态保存/恢复）
5. **创建目录**：如果 `~/fliggy/app/validators/{module}/` 不存在，自动创建
6. **写入文件**：使用 `write` 工具写入
7. **确认**：告诉用户文件已创建，提供路径和编号

## 编号扫描和自动递增示例

```ruby
# 扫描模块目录，获取下一个可用编号
def find_next_number(module_name)
  validators_dir = File.expand_path("~/fliggy/app/validators/#{module_name}")
  
  # 如果目录不存在，返回 001
  return "001" unless Dir.exist?(validators_dir)
  
  # 查找所有符合命名规范的文件
  pattern = File.join(validators_dir, "#{module_name}_*_validator.rb")
  files = Dir.glob(pattern)
  
  # 提取编号
  numbers = files.map do |file|
    basename = File.basename(file, '.rb')
    # 匹配 {module}_{编号}_validator
    match = basename.match(/^#{module_name}_(\d{3})_validator$/)
    match ? match[1].to_i : nil
  end.compact
  
  # 返回最大编号 + 1（格式化为三位数字）
  next_number = numbers.empty? ? 1 : numbers.max + 1
  format("%03d", next_number)
end

# 检查编号是否已存在
def number_exists?(module_name, number)
  validators_dir = File.expand_path("~/fliggy/app/validators/#{module_name}")
  file_path = File.join(validators_dir, "#{module_name}_#{number}_validator.rb")
  File.exist?(file_path)
end

# 获取可用编号（如果指定的编号已存在，自动递增）
def get_available_number(module_name, requested_number = nil)
  if requested_number
    # 用户手动指定了编号
    number = requested_number
    while number_exists?(module_name, number)
      puts "警告：编号 #{number} 已存在，自动递增..."
      number = format("%03d", number.to_i + 1)
    end
    number
  else
    # 自动获取下一个可用编号
    find_next_number(module_name)
  end
end
```

## Best Practices

### prepare 方法
- 清晰定义任务参数
- 使用实例变量存储关键数据
- 返回的 Hash 应易于 Agent 理解
- 可以包含 `hint` 提示信息

### verify 方法
- 第一个断言应检查核心实体（订单、预订等）
- 权重分配合理（总和 100 分）
- 提供清晰的错误消息（期望 vs 实际）
- 核心验证点权重更高
- 使用 `return unless @entity` 避免后续断言报错

### simulate 方法
- 完全模拟 Agent 的操作流程
- 确保创建的数据能通过 verify 验证
- 使用真实的测试用户和数据
- 返回关键操作信息

### 代码风格
- 使用 `frozen_string_literal: true`
- 详细的中文注释
- 清晰的变量命名
- 适当的空行和缩进

### 模块命名建议
- **hotel**：酒店预订相关
- **flight**：机票预订相关
- **train**：火车票预订相关
- **attraction**：景点门票相关
- **car**：租车相关
- **common**：通用或跨业务的任务

## Example: 简单的酒店预订 Validator（新格式）

```ruby
# frozen_string_literal: true

require_relative '../base_validator'

# 验证用例 hotel_020: 给张三预订明天深圳酒店（1间房1成人，入住2晚）
# 
# 任务描述:
#   Agent 需要在系统中搜索深圳的酒店，
#   预订明天入住、大后天退房（共2晚），
#   预订1间房、1位成人、0位儿童
# 
# 复杂度分析:
#   1. 需要搜索"深圳"城市的酒店（具体城市）
#   2. 需要选择"明天"入住日期（理解相对日期）
#   3. 需要正确计算2晚的离店日期（明天+2天=大后天）
#   4. 需要设置正确的房间数（1间）和人数（1成人0儿童）
# 
# 评分标准:
#   - 订单已创建 (25分)
#   - 城市正确（深圳） (15分)
#   - 入住日期正确（明天）(15分)
#   - 离店日期正确（大后天，共2晚）(25分)
#   - 房间数和人数正确（1间房，1成人，0儿童）(20分)

class V020HotelValidator < BaseValidator
  self.validator_id = 'v020_hotel_validator'
  self.task_id = 'cebea439-0ffc-4798-9edb-e5cef8d09100'
  self.title = '给张三预订明天深圳酒店（1间房1成人，入住2晚）'
  self.timeout_seconds = 240

  def prepare
    @city = '深圳'
    @check_in_date = Date.current + 1.day
    @nights = 2
    @check_out_date = @check_in_date + @nights.days
  
    {
      task: "请预订明天入住#{@city}的酒店（入住2晚）",
      city: @city,
      check_in_date: @check_in_date.to_s,
      nights: @nights
    }
  end

  def verify
    add_assertion "订单已创建", weight: 25 do
      all_bookings = HotelBooking
        .joins(:hotel)
        .where(hotels: { city: @city, data_version: 0 })
        .where(data_version: @data_version)
        .order(created_at: :desc)
        .to_a
      expect(all_bookings).not_to be_empty, "未找到任何订单"
      @hotel_booking = all_bookings.first
    end
  
    return unless @hotel_booking
  
    add_assertion "城市正确", weight: 15 do
      expect(@hotel_booking.hotel.city).to eq(@city)
    end
  
    add_assertion "入住日期正确", weight: 15 do
      expect(@hotel_booking.check_in_date).to eq(@check_in_date)
    end
  end

  def simulate
    user = User.find_by!(email: 'demo@travel01.com', data_version: 0)
    hotel = Hotel.where(city: @city, data_version: 0).sample
  
    HotelBooking.create!(
      hotel_id: hotel.id,
      user_id: user.id,
      check_in_date: @check_in_date,
      check_out_date: @check_out_date,
      rooms_count: 1,
      adults_count: 1,
      children_count: 0,
      total_price: 300.0,
      status: 'pending',
      guest_name: '张三',
      guest_phone: '13800138000',
      data_version: @data_version
    )
  end
end
```

## Anti-patterns to avoid

- **不要生成 spec 文件**：本技能只生成 validator 代码，不生成测试
- **不要使用 description 字段**：只使用 `title`
- **不要硬编码 UUID**：使用 `SecureRandom.uuid` 生成新的 `task_id`
- **不要使用旧的模块命名空间**：新格式不使用 `V001V050`、`V051V100` 等模块
- **不要使用旧的编号格式**：新格式使用 `v001_hotel` 而不是 `v001`（旧的 v001_v050 范围格式）
- **不要使用不合理的权重**：确保所有权重总和为 100
- **不要忽略数据版本**：查询基线数据用 `data_version: 0`，创建执行数据用 `@data_version`

## Fliggy 生产级 Validator 模板规范

### 核心设计原则

基于 Fliggy 项目 300+ 生产级 validator 的最佳实践：

1. **结构完整**：包含文档注释、prepare、verify、simulate、状态管理
2. **防御性强**：使用 Guard Clause 避免后续断言报错
3. **错误消息清晰**：格式为 `"字段名错误。期望: X, 实际: Y"`
4. **断言权重合理**：总分 100，核心断言权重更高
5. **可自动化**：simulate 方法可完整复现 Agent 操作

### 文档注释规范

```ruby
# frozen_string_literal: true

require_relative '../base_validator'

# 验证用例 v{NUMBER}_{MODULE}: {简短标题}
# 
# 任务描述:
#   {详细描述 Agent 需要完成的操作}
#   Agent 需要完成以下操作：
#   1. {步骤1}
#   2. {步骤2}
# 
# 复杂度分析:（可选，对于复杂任务）
#   1. {复杂度点1}
#   2. {复杂度点2}
#   ❌ 不能一次性提供：需要先{步骤A}→{步骤B}→{步骤C}
# 
# 评分标准:
#   - {断言1描述} ({权重}分)
#   - {断言2描述} ({权重}分)
#   ...
#   总分：100分
# 
# 使用方法:
#   POST /api/tasks/v{NUMBER}_{MODULE}_validator/start
```

### prepare 方法规范

```ruby
def prepare
  # 1. 设置业务参数（实例变量）
  @city = '深圳'
  @check_in_date = Date.current + 2.days  # 相对日期
  @nights = 1
  @check_out_date = @check_in_date + @nights.days
  
  # 2. 查询基线数据（data_version=0）
  eligible_items = {Model}.where(
    {core_field}: @{param},
    data_version: 0
  )
  
  # 3. 计算最优解（如需验证"最优选择"）
  @best_item = eligible_items.max_by { |i| i.rating / i.price.to_f }
  
  # 4. 返回任务信息
  {
    task: "给张三预订后天入住一晚#{@city}的经济型酒店...",
    city: @city,
    check_in_date: @check_in_date.to_s,
    date_description: "入住：后天（#{@check_in_date.strftime('%Y年%m月%d日')}）",
    hint: "系统中有多家酒店可选，请选择性价比最高的"
  }
end
```

### verify 方法规范

```ruby
def verify
  # 断言1（必需）：查询核心实体并存储（权重 20-25 分）
  add_assertion "{实体}已创建", weight: 20 do
    all_items = {Model}
      .joins(:association)  # 关联查询
      .where({core_field}: @{param})  # ✅ 只过滤核心实体
      .where(data_version: @data_version)  # ✅ 会话隔离
      .order(created_at: :desc)
      .to_a
    
    expect(all_items).not_to be_empty, 
      "未找到任何{实体}记录"
    
    @item = all_items.first
  end
  
  # Guard Clause（必需）：防御式编程
  return unless @item
  
  # 断言2-N：验证具体属性
  add_assertion "{核心属性}正确（{期望值}）", weight: 15 do
    expect(@item.{field}).to eq(@{expected}),
      "{字段名}错误。期望: #{@{expected}}, 实际: #{@item.{field}}"
  end
  
  # 高级断言：验证"最优选择"（权重 10-30 分）
  add_assertion "选择了{最优目标}", weight: 10 do
    best_item = eligible_items.max_by { ... }
    expect(@item.id).to eq(best_item.id),
      "未选择{最优目标}。应选: #{best_item.name}，实际选择: #{@item.name}"
  end
end
```

### simulate 方法规范

```ruby
def simulate
  # 1. 查找测试用户
  user = User.find_by!(email: 'demo@travel01.com', data_version: 0)
  
  # 2. 获取联系人信息
  contact = user.contacts.find_by!(name: '张三', data_version: 0)
  
  # 3. 查询目标实体（复用 prepare 逻辑）
  target_item = {Model}.where(...).max_by { ... }
  
  # 4. 创建记录
  record = {Model}.create!(
    {field}: {value},
    user_id: user.id,
    data_version: @data_version  # ✅ 会话隔离
  )
  
  # 5. 返回操作信息
  {
    action: 'create_{entity}',
    {entity}_id: record.id,
    {key_field}: record.{key_field}
  }
end
```

### 状态管理方法规范

```ruby
private

def execution_state_data
  {
    city: @city,
    check_in_date: @check_in_date.to_s,  # 日期转字符串
    best_item_id: @best_item&.id  # 对象只保存 ID
  }
end

def restore_from_state(data)
  @city = data['city']
  @check_in_date = Date.parse(data['check_in_date'])
  @best_item = {Model}.find_by(id: data['best_item_id']) if data['best_item_id']
end
```

### 断言权重分配参考

| 断言类型 | 权重范围 | 优先级 |
|---------|---------|--------|
| 实体已创建 | 20-25 | 最高 |
| 核心属性正确 | 10-15 | 高 |
| 日期/时间正确 | 10-15 | 高 |
| 价格/预算正确 | 15-20 | 高 |
| 最优选择正确 | 10-30 | 最高 |
| 数量/人数正确 | 5-10 | 中 |
| 联系人信息正确 | 5-10 | 中 |

**总分必须等于 100**

---

## When you're done

1. 确定模块名（默认 `common`）和编号（自动或手动指定）
2. 检查编号是否已存在，如已存在则自动递增并提示
3. 创建目录（如不存在）：`~/fliggy/app/validators/{module}/`
4. 使用 **Fliggy 生产级模板** 生成 validator 文件
5. 写入文件：`~/fliggy/app/validators/{module}/v{NUMBER}_{module}_validator.rb`
6. 告诉用户：
   - 文件已创建
   - 完整路径
   - 模块名和编号
   - 需要填充的 TODO 项
   - 如何使用（通过 API 或 Rails console）
7. **不生成任何 spec 文件**

---

## 生成器注意事项

生成 validator 时，**必须**在以下位置添加明确的 TODO 注释：

```ruby
# TODO: 设置业务参数
# TODO: 查询基线数据
# TODO: 根据业务模型修改查询
# TODO: 添加核心属性验证
# TODO: 实现自动化逻辑
```

这样用户可以清楚知道哪些部分需要填充业务逻辑。
