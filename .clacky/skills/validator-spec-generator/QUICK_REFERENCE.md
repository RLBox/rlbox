# Validator Generator 快速参考（Goomart 电商版）

## 命令格式

```
生成 validator: [任务描述], 模块 [module_name], 编号 [number]
```

- **任务描述**（必需）：用自然语言描述 Agent 要完成的任务
- **模块名**（可选）：业务模块，默认 `common`
- **编号**（可选）：手动指定，默认按模块自动分配

## 命名规则速查

**核心**：类名 = **文件名 Pascal 化**，不含目录名。

| 项 | 格式 | 示例 |
|---|---|---|
| 目录 | `{module}/`（已 Zeitwerk collapse） | `order/` |
| 文件名 | `v{NNN}_{brief_name}_validator.rb` | `v002_reorder_previous_validator.rb` |
| 类名 | `File.basename(f, '.rb').split('_').map(&:capitalize).join` | `V002ReorderPreviousValidator` |
| validator_id | 与文件名（去 `.rb`）一致 | `v002_reorder_previous_validator` |
| 编号 | 三位数字（模块内递增） | `001`, `002`, `003` |

⚠️ 不要把目录名塞进类名（会 `Zeitwerk::NameError`）：
- ❌ `V002OrderReorderPreviousValidator`
- ❌ `Order::V002ReorderPreviousValidator`（collapse 掉了命名空间）

## Goomart 业务模块表

| 模块 | 用途 | 典型任务 |
|---|---|---|
| `common` | 通用 / 跨模块 | 购物车+支付复合任务；默认兜底 |
| `order` | 下单、支付、订单状态、取消 | "给张三下单购 2 斤苹果" / "取消订单" |
| `catalog` | 商品浏览、分类、搜索、详情 | "浏览水果分类找最便宜苹果" / "搜索鸡蛋最低价" |
| `cart` | 购物车增删改 | "给张三加购 2 斤苹果" / "把酸奶改 3 盒" |
| `checkout` | 结算、地址选择、备注、运费 | "用非默认地址结算" / "备注配送时间窗口" |
| `account` | 账号资料、收货地址管理、支付密码 | "添加收货地址" / "修改昵称" / "重置支付密码" |

## 快速示例

### 1. 最简单（自动分模块 + 自动编号）
```
生成 validator：创建一个标题为 "Hello World" 的帖子
```
→ `common/v001_common_validator.rb`（没匹配到具体模块，兜底 `common`）

### 2. 指定模块
```
生成 validator：给张三下单购买 2 斤有机苹果，模块 order
```
→ `order/v001_order_validator.rb`

### 3. 指定模块 + 编号
```
生成 validator：给张三加购酸奶 3 盒，模块 cart，编号 005
```
→ `cart/v005_cart_validator.rb`

### 4. 编号冲突自动递增
```
生成 validator：删除购物车商品，模块 cart，编号 003
```
如果 `cart/v003_cart_validator.rb` 已存在 → 自动递增到 `004`，输出：
> ⚠️ 编号 003 已存在，已自动递增到 004

## 文件骨架（详见 TEMPLATE_GOOMART.rb）

```ruby
# frozen_string_literal: true

require_relative '../base_validator'

class V001OrderValidator < BaseValidator
  self.validator_id   = 'v001_order_validator'
  self.task_id        = '固定-UUID'
  self.title          = '给张三下单购买 2 斤有机苹果'
  self.timeout_seconds = 180

  # def seed  # 可选：题目私有预制数据
  # end

  def prepare
    @user    = User.find_by!(email: 'demo@rlbox.ai', data_version: '0')
    @product = Product.find_by!(name: '有机苹果', data_version: '0')
    { task: '请给张三下单购买 2 斤有机苹果', hint: '...' }
  end

  def verify
    add_assertion '订单已创建', weight: 40 do
      @order = Order.where(user: @user, data_version: @data_version)
                    .order(created_at: :desc).first
      expect(@order).not_to be_nil
    end
    return if @order.nil?

    add_assertion '数量为 2', weight: 30 do
      item = @order.order_items.find_by(product: @product)
      expect(item&.quantity).to eq(2), "预期 2，实际 #{item&.quantity.inspect}"
    end

    add_assertion '订单状态为 pending', weight: 30 do
      expect(@order.status).to eq('pending')
    end
  end

  def simulate
    order = Order.create!(user: @user, status: 'pending',
                          total_price: @product.price * 2,
                          data_version: @data_version)
    order.order_items.create!(product: @product, quantity: 2,
                              unit_price: @product.price,
                              data_version: @data_version)
  end
end
```

## 关键要点

### ✅ DO
- `data_version` 永远是**字符串**（`'0'`，不是整数 `0`）
- `simulate` 和 `seed` 里 `create!` 必带 `data_version: @data_version`
- `verify` 查询必带 `data_version: @data_version`
- where 只锁 scope，断言放 `add_assertion` 块内
- 关键实体后面跟 `return if xxx.nil?` Guard clause
- 权重总和 = 100
- 错误消息具体（期望值 + 实际值）
- 测试用户：`demo@rlbox.ai`（密码 `password123` / 支付密码 `123456`）
- **有 seed 钩子时**：baseline 引用抽到 `load_refs` 私有方法，seed 和 prepare 各调一次（`return if @user` memoize）
- **查"自己的" addresses / cart_items**：显式 `where(data_version: '0')` 避免 RLS 把 seed 私有数据查进来
- **断言布尔**：用 `be_truthy` / `eq(true)`
- **生成前 pre-flight**：`bundle exec rails runner "puts Product.columns.map(&:name).join(', ')"` 验字段真存在

### ❌ DON'T
- 不在 `simulate` / `seed` 里写 `data_version: '0'`（污染 baseline）
- 不在业务表上用 `data_version_excluded!` / `unscope(default_scope)` / `skip_callback`（ADR-001 红线）
- 不手动 `SET SESSION app.data_version`（`base_validator` 已处理）
- 不用 `SecureRandom.uuid` 作为 `task_id` 的值（每次加载都变）
- 不在 `prepare` 里 `create!`（该去 `seed` / `simulate`）
- 不用整数 `data_version: 0`
- **不要用 `be_true` / `be_false`**（RSpec 3 已删，会被当 predicate matcher 爆 NoMethodError）
- **seed 里不要引用 @user 之类的实例变量**，除非已经调了 `load_refs`（seed 在 prepare 之前执行）
- **类名不要塞目录名**：`order/v002_reorder_previous_validator.rb` → `V002ReorderPreviousValidator`，**不是** `V002OrderReorderPreviousValidator`

## 目录结构

```
app/validators/
  ├── base_validator.rb
  ├── support/data_packs/v1/       ← baseline（不归 skill 管）
  ├── common/
  ├── order/
  ├── catalog/
  ├── cart/
  ├── checkout/
  └── account/
```

## 编号管理 API

```ruby
require_relative 'validator_number_helper'
helper = ValidatorNumberHelper.new

# 自动分配下一个编号
helper.find_next_number('order')         # => "003"

# 检查是否存在
helper.number_exists?('order', '001')    # => true

# 请求指定编号，冲突自动递增
helper.get_available_number('order', '003')
# => { number: "004", conflict: true, message: "⚠️ 编号 003 已存在，已自动递增到 004" }
```

## 交付前 Checklist

- [ ] `bundle exec rake validator:lint` 通过
- [ ] `bundle exec rails runner "V001OrderValidator.new.execute_simulate"` 返回 `status: passed`
- [ ] 文件路径正确（`app/validators/{module}/v{NNN}_{module}_validator.rb`）
- [ ] 类名与 `validator_id` 对应
- [ ] `task_id` 是固定 UUID（不是 `SecureRandom.uuid` 字面量）
- [ ] 权重总和 = 100

## 权威文档

- `docs/conventions/validator-writing.md` — 编写规范（必读）
- `docs/architecture/data-version.md` — data_version 语义
- `docs/architecture/validator-system.md` — 生命周期
- `docs/decisions/ADR-001-all-business-tables-have-data-version.md` — 业务表红线
