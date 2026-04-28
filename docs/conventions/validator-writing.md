---
topic: validator-writing
updated_at: 2026-04-28
allow_legacy_models_for_contrast: true
supersedes: ../archive/VALIDATOR_WRITING_STANDARDS.md
related:
  - architecture/data-version.md
  - architecture/validator-system.md
  - decisions/INDEX.md
---

# ✍️ Validator 编写标准

> **本文替换** `docs/archive/VALIDATOR_WRITING_STANDARDS.md`（旧文例子都是旅行项目残留）。

## 1. 题目（title + description）

格式：`给/帮 [受益人] + 动词 + 核心目标 + （关键约束）`

**✅ Good**
- `给张三加购 2 斤有机苹果`
- `帮张三下单凑满减（订单满 199 减 20，选最便宜的零食）`
- `给张三把购物车里的某商品改成 3 盒`

**❌ Bad**
- `CartItem.create(user_id: 1, product_id: 2, quantity: 2)` ← 像代码
- `在 /cart 页面点击 + 按钮两次` ← 像操作手册
- `订单 id=5 的 status 改成 paid` ← 暴露内部字段

## 2. prepare 方法（查 baseline，不写）

```ruby
def prepare
  @user    = User.find_by!(email: 'demo@example.com', data_version: '0')
  @product = Product.find_by!(name: '有机苹果', data_version: '0')
  { task: "给#{@user.name}加购2份#{@product.name}", hint: '...' }
end
```

**禁止**：
- ❌ 在 prepare 里 `create!`（属于 simulate 阶段）
- ❌ 漏 `data_version: '0'`（可能跨会话误读）

## 3. seed 方法（题目私有预制数据，可选）

如果题目**不是**从干净 baseline 开始，用 `seed` 方法预置会话私有数据。

**⚠️ 关键顺序**：`seed` 在 `prepare` 之**前**执行。如果 seed 和 prepare 都需要同一批 baseline 引用，抽出 `load_refs` 方法供两者共用：

```ruby
def seed
  load_refs
  CartItem.create!(
    user: @user, product: @product, quantity: 1,
    data_version: @data_version   # ← 必须用 @data_version，绝不 '0'
  )
end

def prepare
  load_refs
  { task: "把购物车里的#{@product.name}改成3盒", hint: '...' }
end

private

def load_refs
  return if @user
  @user    = User.find_by!(email: 'demo@example.com', data_version: '0')
  @product = Product.find_by!(name: '有机苹果', data_version: '0')
end
```

**关键规则**：
1. seed 里 `create!` 必须显式写 `data_version: @data_version`，**不要写 `'0'`**
2. 查 baseline 记录时必须带 `data_version: '0'`
3. 查关联（如 `@user.addresses`）时也要加 `.where(data_version: '0')`，否则可能拿到私有数据

## 4. simulate 方法（模拟 Agent 动作）

```ruby
def simulate
  CartItem.create!(
    user: @user, product: @product, quantity: 2,
    data_version: @data_version   # ← 绝不用 '0'
  )
end
```

## 5. verify 方法（断言）

### 5.1 查询必须过滤 data_version

```ruby
# ✅ GOOD
items = CartItem
  .where(user: @user, data_version: @data_version)
  .order(created_at: :desc).to_a

# ❌ BAD — 漏 data_version，可能读到其他会话数据
items = CartItem.where(user: @user).to_a
```

`rake validator:lint` 会静态检测遗漏。

### 5.2 过滤 vs 断言分离

```ruby
# ❌ 把要断言的属性塞进 where，结果只能判"有/无"
items = CartItem.where(product: @product, quantity: 2, data_version: @data_version)

# ✅ where 只锁定 scope，断言独立
items = CartItem.where(product: @product, data_version: @data_version).to_a
add_assertion "数量为 2", weight: 15 do
  items.each { |i| expect(i.quantity).to eq(2), "预期 2，实际 #{i.quantity}" }
end
```

### 5.3 Guard clause（必须）

```ruby
add_assertion "购物车不为空", weight: 25 do
  @items = CartItem.where(user: @user, data_version: @data_version).to_a
  expect(@items).not_to be_empty, "购物车空了"
end

return if @items.nil? || @items.empty?  # ← 必须，否则后面断言会 NPE

add_assertion "商品正确", weight: 15 do
  expect(@items.map(&:product_id)).to include(@product.id)
end
```

### 5.4 Assertion 权重分布（总和 = 100）

| 类别 | 权重 |
|---|---|
| 存在性 + 数量 | 20–25 |
| 核心实体对 | 10–15 |
| 单属性 | 10–15 each |
| 业务逻辑（复合判断） | 20–30 |

### 5.5 错误信息必须具体

```ruby
# ✅
expect(item.quantity).to eq(2), "数量错。预期: 2, 实际: #{item.quantity}"
# ❌
expect(item.quantity).to eq(2), "错了"
```

## 6. 跨请求隔离：verify 必须独立工作（ADR-007 硬规则）

生产环境中，`prepare` 和 `verify` 是**两次独立 HTTP 请求**，内存不共享。在 `prepare` 里设置的 `@user` 在 `verify` 开始时是 **nil**。

### 正确姿势

**方式 B（推荐）：verify 里独立重查**

```ruby
def verify
  # verify 是新实例，@user 是 nil——按 baseline 重查
  user    = User.find_by!(email: 'demo@example.com', data_version: '0')
  product = Product.find_by!(name: '有机苹果', data_version: '0')
  add_assertion '加购成功', weight: 40 do
    expect(CartItem.where(user: user, product: product, data_version: @data_version)).to exist
  end
end
```

**方式 C（用了 seed 时推荐）：`load_refs` 模式**

verify 阶段调 `load_refs`，内部 `return if @user` 做 memoize，新实例第一次调会真查 baseline。

```ruby
def verify
  load_refs   # verify 新实例下会真的查一次 baseline
  add_assertion '操作成功', weight: 40 do
    expect(Order.where(user: @user, data_version: @data_version)).to exist
  end
end
```

### 自查问题

写完 validator 前问自己：**verify 里用到的每个 `@xxx`，在 verify 阶段新建实例只有 `@data_version` 的前提下，能否正常取到？**

## 7. 目录 & 命名约定（ADR-006）

```
app/validators/
├── base_validator.rb           → Validators::BaseValidator
├── cart/
│   └── v001_add_to_cart_validator.rb  → Validators::Cart::V001AddToCartValidator
└── order/
    └── v001_place_order_validator.rb  → Validators::Order::V001PlaceOrderValidator
```

**为什么用 `Validators::` 命名空间？**
不加命名空间，`app/validators/order/` 会挂在 `Order::` 下，与 `app/models/order.rb` 里的 `class Order` 撞车（`TypeError: Order is not a module`）。详见 ADR-006（派生项目 docs/decisions/ 目录）。

```ruby
# ✅ 正确写法
class Validators::Order::V001PlaceOrderValidator < Validators::BaseValidator
  self.validator_id = 'order_v001_place_order'
end
```

## 8. 常见错误速查

| 错误 | 后果 | 规避 |
|---|---|---|
| simulate/seed 里用 `data_version: '0'` | 污染 baseline | lint |
| verify 漏 `data_version` | 误判其他会话 | `rake validator:lint` |
| 把属性塞进 where | 细粒度 score 丢失 | where 只锁 scope |
| 无 guard clause | NPE | 存在性断言后立即 guard |
| 权重总和 ≠ 100 | 评分异常 | lint |
| verify 用 `@user` 等 prepare 设置的 ivar | 生产环境 nil | 见 §6 跨请求隔离 |
| `expect(x).to be_true` | RSpec 3 移除了此 matcher | 用 `be_truthy` / `eq(true)` |
| 类名 ≠ 文件名（Pascal） | Zeitwerk::NameError | 见 §7 命名约定 |

## 9. 延伸阅读
- [architecture/validator-system.md](../architecture/validator-system.md) — 框架设计（生命周期、数据隔离）
- [architecture/validator-linter.md](../architecture/validator-linter.md) — Linter 实现
- [decisions/INDEX.md](../decisions/INDEX.md) — ADR 总览（ADR-005/006/007 在派生项目各自的 decisions/ 目录中）
