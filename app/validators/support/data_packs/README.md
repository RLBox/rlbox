# 验证数据包说明

## 🎯 统一数据管理策略

**所有数据通过 data_packs 版本化管理，应用启动时自动将所有数据包一次性加载为基线数据（`data_version='0'`），供所有验证器共享使用。**

```
app/validators/support/data_packs/v1/
├── base.rb                    # 基础数据（优先加载）
├── demo_user.rb               # 默认用户数据
db/seeds.rb                    # 空入口，仅提供使用说明
```

## 核心理念

### 1. 数据隔离基于 data_version，而非数据分类

rlbox 使用 **PostgreSQL RLS（行级安全策略）+ `data_version` 字段** 实现数据隔离，不再区分"基础数据"与"用户数据"。

- **基线数据**（`data_version='0'`）：应用启动时加载的所有数据包，所有验证器共享，永久保留
- **验证专属数据**（`data_version='<hex>'`）：验证器 prepare 阶段由用户操作产生，验证完成后删除

### 2. 全量一次性加载策略

应用启动时（通过 initializer），将 `v1/` 目录下所有数据包**一次性全量加载**为基线数据：
- 先加载 `base.rb`，再按文件名排序加载其余文件
- 所有记录的 `data_version='0'`，不会被验证流程清除
- 无需区分哪些是"基础数据"，哪些是"业务数据"，统一管理

### 3. RLS 自动过滤

每次验证器 prepare 时生成唯一的 `data_version`（16位十六进制），设置到 PostgreSQL 会话变量 `app.data_version`：
- RLS 策略自动过滤查询：返回 `data_version='0'`（基线）+ 当前会话版本的数据
- 用户操作产生的新记录自动打上当前 `data_version` 标记
- 验证完成后仅删除当前 `data_version` 的记录，基线数据不受影响

## 核心流程

### 数据加载时机

```
应用启动（initializer）
  ↓ config/initializers/validator_baseline.rb
  ↓ 检查是否已有 data_version='0' 的基线数据
  ↓ 如果没有，设置会话变量 app.data_version = '0'
  ↓ 优先加载 base.rb，再按序加载其余数据包
  ↓ 所有数据以 data_version='0' 写入数据库
  ✓ 基线数据就绪，供所有验证器共享
```

> **Fallback 机制**：`execute_simulate` 调用时会通过 `ensure_baseline_data_loaded` 检查基线数据是否存在，若不存在则触发加载（适用于 rake/test 等非 Web 上下文）。

### execute_prepare() 流程

```ruby
# 1. 检查 UI 能力声明（requires_ui 校验）
check_ui_requirements!

# 2. 生成唯一 data_version 并设置会话变量
@data_version = SecureRandom.hex(8)   # 示例: "a3f9c8b2e1d4567f"
SET SESSION app.data_version = '<hex>'

# 3. 执行验证器自定义准备逻辑
prepare()    # 通常仅返回任务描述，无需手动加载数据（基线已就绪）

# 4. 保存执行状态（含 data_version）
save_execution_state()

# 结果：
# - 基线数据（data_version='0'）已在数据库中
# - 会话变量指向当前 data_version
# - 用户后续操作产生的记录将自动打上该 data_version
```

### execute_verify() 流程

```ruby
# 1. 恢复执行状态（含 data_version）
restore_execution_state()
SET SESSION app.data_version = '<hex>'   # 恢复会话变量

# 2. 执行验证
verify()                    # 验证用户操作结果

# 3. 清理执行状态记录
cleanup_execution_state()

# 4. 回滚到基线（删除当前 data_version 的所有数据）
rollback_to_baseline()

# 结果：
# - 基线数据（data_version='0'）保留
# - 当前验证产生的数据（data_version='<hex>'）已删除
# - 数据库恢复干净的基线状态
```

## 数据分类

### 基线数据（全量加载，永久保留）

**位置**: `v1/*.rb`（所有数据包）

当前 rlbox 包含的数据包（示例）：
- **base.rb**: 基础数据（城市、目的地等）
- **demo_user.rb**: 默认用户数据

**特点**:
- 应用启动时一次性全量加载，`data_version='0'`
- 所有验证器共享
- 永久保留，不被 `rollback_to_baseline` 清除
- 新增数据包无需修改代码，重启后自动加载

### 验证专属数据（验证过程产生）

**来源**: 用户在界面上操作产生（如创建订单）

**特点**:
- 自动打上当前 `data_version` 标记（由 `DataVersionable` before_create 钩子写入）
- 验证完成后通过 `rollback_to_baseline` 删除
- 下一次验证使用全新的 `data_version`，互不干扰

## data_version 机制

### 什么是 data_version？

`data_version` 是每条数据库记录上的字段，标识该记录属于哪个"数据版本"：

| data_version | 含义 |
|---|---|
| `'0'` | 基线数据，应用启动时加载，永久保留 |
| `'a3f9c8b2e1d4567f'` | 某次验证会话的专属数据，验证后删除 |

### RLS 如何工作？

```sql
-- 会话变量设置后，RLS 策略自动过滤
-- 查询只返回基线数据 + 当前会话数据
SET SESSION app.data_version = 'a3f9c8b2e1d4567f';

-- 此时 Flight.all 等价于:
-- SELECT * FROM flights WHERE data_version IN ('0', 'a3f9c8b2e1d4567f')
```

### 为什么不再需要 ensure_checkpoint / reset_test_data_only？

旧方案（fliggy 风格）通过"清空数据表再重新加载"来确保干净环境，维护成本高。

rlbox 的新方案通过 `data_version` 实现天然隔离：
- ✅ 基线数据只加载一次，无需反复清空重载
- ✅ 每次验证使用独立的 `data_version`，互不干扰
- ✅ 回滚只删除当前版本的记录，速度更快，更安全

## 实际执行示例

### 场景：完整验证流程

```bash
# === 应用启动状态 ===
# (initializer 已加载基线数据)
City.unscoped.where(data_version: '0').count      # => N (基础城市数据)
Flight.unscoped.where(data_version: '0').count    # => 0 (rlbox 暂无航班基线数据)

# === 1. execute_prepare ===
validator = SomeValidator.new
validator.execute_prepare

# → check_ui_requirements!(): 校验前端 UI 能力
# → @data_version = "a3f9c8b2e1d4567f"
# → SET SESSION app.data_version = 'a3f9c8b2e1d4567f'
# → prepare(): 返回任务描述
# → save_execution_state(): 保存状态到 validator_executions 表

# === 2. 用户/Agent 操作 ===
# 用户在界面操作，产生新记录（自动标记 data_version='a3f9c8b2e1d4567f'）
Booking.where(data_version: 'a3f9c8b2e1d4567f').count   # => 1

# === 3. execute_verify ===
result = validator.execute_verify

# → restore_execution_state(): 恢复 @data_version
# → SET SESSION app.data_version = 'a3f9c8b2e1d4567f'
# → verify(): 验证用户操作结果
# → cleanup_execution_state(): 删除执行状态记录
# → rollback_to_baseline(): 删除 data_version='a3f9c8b2e1d4567f' 的所有记录

# === 最终状态 ===
City.unscoped.where(data_version: '0').count     # => N (基线保留)
Booking.where(data_version: 'a3f9c8b2e1d4567f').count  # => 0 (已清除)
```

## 使用方式

### 方式 1: 通过验证器自动使用（推荐）

```ruby
# 验证器无需手动加载数据，基线数据在应用启动时已就绪
validator = SomeValidator.new
validator.execute_prepare  # 设置 data_version，调用 prepare()
# ... 用户操作 ...
validator.execute_verify   # 验证后自动回滚
```

### 方式 2: 手动触发基线加载（开发/调试用）

```bash
# 加载所有数据包为基线数据
rails runner "
  ActiveRecord::Base.connection.execute(\"SET SESSION app.data_version = '0'\")
  Dir.glob(Rails.root.join('app/validators/support/data_packs/v1/*.rb')).sort.tap { |fs|
    base = fs.find { |f| File.basename(f) == 'base.rb' }
    fs.delete(base); fs.unshift(base) if base
  }.each { |f| load f }
"
```

### 方式 3: 通过 db:seed 加载（会显示使用说明）

```bash
rails db:seed
# 输出使用说明和手动加载命令
```

## 创建新数据包

### 步骤

1. **创建文件**：`app/validators/support/data_packs/v1/<domain>.rb`
2. **编写数据**：参考现有数据包的结构
3. **无需配置**：重启应用后，新文件会自动被 initializer 识别并加载为基线数据

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

创建文件后，**重启应用**即可自动加载，无需修改任何代码。

## 版本迭代

当需要修改数据时：

1. **创建新版本目录**: `mkdir app/validators/support/data_packs/v2`
2. **复制所有文件**: `cp app/validators/support/data_packs/v1/* app/validators/support/data_packs/v2/`
3. **修改数据**: 在 v2 目录中修改需要更新的数据包
4. **切换版本**: 修改 `BaseValidator::DATA_PACK_VERSION = 'v2'`
5. **保留旧版本**: v1 目录保留，保持向后兼容

```ruby
# app/validators/base_validator.rb
class BaseValidator
  # 数据包版本（当前使用 v1）
  DATA_PACK_VERSION = 'v1'  # 修改这一行即可全局切换

  # ...
end
```

## 数据包规范

### 文件命名

- 格式：`<domain>.rb`
- 示例：`flights.rb`, `hotels.rb`, `trains.rb`
- domain：业务领域（flights, hotels, trains 等）

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
4. **数据关联正确**：确保外键关联正确（如依赖 base.rb 中的 City 数据）
5. **不使用显式 ID**：让数据库自动生成 ID，避免冲突
6. **数据量适中**：测试数据应足够但不过多，避免影响性能

## 设计优势

### 1. 降低维护成本

- ✅ 所有数据统一在 data_packs 管理
- ✅ 版本化命名，修改时创建新版本
- ✅ 无需在验证器中指定加载哪些数据包

### 2. 天然数据隔离

- ✅ 基于 `data_version` + RLS 实现隔离，无需手动清空/重载
- ✅ 每次验证使用独立的 `data_version`，并发验证互不干扰
- ✅ 验证后只删除当前版本记录，速度快，不影响基线数据

### 3. 自动化加载

- ✅ 应用启动时自动一次性全量加载所有数据包
- ✅ 新增数据包无需修改代码，重启后自动识别
- ✅ 验证器专注业务逻辑，无需关心数据加载

### 4. 可重复性

- ✅ 每次验证生成独立的 `data_version`
- ✅ 验证后回滚到基线，确保环境干净
- ✅ 验证器可安全重复执行

### 5. 性能优化

- ✅ 基线数据只加载一次，无需每次重载
- ✅ 回滚使用 `delete_all`（跳过回调），速度快
- ✅ RLS 过滤在数据库层完成，应用层透明

## 注意事项

1. **不要修改已发布的数据包**：创建新版本而非修改现有版本
2. **确保数据完整性**：外键关联必须正确（`base.rb` 优先加载）
3. **必须使用动态日期**：使用 `Date.current + N.days` 而不是固定日期
4. **测试数据真实性**：数据应接近真实场景
5. **不要在 db/seeds.rb 中添加数据**：所有数据统一在 data_packs 管理
6. **新增数据包无需配置**：创建文件后重启应用即可

## 常见问题

### Q: 为什么不再区分"基础数据"和"用户数据"？

A: rlbox 采用 `data_version` 隔离方案，所有数据包统一作为基线数据（`data_version='0'`）加载，无需区分。验证过程中用户产生的数据通过 `data_version` 自动打标，验证后精准清除，不影响基线。

### Q: 数据包是每次验证都重新加载吗？

A: 不是。数据包**只在应用启动时加载一次**（通过 initializer），之后的所有验证复用同一份基线数据。这与旧的"每次 prepare 都清空重载"方案不同。

### Q: 如何确认基线数据已加载？

```ruby
# 检查是否有 data_version='0' 的基线记录
City.unscoped.where(data_version: '0').count
```

### Q: 如何清空所有数据重新开始？

```bash
# 方式1: 重置数据库（会触发 initializer 重新加载）
rails db:reset

# 方式2: 手动清空（谨慎操作）
rails runner "ActiveRecord::Base.connection.execute('TRUNCATE TABLE cities, flights, bookings RESTART IDENTITY CASCADE')"
```

### Q: 并发验证会互相干扰吗？

A: 不会。每次验证生成独立的 `data_version`，RLS 策略确保不同会话只看到自己的数据。

### Q: 如何升级数据包版本？

1. 创建新版本目录：`mkdir app/validators/support/data_packs/v2`
2. 复制并修改数据包
3. 修改 `BaseValidator::DATA_PACK_VERSION = 'v2'`
4. 重启应用，新版本自动加载

## 相关文件

- `db/seeds.rb`: 空入口，提供使用说明
- `app/validators/support/data_packs/v1/base.rb`: 基础数据包（优先加载）
- `app/validators/support/data_packs/v1/*.rb`: 各业务数据包
- `config/initializers/validator_baseline.rb`: 应用启动时自动加载基线数据
- `app/validators/base_validator.rb`: `ensure_baseline_data_loaded`、`rollback_to_baseline` 等核心逻辑
- `app/validators/*_validator.rb`: 具体验证器实现
