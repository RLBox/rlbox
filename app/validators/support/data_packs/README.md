# 验证数据包说明

## 🎯 统一数据管理策略

**所有数据通过 data_packs 版本化管理，prepare 阶段自动加载最新版本下的所有数据包**

```
app/validators/support/data_packs/v1/
├── base.rb                    # 基础数据
├── demo_user.rb               # 默认用户数据
db/seeds.rb                    # 空入口，仅提供使用说明
```

## 核心理念

### 1. 初始状态：数据库为空

项目启动后，数据库默认为空，无任何预置数据。

### 2. 自动全量加载策略

- **基础数据**：验证器运行时自动加载（`ensure_checkpoint`）
- **用户数据**：验证过程中产生，验证后清除

### 4. 数据隔离

- **基础数据**：永久保留，所有验证器共享
- **用户数据**：验证过程产生，验证后清除

## 核心流程

### 数据加载顺序

```
1. ensure_checkpoint()
   ↓ 检查 City 表是否有数据
   ↓ 如果为空，加载 v1/base.rb
   ↓ 加载 v1/demo_user.rb
   ↓ 确保基础数据存在（base.rb, demo_user.rb）

2. reset_test_data_only()
   ↓ 清空所有用户数据
   ↓ 重置 ID 序列

3. load_all_data_packs()
   ↓ 扫描 v1 目录下所有 .rb 文件（排除 base.rb）
   ↓ 按文件名排序后依次加载
   ↓ 输出加载日志，便于调试
   ↓ 所有数据持久化到数据库，供用户操作使用
```

### execute_prepare() 流程

```ruby
# 1. 确保基础数据存在（持久化）
ensure_checkpoint()          # 加载 v1/base.rb（如果需要）

# 2. 清空测试数据表（持久化）
reset_test_data_only()       # 清空所有用户数据

# 3. 加载所有业务数据包（持久化）
load_all_data_packs()        # 自动加载 v1 目录下所有数据包
                             # flights.rb, hotels.rb, cars.rb, ...

# 4. 执行自定义准备逻辑
prepare()                    # 验证器自定义准备

# 5. 保存执行状态
save_execution_state()       # 持久化执行状态

# 结果：
# - City 表有数据（永久保留）
# - 所有数据有数据（供用户操作）
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
# - 所有数据为空（已清除）
# - Booking 表为空（已清除）
# - 数据库恢复干净状态
```

## 数据分类

### 基础数据（永久保留）

**位置**: `v1/base.rb`

- **base.rb**: 基础数据
- **demo_user.rb**: 默认用户数据

**特点**:
- 所有验证器共享
- 永久保留，不被清除
- 在 `reset_test_data_only()` 和 `rollback_to_checkpoint()` 中跳过

### 用户数据（全量加载）

**位置**: `v1/*.rb`（除 base.rb 外的所有文件）

当前包含的用户数据：
- **demo_user.rb**: 默认用户数据

**特点**:
- prepare 阶段自动全量加载
- 验证后清除（rollback_to_checkpoint）
- 验证器无需指定加载哪些数据包

### 用户数据（验证过程产生）

**来源**: 用户操作产生

- **User**: 用户数据

**特点**:
- 验证过程中产生
- 验证后清除（rollback_to_checkpoint）

## Checkpoint 机制

### 什么是 Checkpoint？

Checkpoint = `v1/base.rb` 加载完成后的数据库状态

- ✅ 包含：base.rb, demo_user.rb
- ❌ 不包含：用户数据

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
Hotel.count     # => 0
Booking.count   # => 0

# === 1. execute_prepare ===
validator = BookFlightValidator.new
validator.execute_prepare

# → ensure_checkpoint(): City 为空，加载 base.rb
City.count      # => 240 (基础数据)
Destination.count # => 240+

# → reset_test_data_only(): 清空测试表（已经是空的）
Flight.count    # => 0
Hotel.count     # => 0

# → load_all_data_packs(): 加载 v1 下所有数据包
# 📦 正在加载 v1 数据包...
#   → 加载 abroad_shopping.rb
#   → 加载 abroad_tickets.rb
#   → 加载 bus_tickets.rb
#   → 加载 cars.rb
#   → 加载 deep_travel.rb
#   → 加载 flights.rb
#   → 加载 hotel_packages.rb
#   → 加载 hotels.rb
#   → 加载 hotels_seed.rb
#   → 加载 internet_services.rb
#   → 加载 tour_group_products.rb
# ✓ 所有数据包加载完成

Flight.count    # => 6 (测试航班)
Hotel.count     # => N (酒店数据)
Car.count       # => M (汽车租赁数据)
# ... 其他业务数据

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
Hotel.count     # => 0 (清除)
Booking.count   # => 0 (清除)
```

## 设计优势

### 1. 降低维护成本

- ✅ 所有数据统一在 data_packs 管理
- ✅ 版本化命名，修改时创建新版本
- ✅ 无需在验证器中指定加载哪些数据包

### 2. 自动化加载

- ✅ prepare 阶段自动加载所有数据包
- ✅ 新增数据包无需修改代码，自动识别
- ✅ 验证器专注业务逻辑，无需关心数据加载

### 3. 数据隔离

- ✅ 基础数据（City）和测试数据（Flight）分离
- ✅ 验证器只修改测试数据，不影响基础数据
- ✅ 每次验证前清空测试表，确保干净环境

### 4. 可重复性

- ✅ 每次验证前清空测试表
- ✅ 每次验证后回滚到 checkpoint
- ✅ 确保验证器可重复执行

### 5. 性能优化

- ✅ 使用 `delete_all` 而不是 `destroy_all`（跳过回调）
- ✅ 重置 ID 序列避免冲突
- ✅ 批量加载，减少单次加载开销

### 6. 版本管理

- ✅ 数据包版本化（v1, v2, v3）
- ✅ 修改数据时创建新版本，保持向后兼容
- ✅ 全局切换版本，所有验证器同步更新

## 使用方式

### 方式 1: 通过验证器自动加载（推荐）

```ruby
validator = BookFlightValidator.new
validator.execute_prepare  # 自动加载 base.rb + v1 下所有数据包
```

### 方式 2: 手动加载基础数据

```bash
rails runner "load Rails.root.join('app/validators/support/data_packs/v1/base.rb')"
```

### 方式 3: 手动加载完整演示数据

```bash
# 加载基础数据
rails runner "load Rails.root.join('app/validators/support/data_packs/v1/base.rb')"

# 加载所有业务数据包
rails runner "Dir.glob(Rails.root.join('app/validators/support/data_packs/v1/*.rb')).reject { |f| File.basename(f) == 'base.rb' }.sort.each { |f| load f }"
```

### 方式 4: 通过 db:seed 加载（会显示使用说明）

```bash
rails db:seed
# 输出使用说明和手动加载命令
```

## 创建新数据包

### 步骤

1. **创建文件**：`app/validators/support/data_packs/v1/<domain>.rb`
2. **编写数据**：参考现有数据包的结构
3. **无需配置**：新文件会自动被 `load_all_data_packs` 识别和加载
4. **测试验证**：运行任意验证器，新数据包会自动加载

### 示例：创建 trains.rb 数据包

```ruby
# app/validators/support/data_packs/v1/trains.rb
# frozen_string_literal: true

# trains_v1 数据包
# 用于火车票预订验证任务

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
    available_seats: 100,
    train_date: base_date
  }
].each do |attrs|
  Train.create!(attrs)
end

puts "✓ trains_v1 数据包加载完成（1个车次）"
```

创建文件后，无需任何配置，下次运行任何验证器时会自动加载。

## 版本迭代

当需要修改数据时：

1. **创建新版本目录**: `mkdir app/validators/support/data_packs/v2`
2. **复制所有文件**: `cp app/validators/support/data_packs/v1/* app/validators/support/data_packs/v2/`
3. **修改数据**: 在 v2 目录中修改需要更新的数据包
4. **切换版本**: 修改 `BaseValidator::DATA_PACK_VERSION = 'v2'`
5. **保留旧版本**: v1 目录保留，保持向后兼容

示例：

```ruby
# app/validators/base_validator.rb
class BaseValidator
  # 数据包版本（当前使用 v2）
  DATA_PACK_VERSION = 'v2'  # 修改这一行即可全局切换
  
  # ...
end
```

所有验证器会自动使用 v2 版本的数据包。

## 数据包规范

### 文件命名

- 格式：`<domain>.rb`
- 示例：`flights.rb`, `hotels.rb`, `trains.rb`
- domain：业务领域（flights, hotels, trains等）

### 文件结构

```ruby
# frozen_string_literal: true

# <domain>_v<version> 数据包
# 用于 <具体验证任务描述>
#
# 数据说明：
# - <数据集1描述>
# - <数据集2描述>

puts "正在加载 <domain>_v<version> 数据包..."

# ==================== 动态日期设置 ====================
base_date = Date.current + 3.days  # 使用动态日期
base_datetime = base_date.to_time.in_time_zone

# ==================== 数据创建 ====================
[
  {
    field1: "value1",
    field2: 100,
    date_field: base_date  # 使用动态日期
  }
].each do |attrs|
  Model.create!(attrs)
end

puts "✓ <domain>_v<version> 数据包加载完成（<数量>条记录）"
```

### 最佳实践

1. **明确数据用途**：在注释中说明数据包的用途和特征
2. **使用动态日期**：使用 `Date.current + N.days` 而不是固定日期
3. **输出清晰日志**：加载开始和结束时输出日志，便于调试
4. **数据关联正确**：确保外键关联正确（如 Flight 的 departure_city 必须在 City 表中存在）
5. **不使用显式 ID**：让数据库自动生成 ID，避免冲突
6. **数据量适中**：测试数据应足够但不过多，避免影响性能

## 注意事项

1. **不要修改已发布的数据包**：创建新版本而非修改现有版本
2. **确保数据完整性**：外键关联必须正确
3. **必须使用动态日期**：使用 `Date.current + N.days` 而不是固定日期
4. **测试数据真实性**：数据应接近真实场景
5. **不要在 db/seeds.rb 中添加数据**：所有数据统一在 data_packs 管理
6. **新增数据包无需配置**：创建文件后会自动加载

## 常见问题

### Q: 为什么自动加载所有数据包？

A: 简化验证器开发。验证器无需关心加载哪些数据包，专注业务逻辑。新增数据包无需修改代码。

### Q: 如何只加载特定数据包？

A: 当前架构不支持选择性加载。如需此功能，可以：
1. 将不需要的数据包移出 v1 目录
2. 或创建单独的版本目录（如 v1_minimal）仅包含需要的数据包

### Q: 为什么不在 db/seeds.rb 中加载数据？

A: 统一管理降低维护成本。所有数据通过 data_packs 版本化管理，避免重复维护。

### Q: 如何查看当前数据库状态？

A: 使用 rails console:
```ruby
City.count         # 基础数据
Flight.count       # 测试数据
Booking.count      # 订单数据
```

### Q: prepare 后为什么所有表都有数据？

A: 这是正确的。prepare 加载的数据是持久化的，供用户操作使用。verify 完成后会通过 rollback_to_checkpoint 清除。

### Q: 如何清空所有数据重新开始？

A: 
```bash
# 方式1: 重置数据库
rails db:reset

# 方式2: 手动清空
rails runner "Flight.delete_all; Hotel.delete_all; Booking.delete_all; City.delete_all; Destination.delete_all"

# 然后重新加载基础数据
rails runner "load Rails.root.join('app/validators/support/data_packs/v1/base.rb')"
```

### Q: 如何升级数据包版本？

A: 
1. 创建新版本目录：`mkdir app/validators/support/data_packs/v2`
2. 复制并修改数据包
3. 修改 `BaseValidator::DATA_PACK_VERSION = 'v2'`
4. 所有验证器自动切换到 v2

## 相关文件

- `db/seeds.rb`: 空入口，提供使用说明
- `app/validators/support/data_packs/v1/base.rb`: 基础数据包
- `app/validators/support/data_packs/v1/*.rb`: 各业务数据包
- `app/validators/support/data_packs/ARCHITECTURE.md`: 架构详细文档
- `app/validators/base_validator.rb`: 数据包加载逻辑
- `app/validators/*_validator.rb`: 具体验证器实现
