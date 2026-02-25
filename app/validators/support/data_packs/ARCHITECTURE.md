# 数据包系统架构说明

## 🎯 统一数据管理策略

**核心理念：所有数据通过 data_packs 版本化管理，降低维护成本**

```
app/validators/support/data_packs/v1/
├── base.rb          # 基础数据：City, Destination, Demo用户（永久保留）
├── flights.rb       # 航班测试数据（验证器专用，6个航班）
├── hotels.rb        # 酒店测试数据
├── hotels_seed.rb   # 酒店种子数据（待迁移到 hotels.rb）
├── trains.rb        # 火车测试数据
└── ...              # 其他业务数据包

db/seeds.rb          # 空入口，仅提供使用说明
```

## 设计理念

### 1. 初始状态：数据库为空

项目启动后，数据库默认为空，无任何预置数据。

### 2. 按需加载策略

- **基础数据**（City, Destination）：验证器运行时自动加载
- **业务数据**（Flight, Hotel 等）：各验证器根据需要加载对应的 data_pack
- **用户数据**（订单、乘客等）：验证过程中产生，验证后清除

### 3. 版本化管理

所有数据包采用版本化命名：
- `v1/base.rb` - 基础数据版本 1
- `v1/flights.rb` - 航班数据版本 1
- `v2/flights.rb` - 航班数据版本 2（当需要修改时创建新版本）

### 4. 数据隔离

- **基础数据**（City, Destination）：永久保留，所有验证器共享
- **测试数据**（Flight, Hotel 等）：验证器独占，验证后清除
- **订单数据**（Booking, HotelBooking 等）：验证过程产生，验证后清除

## 核心流程

### 数据加载顺序

```
1. ensure_checkpoint()
   ↓ 检查 City 表是否有数据
   ↓ 如果为空，加载 v1/base.rb
   ↓ 确保基础数据存在（City, Destination, Demo用户）

2. reset_test_data_only()
   ↓ 清空所有测试相关的表（Flight, Hotel, Train 等）
   ↓ 保留基础数据（City, Destination）
   ↓ 保留订单数据（Booking 等，会在验证后清理）
   ↓ 重置 ID 序列

3. load_data_pack()
   ↓ 执行数据包脚本（如 v1/flights.rb）
   ↓ 创建验证器专用的测试数据（如 6 个航班）
   ↓ 数据持久化到数据库，供用户操作使用
```

### execute_prepare() 流程

```ruby
# 1. 确保基础数据存在（持久化）
ensure_checkpoint()      # 加载 v1/base.rb（如果需要）

# 2. 清空测试数据表（持久化）
reset_test_data_only()   # 清空 Flight 等测试表

# 3. 加载验证器专有数据包（持久化）
load_data_pack()         # 加载 v1/flights.rb（6个航班）

# 4. 执行自定义准备逻辑
prepare()                # 验证器自定义准备

# 5. 保存执行状态
save_execution_state()   # 持久化执行状态

# 结果：
# - City 表有数据（永久保留）
# - Flight 表有 6 个测试航班（供用户操作）
# - 执行状态已保存
```

### execute_verify() 流程

```ruby
# 1. 恢复执行状态
restore_execution_state()  # 恢复准备阶段保存的状态

# 2. 执行验证
verify()                   # 验证用户操作结果

# 3. 清理执行状态
cleanup_execution_state()  # 删除执行状态

# 4. 回滚到 checkpoint
rollback_to_checkpoint()   # 清空测试数据和订单，保留基础数据

# 结果：
# - City 表有数据（保留）
# - Flight 表为空（已清除）
# - Booking 表为空（已清除）
# - 数据库恢复干净状态
```

## 数据分类

### 基础数据（永久保留）

**位置**: `v1/base.rb`

- **City**: 240+ 城市数据，包含机场代码、主题标签
- **Destination**: 目的地数据，与 City 关联
- **Demo用户**: demo@travel01.com，用于演示和测试

**特点**:
- 所有验证器共享
- 永久保留，不被清除
- 在 `reset_test_data_only()` 和 `rollback_to_checkpoint()` 中跳过

### 测试数据（验证器专用）

**位置**: `v1/flights.rb`, `v1/hotels.rb` 等

- **Flight**: 航班数据（如 6 个测试航班）
- **Hotel**: 酒店数据
- **Train**: 火车数据
- **Car**: 汽车租赁数据
- **BusTicket**: 巴士票数据

**特点**:
- 验证器独占使用
- 准备阶段加载（持久化）
- 验证后清除（rollback_to_checkpoint）

### 订单数据（验证过程产生）

**来源**: 用户操作产生

- **Booking**: 机票订单
- **HotelBooking**: 酒店订单
- **TrainBooking**: 火车票订单
- **其他订单**: CarOrder, BusTicketOrder 等

**特点**:
- 验证过程中产生
- 验证后清除（rollback_to_checkpoint）

## Checkpoint 机制

### 什么是 Checkpoint？

Checkpoint = `v1/base.rb` 加载完成后的数据库状态

- ✅ 包含：City, Destination, Demo用户
- ❌ 不包含：Flight, Hotel, Train 等业务数据
- ❌ 不包含：Booking, HotelBooking 等订单数据

### 为什么需要 Checkpoint？

**问题场景**：
```
初始状态: 数据库为空
验证器要求: 需要 City 数据（Flight 关联 departure_city）
```

**解决方案**：
```ruby
def ensure_checkpoint
  if City.count == 0
    load Rails.root.join('app/validators/support/data_packs/v1/base.rb')
  end
end
```

**执行时机**：
- 在 `execute_prepare()` 开始时调用
- 确保基础数据存在后再加载测试数据

### 回滚到 Checkpoint

**目的**：验证完成后恢复数据库到干净状态

```ruby
def rollback_to_checkpoint
  # 1. 清空测试数据（Flight, Hotel, Train 等）
  # 2. 清空订单数据（Booking, HotelBooking 等）
  # 3. 保留基础数据（City, Destination）
end
```

**结果**：
- City 表有数据（保留）
- Flight 表为空（清除）
- Booking 表为空（清除）
- 数据库状态 = Checkpoint 状态

## 实际执行示例

### 场景：BookFlightValidator 完整流程

```bash
# === 初始状态 ===
City.count      # => 0
Flight.count    # => 0
Booking.count   # => 0

# === 1. execute_prepare ===
validator = BookFlightValidator.new
validator.execute_prepare

# → ensure_checkpoint(): City 为空，加载 base.rb
City.count      # => 240 (基础数据)
Destination.count # => 240+

# → reset_test_data_only(): 清空测试表（已经是空的）
Flight.count    # => 0

# → load_data_pack(): 加载 v1/flights.rb
Flight.count    # => 6 (测试航班)

# → prepare(): 验证器自定义准备逻辑
# 返回任务信息给 Agent

# === 2. Agent 操作 ===
# Agent 通过界面搜索航班、创建订单
Booking.count   # => 1 (Agent 创建的订单)

# === 3. execute_verify ===
result = validator.execute_verify

# → restore_execution_state(): 恢复准备阶段的状态
# → verify(): 验证订单是否正确
# → cleanup_execution_state(): 清理执行状态
# → rollback_to_checkpoint(): 回滚到 checkpoint

# === 最终状态 ===
City.count      # => 240 (保留)
Flight.count    # => 0 (清除)
Booking.count   # => 0 (清除)
```

## 设计优势

### 1. 降低维护成本

- ✅ 所有数据统一在 data_packs 管理
- ✅ 版本化命名，修改时创建新版本
- ✅ 避免 db/seeds.rb 和 data_packs 重复

### 2. 数据隔离

- ✅ 基础数据（City）和测试数据（Flight）分离
- ✅ 验证器只修改测试数据，不影响基础数据
- ✅ 每个验证器独立加载所需数据包

### 3. 可重复性

- ✅ 每次验证前清空测试表
- ✅ 每次验证后回滚到 checkpoint
- ✅ 确保验证器可重复执行

### 4. 性能优化

- ✅ 按需加载，不加载不需要的数据
- ✅ 使用 `delete_all` 而不是 `destroy_all`（跳过回调）
- ✅ 重置 ID 序列避免冲突

### 5. 版本管理

- ✅ 数据包版本化（v1, v2, v3）
- ✅ 修改数据时创建新版本，保持向后兼容
- ✅ 验证器指定使用的数据包版本

## 使用方式

### 方式 1: 通过验证器自动加载（推荐）

```ruby
validator = BookFlightValidator.new
validator.execute_prepare  # 自动加载 base.rb + v1/flights.rb
```

### 方式 2: 手动加载基础数据

```bash
rails runner "load Rails.root.join('app/validators/support/data_packs/v1/base.rb')"
```

### 方式 3: 手动加载完整演示数据

```bash
# 加载基础数据
rails runner "load Rails.root.join('app/validators/support/data_packs/v1/base.rb')"

# 加载航班数据
rails runner "load Rails.root.join('app/validators/support/data_packs/v1/flights.rb')"

# 加载酒店数据
rails runner "load Rails.root.join('app/validators/support/data_packs/v1/hotels_seed.rb')"
```

## 创建新数据包

### 步骤

1. **创建文件**: `app/validators/support/data_packs/v1/<domain>.rb`
2. **编写数据**: 参考 `flights.rb` 的结构
3. **创建验证器**: 在 `app/validators/` 中创建验证器类
4. **指定版本**: 设置 `self.data_pack_version = 'v1/<domain>'`
5. **测试验证**: 使用 CLI 或 API 测试完整流程

### 示例：创建 trains.rb 数据包

```ruby
# app/validators/support/data_packs/v1/trains.rb
# frozen_string_literal: true

puts "正在加载 trains_v1 数据包..."

base_date = Date.current + 3.days

[
  {
    train_number: "G1234",
    departure_city: "深圳市",
    destination_city: "北京市",
    departure_time: base_date.to_time.in_time_zone.change(hour: 8, min: 0),
    arrival_time: base_date.to_time.in_time_zone.change(hour: 17, min: 30),
    price: 933.5,
    available_seats: 100
  }
].each do |attrs|
  Train.create!(attrs)
end

puts "✓ trains_v1 数据包加载完成（1个车次）"
```

### 在验证器中使用

```ruby
class BookTrainValidator < BaseValidator
  self.validator_id = 'book_train'
  self.title = '预订火车票'
  self.data_pack_version = 'v1/trains'  # 指定数据包版本
  
  def prepare
    # 数据已通过 load_data_pack 自动加载
  end
  
  def verify
    # 验证逻辑
  end
end
```

## 版本迭代

当需要修改数据时：

1. **创建新版本**: 复制为 `v2/<domain>.rb`
2. **修改数据**: 在新文件中进行修改
3. **更新验证器**: 修改 `data_pack_version = 'v2/<domain>'`
4. **保留旧版本**: 不删除旧文件，保持向后兼容

示例：

```ruby
# v1/flights.rb - 旧版本，6个航班
# v2/flights.rb - 新版本，10个航班，增加了更多航线

# 新验证器使用 v2
class BookFlightV2Validator < BaseValidator
  self.data_pack_version = 'v2/flights'
end

# 旧验证器仍使用 v1
class BookFlightValidator < BaseValidator
  self.data_pack_version = 'v1/flights'
end
```

## 注意事项

1. **不要修改已发布的数据包**: 创建新版本而非修改现有版本
2. **确保数据完整性**: 外键关联必须正确（如 Flight 的 departure_city 必须在 City 表中存在）
3. **必须使用动态日期**: 使用 `Date.current + N.days` 而不是 `Date.parse('2024-12-20')`
4. **测试数据真实性**: 数据应接近真实场景
5. **验证器日期一致性**: 验证器的 `prepare` 方法必须使用与数据包相同的日期逻辑

## 常见问题

### Q: 为什么不在 db/seeds.rb 中加载数据？

A: 统一管理降低维护成本。所有数据通过 data_packs 版本化管理，避免 seeds.rb 和 data_packs 重复维护。

### Q: 如何查看当前数据库状态？

A: 使用 rails console:
```ruby
City.count         # 基础数据
Flight.count       # 测试数据
Booking.count      # 订单数据
```

### Q: prepare 后为什么 Flight.count != 0？

A: 这是正确的。prepare 加载的数据是持久化的，供用户操作使用。verify 完成后会通过 rollback_to_checkpoint 清除。

### Q: 如何清空所有数据重新开始？

A: 
```bash
# 方式1: 重置数据库
rails db:reset

# 方式2: 手动清空
rails runner "Flight.delete_all; Booking.delete_all; City.delete_all; Destination.delete_all"

# 然后重新加载基础数据
rails runner "load Rails.root.join('app/validators/support/data_packs/v1/base.rb')"
```

### Q: 能否在一个验证器中使用多个数据包？

A: 可以。重写 `load_data_pack` 方法：

```ruby
class ComplexValidator < BaseValidator
  self.data_pack_version = 'v1/complex'
  
  def load_data_pack
    load Rails.root.join('app/validators/support/data_packs/v1/flights.rb')
    load Rails.root.join('app/validators/support/data_packs/v1/hotels.rb')
    load Rails.root.join('app/validators/support/data_packs/v1/trains.rb')
  end
end
```

## 相关文件

- `db/seeds.rb`: 空入口，提供使用说明
- `app/validators/support/data_packs/v1/base.rb`: 基础数据包
- `app/validators/support/data_packs/v1/*.rb`: 各业务数据包
- `app/validators/base_validator.rb`: 数据包加载逻辑
- `app/validators/*_validator.rb`: 具体验证器实现
