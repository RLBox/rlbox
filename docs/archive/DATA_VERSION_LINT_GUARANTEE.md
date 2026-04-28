> ⚠️ **Archived** — 此文件已被新 wiki 体系取代，仅保留作历史参考，勿模仿。

# 如何保证 data_version 过滤不被遗漏

## 问题背景

在多会话验证器系统中，**每个查询都必须包含 `data_version: @data_version` 过滤**，否则会导致：

1. **会话隔离失败** - 查询到其他会话的数据
2. **验证器误判** - 验证了别的会话创建的订单
3. **数据污染** - 多个会话的数据相互干扰

**实际案例：** v033 等 7 个租车验证器在 verify 方法中使用 `CarOrder.order(created_at: :desc).first`，没有 `data_version` 过滤，导致可能查询到其他会话的订单。

---

## 解决方案：自动化检测 + CI 集成

我们通过 **ValidatorLinter** 静态代码分析工具来自动检测这类问题。

---

## 1. ValidatorLinter 工作原理

### 检测逻辑

`ValidatorLinter#check_data_version` 方法会：

1. **提取 `verify` 方法内容** - 只检查 verify 方法（prepare 和 simulate 不检查）
2. **扫描业务模型查询** - 检测所有业务模型的查询调用（CarOrder, HotelBooking 等）
3. **检查查询链** - 提取完整的方法链（可能跨多行）
4. **验证 data_version** - 确保查询链中包含 `data_version: @data_version`

### 支持的查询模式

```ruby
# ✅ 检测以下查询模式
CarOrder.where(...)
CarOrder.find_by(...)
CarOrder.order(...)
CarOrder.all
CarOrder.first
CarOrder.last

# ✅ 支持跨多行的查询链
all_orders = CarOrder
  .where(data_version: @data_version)  # ✅ 检测到 data_version
  .order(created_at: :desc)
  .to_a
```

### 业务模型列表

目前检测以下业务模型（会话隔离必需）：

```ruby
# 订单类
CarOrder, HotelBooking, TrainBooking, TourGroupBooking, 
TicketOrder, ActivityOrder, BusTicketOrder, CharterBooking, 
DeepTravelBooking, CruiseOrder, HotelPackageOrder, 
InsuranceOrder, VisaOrder, InternetOrder, AbroadTicketOrder, 
MembershipOrder

# 产品类（如果在 verify 中查询）
Flight, Train, Hotel, Car, Ticket, Attraction, TourGroupProduct
```

---

## 2. 使用方法

### 2.1 检查所有验证器

```bash
rake validator:lint
```

**输出示例（发现问题）：**
```
🔍 Validator Lint Report
============================================================

❌ Found 1 issue(s):

🔴 HIGH Priority (1 issues):
------------------------------------------------------------

1. [HIGH] v033_rent_suv_beijing_validator (line 58)
  → CarOrder 查询缺少 data_version 过滤（verify 方法中）
  → 建议: 添加 .where(data_version: @data_version) 确保会话隔离
```

### 2.2 检查单个验证器

```bash
rake validator:lint_single[v033_rent_suv_beijing_validator]
```

**输出示例（通过）：**
```
[PASS] v033_rent_suv_beijing_validator passed all lint checks
```

---

## 3. CI 集成保证

### 3.1 在 rake validator:simulate 中自动运行

`rake validator:simulate` 在 **Step 0.5** 自动运行 `ValidatorLinter`：

```ruby
# lib/tasks/validator.rake
task simulate: :environment do
  # Step 0.5: Validator Lint (静态分析)
  puts "
" + "=" * 70
  puts "📝 Step 0.5: Validator Lint (静态分析)"
  puts "=" * 70
  
  linter = ValidatorLinter.new
  issues = linter.lint_all
  
  if issues.any?
    linter.report(issues)
    
    # 如果有 HIGH 级别问题，直接退出
    high_issues = issues.select { |i| i.severity == 'HIGH' }
    if high_issues.any?
      puts "
❌ 发现 #{high_issues.size} 个 HIGH 级别问题，请修复后再运行验证器"
      exit 1
    end
  end
  
  # 继续执行 Step 1, 2, 3...
end
```

### 3.2 严格模式配置

`config/validator_lint_rules.yml`:

```yaml
strict_mode:
  enabled: true
  fail_on_high_severity: true      # HIGH 级别问题直接失败
  fail_on_medium_severity: false   # MEDIUM 级别问题不失败（警告）
  fail_on_low_severity: false      # LOW 级别问题不失败
```

**关键点：**
- **HIGH 级别问题（含 data_version）会阻止 `rake validator:simulate` 执行**
- 必须修复后才能继续运行验证器
- 从源头保证代码质量

---

## 4. 正确模式 vs 错误模式

### ❌ 错误模式 1：没有 data_version 过滤

```ruby
def verify
  add_assertion "订单已创建", weight: 20 do
    @order = CarOrder.order(created_at: :desc).first  # ❌ 没有 data_version
    expect(@order).not_to be_nil
  end
end
```

**检测结果：**
```
[HIGH] CarOrder 查询缺少 data_version 过滤（verify 方法中）
→ 建议: 添加 .where(data_version: @data_version) 确保会话隔离
```

---

### ❌ 错误模式 2：where 中没有 data_version

```ruby
def verify
  add_assertion "订单已创建", weight: 20 do
    @order = CarOrder
      .where(car_id: @car.id)  # ❌ 缺少 data_version: @data_version
      .order(created_at: :desc)
      .first
    expect(@order).not_to be_nil
  end
end
```

**检测结果：**
```
[HIGH] CarOrder 查询缺少 data_version 过滤（verify 方法中）
→ 建议: 添加 .where(data_version: @data_version) 确保会话隔离
```

---

### ✅ 正确模式 1：独立的 where(data_version: @data_version)

```ruby
def verify
  add_assertion "订单已创建", weight: 20 do
    all_orders = CarOrder
      .where(data_version: @data_version)  # ✅ 包含 data_version
      .order(created_at: :desc)
      .to_a
    
    expect(all_orders).not_to be_empty
    @order = all_orders.first
  end
end
```

---

### ✅ 正确模式 2：where 参数中包含 data_version

```ruby
def verify
  add_assertion "订单已创建", weight: 20 do
    @order = CarOrder
      .where(car_id: @car.id, data_version: @data_version)  # ✅ 包含
      .order(created_at: :desc)
      .first
    expect(@order).not_to be_nil
  end
end
```

---

### ✅ 正确模式 3：joins + where 中包含 data_version

```ruby
def verify
  add_assertion "创建了门票订单", weight: 20 do
    all_orders = TicketOrder
      .joins(ticket: :attraction)
      .includes(:ticket)
      .where(tickets: { attractions: { name: @attraction_name } })
      .where(data_version: @data_version)  # ✅ 包含
      .order(created_at: :desc)
      .to_a
    
    expect(all_orders).not_to be_empty
  end
end
```

---

## 5. 特殊情况处理

### 5.1 系统表不需要 data_version

以下模型不需要 `data_version` 过滤（系统表）：

- `Administrator` - 管理员表
- `Session` - 用户会话表
- `AdminOplog` - 管理员操作日志
- `ValidatorExecution` - 验证器执行记录
- `ActiveStorage::*` - 文件存储表

**Linter 会自动跳过这些表。**

---

### 5.2 prepare 和 simulate 方法

**Linter 只检查 `verify` 方法，不检查 `prepare` 和 `simulate` 方法。**

**原因：**
- `prepare` 方法查询 `data_version: 0` 的基础数据（正确）
- `simulate` 方法创建 `data_version: @data_version` 的测试数据（正确）
- 只有 `verify` 方法需要确保查询当前会话的数据

---

## 6. 工作流程保证

### 6.1 开发阶段

**创建新验证器时：**
```bash
# 1. 创建验证器
rails generate validator book_hotel "预订酒店" "用户需要预订..."

# 2. 实现 prepare, verify, simulate 方法
vim app/validators/v001_v050/v123_book_hotel_validator.rb

# 3. 运行 lint 检查（自动在 simulate 中执行）
rake validator:simulate_single[v123_book_hotel_validator]

# 如果有 HIGH 级别问题，会在 Step 0.5 阻止执行：
# ❌ 发现 1 个 HIGH 级别问题，请修复后再运行验证器
```

---

### 6.2 修复现有验证器

**批量检查所有验证器：**
```bash
rake validator:lint
```

**修复特定验证器：**
```bash
# 1. 查看具体问题
rake validator:lint_single[v033_rent_suv_beijing_validator]

# 2. 修复代码
vim app/validators/v001_v050/v033_rent_suv_beijing_validator.rb

# 3. 重新检查
rake validator:lint_single[v033_rent_suv_beijing_validator]

# 4. 运行验证器测试
rake validator:simulate_single[v033_rent_suv_beijing_validator]
```

---

### 6.3 CI/CD 集成

**GitHub Actions / GitLab CI 配置示例：**

```yaml
# .github/workflows/validator_lint.yml
name: Validator Lint

on:
  pull_request:
    paths:
      - 'app/validators/**'

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Setup Rails
        run: bundle install
      - name: Run Validator Lint
        run: rake validator:lint
```

**效果：**
- 每次 PR 修改验证器时自动运行 lint
- 如果有 HIGH 级别问题，CI 会失败
- 强制修复后才能合并代码

---

## 7. 常见问题 FAQ

### Q1: 为什么 prepare 方法中的查询没有报错？

**A:** `ValidatorLinter` 只检查 `verify` 方法。`prepare` 方法查询 `data_version: 0` 的基础数据是正确的，不需要检查。

---

### Q2: 如果我确实需要查询 data_version: 0 的数据怎么办？

**A:** 在 `verify` 方法中，如果需要查询基础数据（如 User, Attraction），显式添加 `data_version: 0`：

```ruby
def verify
  # ✅ 显式查询基础数据
  user = User.find_by(email: 'demo@travel01.com', data_version: 0)
  
  # ✅ 查询当前会话的订单
  all_orders = TicketOrder
    .where(user_id: user.id, data_version: @data_version)
    .order(created_at: :desc)
    .to_a
end
```

**Linter 不会误报，因为显式指定了 `data_version`。**

---

### Q3: 我的查询跨多行，Linter 能检测吗？

**A:** 能。`ValidatorLinter` 会提取完整的查询链（跨多行）：

```ruby
# ✅ Linter 能正确检测跨多行查询
all_orders = TicketOrder
  .joins(ticket: :attraction)
  .includes(:ticket)
  .where(tickets: { attractions: { name: @attraction_name } })
  .where(data_version: @data_version)  # ← Linter 能找到这一行
  .order(created_at: :desc)
  .to_a
```

---

### Q4: 如何添加新的业务模型到检测列表？

**A:** 编辑 `lib/validator_linter.rb` 中的 `business_models` 数组：

```ruby
def check_data_version(validator_name, content, file_path)
  # ...
  
  business_models = %w[
    CarOrder HotelBooking TrainBooking
    YourNewModel  # ← 添加新模型
  ]
  
  # ...
end
```

---

## 8. 总结

### 多层保证机制

| 保证层级 | 机制 | 效果 |
|---------|------|------|
| **开发时** | `rake validator:simulate_single` 自动运行 lint | 立即发现问题 |
| **批量检查** | `rake validator:lint` 扫描所有验证器 | 排查历史遗留问题 |
| **CI 集成** | GitHub Actions / GitLab CI 自动检查 | 代码合并前强制检查 |
| **严格模式** | HIGH 级别问题直接阻止执行 | 从源头防止问题 |

### 关键命令

```bash
# 检查所有验证器
rake validator:lint

# 检查单个验证器
rake validator:lint_single[v033_rent_suv_beijing_validator]

# 显示配置和规则
rake validator:lint_config

# 导出问题到 JSON
rake validator:lint_export[issues.json]
```

### 修复流程

1. **发现问题** - `rake validator:lint` 或 CI 自动检测
2. **查看详情** - 查看行号和错误消息
3. **修复代码** - 添加 `.where(data_version: @data_version)`
4. **验证修复** - `rake validator:lint_single[validator_id]`
5. **测试运行** - `rake validator:simulate_single[validator_id]`

---

## 相关文档

- **多会话实现原理：** `docs/MULTI_SESSION_IMPLEMENTATION.md`
- **Validator Lint 实现文档：** `docs/VALIDATOR_LINT_IMPLEMENTATION.md`
- **租车验证器修复案例：** `docs/CAR_VALIDATOR_DATA_VERSION_FIX.md`
- **Validator 设计规范：** `docs/VALIDATOR_DESIGN.md`

---

**最后更新：** 2026-02-08

**修复统计：** 本次修复发现并解决了 7 个租车验证器的 `data_version` 过滤缺失问题，所有验证器现已通过 lint 检查。
