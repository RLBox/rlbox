# Validator Simulation Tests

## 目的

在项目功能变更后，自动验证所有 Validator 是否仍然有效。

## 运行方式

```bash
# 重置基线数据（每天开始工作时运行）
rake validator:reset_baseline

# 运行所有 Validator 的模拟测试
rake validator:simulate

# 运行单个 Validator 的模拟测试
rake validator:simulate_single[book_flight_sz_to_bj]
```

## ⚠️ 重要：数据重置

### 为什么需要重置数据？

数据包中的航班日期使用 `Date.current + 3.days` 生成。在本地开发环境中：

- **问题**: 数据包初始化时间和测试运行时间可能不是同一天
- **结果**: 航班日期不匹配，导致查询失败
- **解决方案**: 每天开始工作时运行 `rake validator:reset_baseline`

### 什么时候运行 reset_baseline？

1. **每天开始工作时** - 确保数据包日期与当前日期同步
2. **数据包文件更新后** - 重新加载最新的数据结构
3. **测试失败且怀疑日期问题时** - 排查日期不匹配的问题

### 重置过程

```bash
rake validator:reset_baseline
```

该命令会：
1. 删除所有 `data_version=0` 的基线数据
2. 重新加载 `app/validators/support/data_packs/v1/` 中的所有数据包
3. 验证数据加载是否成功
4. 显示当前日期和航班日期

**注意**: 生产环境的时间是写死的，不存在此问题。此功能仅用于本地开发环境。

## 实现规范

每个 Validator 必须实现 `simulate` 方法：

- 使用数据包中已有的测试用户（demo@travel01.com）
- 使用固定的查询和操作
- 不包含复杂业务逻辑
- 操作结果应该让 `verify` 通过

## 数据包依赖

所有 Validator 依赖 `app/validators/support/data_packs/v1/` 中的数据包。

### 测试用户信息

- **邮箱**: demo@travel01.com
- **密码**: password123
- **支付密码**: 222222
- **默认乘客**: 张三（身份证: 110101199001011234, 电话: 13800138000）

## 示例：BookFlightValidator

```ruby
def simulate
  # 1. 查找测试用户
  user = User.find_by!(email: 'demo@travel01.com')
  
  # 2. 查找乘客
  passenger = Passenger.find_by!(user: user, name: '张三')
  
  # 3. 查找目标航班（数据包固定）
  target_flight = Flight.where(
    departure_city: @origin,
    destination_city: @destination,
    flight_date: @target_date
  ).order(:price).first
  
  # 4. 创建订单
  booking = Booking.create!(
    flight_id: target_flight.id,
    passenger_id: passenger.id,
    user_id: user.id,
    total_price: target_flight.price,
    status: 'pending'
  )
  
  # 5. 返回操作信息
  {
    action: 'create_booking',
    booking_id: booking.id,
    flight_number: target_flight.flight_number
  }
end
```

## 测试流程

1. **prepare**: 准备测试环境，设置 data_version
2. **simulate**: 模拟 AI Agent 操作，创建测试数据
3. **verify**: 验证操作结果是否符合预期
4. **rollback**: 清理测试数据，恢复到基线状态

## 注意事项

- `simulate` 中的操作应该是确定性的（数据包固定 → 结果固定）
- 不要在 `simulate` 中写复杂的搜索和比较逻辑
- 所有操作应该使用数据包中已有的数据
- 测试完成后会自动清理数据，不影响其他测试
