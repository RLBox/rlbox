---
topic: adr-006
updated_at: 2026-04-28
status: accepted
decision_date: 2026-04-28
supersedes: none
related:
  - decisions/ADR-001-all-business-tables-have-data-version.md
  - architecture/validator-system.md
  - conventions/validator-writing.md
---

# ADR-006 Validators 挂到命名空间根，避免与业务模型撞车

## Status
✅ **Accepted** — 2026-04-28

## Context

`app/validators/` 下按业务子域分子目录，每个子目录放 `v001_xxx_validator.rb`、`v002_xxx_validator.rb` 等文件。

**冲突点：** Rails 已有业务模型（如 `app/models/order.rb` 定义顶层 `class Order < ApplicationRecord`）。如果 Zeitwerk 走默认规则（文件路径 → 命名空间常量），则：

```
app/models/order.rb                          → class Order
app/validators/order/v001_foo_validator.rb   → module Order; class V001Foo; end; end
```

Ruby 底层限制：**同一个常量要么是 class 要么是 module，不能兼任**。Zeitwerk 加载时会抛：

```
TypeError: Order is not a module
/app/models/order.rb:1: previous definition of Order was here
/app/validators/order/v001_foo_validator.rb:1
```

这是 Ruby 常量语义的硬限制，Zeitwerk 绕不过去。

### 前期错误方案（已废弃）

使用 `Rails.autoloaders.main.collapse(dir)` hack 让子目录"塌陷"：

```ruby
Dir[Rails.root.join('app/validators/*')].select { |p| File.directory?(p) }.each do |dir|
  next if dir.end_with?('/support')
  Rails.autoloaders.main.collapse(dir)
end
```

效果：`app/validators/order/v001_foo.rb` 定义 `V001Foo`（顶层），不是 `Order::V001Foo`。代价：

1. **反 Zeitwerk 默认约定**，新来的 contributor 一脸懵
2. 顶层常量海，无命名空间隔离
3. 控制器里必须写"路径拼常量"的特殊代码
4. 未来新加子目录只要名字撞模型就要重复这场噩梦

## Decision

用 **Zeitwerk 官方 API**：`push_dir(..., namespace:)`，把 `app/validators/` 整个挂到专属命名空间 `Validators` 下。

```ruby
# config/application.rb
module ::Validators; end unless defined?(::Validators)
Rails.autoloaders.main.ignore(Rails.root.join('app/validators/support'))
Rails.autoloaders.main.push_dir(
  Rails.root.join('app/validators'),
  namespace: ::Validators
)
```

映射关系：

| 文件路径 | 期望常量名 |
|---|---|
| `app/validators/base_validator.rb` | `Validators::BaseValidator` |
| `app/validators/order/v001_cancel_order_validator.rb` | `Validators::Order::V001CancelOrderValidator` |
| `app/validators/cart/v001_add_to_cart_validator.rb` | `Validators::Cart::V001AddToCartValidator` |

**关键点：** `Validators::Order` 是全新的 **Module**，和顶层 `Order` AR Class 在 Ruby 常量表里完全不相关，永不冲突。

```ruby
Order.class             # => Class (AR 模型)
Validators::Order.class # => Module
```

## Consequences

### 👍 正向
1. **完全遵循 Rails/Zeitwerk 官方 API**（`push_dir namespace:` 不是 hack）
2. 顶层业务模型不会被 validator 目录"污染"，未来新增子目录零配置
3. Validator 类名自带目录分组，可读性强
4. 控制器里"路径 → 常量名"推导是标准 `"Validators::" + path.camelize`，无 tribal knowledge

### 👎 代价
1. 所有 validator 类声明改为 `class Validators::Subdir::VxxxFooValidator < Validators::BaseValidator`
2. `base_validator.rb` 的类名改成 `Validators::BaseValidator`
3. 控制器、spec 里的 `BaseValidator` 引用改为 `Validators::BaseValidator`

> 一次性改动，存量不多时用脚本批量跑完。

## 约束 / 反例

### ❌ 新加 validator 忘了命名空间前缀
```ruby
# ❌ app/validators/order/v003_new_task_validator.rb
class V003NewTaskValidator < BaseValidator   # Zeitwerk 期望 Validators::Order::V003...
```

### ✅ 正例
```ruby
# app/validators/order/v003_new_task_validator.rb
class Validators::Order::V003NewTaskValidator < Validators::BaseValidator
  # ...
end
```

### 命名公式
```
app/validators/<subdir>/<file>.rb
         ↓
Validators::<Subdir.camelize>::<File.basename(f, '.rb').camelize>
```

## References
- [Zeitwerk README §namespaces](https://github.com/fxn/zeitwerk#namespaces)
- `config/application.rb` — push_dir 配置位置
