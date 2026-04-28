---
topic: adr-005
updated_at: 2026-04-28
status: accepted
decision_date: 2026-04-28
related:
  - decisions/ADR-001-all-business-tables-have-data-version.md
  - decisions/ADR-002-data-packs-not-seeds.md
  - architecture/validator-system.md
  - architecture/data-version.md
  - conventions/validator-writing.md
---

# ADR-005 引入 `seed` 钩子承载"题目私有预制数据"

## Status
✅ **Accepted** — 2026-04-28

## Context

BaseValidator 原本只有三个方法：`prepare` / `verify` / `simulate`。执行顺序：

1. `execute_prepare` 生成 `@data_version`，`SET SESSION app.data_version`
2. 调子类 `prepare`（查 baseline，返回任务描述给 Agent）
3. Agent 操作，之后调 `execute_verify`
4. `verify` 跑断言，完毕后 `rollback_to_baseline`

这套设计假设 Agent 的**任务起点 = baseline**。但实际题目常常不是这样：

- 「把购物车里的矿泉水换成椰子水」→ 起点需要有一条购物车记录
- 「取消张三的未支付订单」→ 起点需要有一个未支付订单
- 「给最近买过某商品的用户发优惠券」→ 起点需要一条购买记录

原先开发者只有两个选择，都是**反模式**：

1. 在 `prepare` 里 `create!` → prepare 被定义为"只读 baseline 不写"，打破约定
2. 把数据塞进 `data_packs/v1/` baseline → 这些数据是**题目私有**的，塞进 baseline 会被所有其他题目看到，污染评测基准（ADR-002 禁止）

## Decision

在 `BaseValidator#execute_prepare` 生命周期里加一个**可选钩子** `seed`，执行位置：`SET SESSION` 之后、子类 `prepare` 之前。

```ruby
# app/validators/base_validator.rb
def execute_prepare
  @data_version = SecureRandom.hex(8)
  ActiveRecord::Base.connection.execute("SET SESSION app.data_version = '#{@data_version}'")

  seed if respond_to?(:seed)   # ← 新增

  @prepare_result = prepare
  # ...
end
```

**关键不变式**：

- `seed` 方法不是抽象必须（`respond_to?` 检查），大多数题目不用写
- 在 `SET SESSION` 之后执行 → 新建记录自动带 `@data_version`（由 `DataVersionable` 的 `before_create` 钩子处理）
- **不会污染 baseline**（`data_version='0'`）
- **不会跨 session 泄漏**（RLS policy 过滤）
- 在 `rollback_to_baseline` 时和 Agent 产生的数据一起被清理

## Consequences

### ✅ Pro

- `prepare` 语义更纯（只读 baseline 返 Hash），不再需要在里面 `create!`
- 题目私有数据有了正确位置，不会污染 `data_packs/v1/`
- 符合"baseline = 全局固定、`@data_version` = 本次会话"的数据二分

### ⚠️ Caveat

- `seed` 里**绝不**能用 `data_version: '0'`（会污染 baseline）—— `rake validator:lint` 会静态扫
- `seed` 里创建的数据量应控制在 O(1~10) 条，不要一次性 seed 几千条（会拖慢每次 `execute_prepare`）
- `seed` 和 `simulate` 的边界：
  - `seed` = "题目的前置条件"（Agent 做任务前世界的状态）
  - `simulate` = "模拟 Agent 正确操作"（自动化回归用）
- **引用 baseline 记录必须抽出 `load_refs` 私有方法**：
  `seed` 在 `prepare` 之前执行，如果把 `@user = User.find_by!(...)` 写在 `prepare` 里，`seed` 调用时 `@user` 还是 nil，`belongs_to` 校验会失败。正确写法：
  ```ruby
  def prepare
    load_refs
    { task: "把 #{@product.name} 加入购物车", hint: "..." }
  end

  def seed
    load_refs
    CartItem.create!(user: @user, product: @product, data_version: @data_version)
  end

  private

  # seed 在 prepare 之前执行 → baseline 引用要抽出供两者共用
  def load_refs
    return if @user  # memoize: 只查一次
    @user    = User.find_by!(email: 'demo@example.com', data_version: '0')
    @product = Product.find_by!(name: '...', data_version: '0')
  end
  ```
- **查关联时要显式 `where(data_version: '0')`**：
  `@user.addresses` 在 RLS 视图下既能看到 baseline 也能看到 `@data_version` 私有记录。正确：
  ```ruby
  @home_address = @user.addresses.where(data_version: '0').order(created_at: :desc).first
  ```

### 反例

```ruby
# ❌ 反例 1：seed 里写 '0' 污染 baseline
def seed
  CartItem.create!(user: @user, product: @item, data_version: '0')   # 禁止
end

# ❌ 反例 2：把 seed 该做的事塞进 prepare
def prepare
  CartItem.create!(user: @user, data_version: @data_version)   # ← 搬到 seed
  { task: '...' }
end

# ❌ 反例 3：把题目私有数据塞进 data_packs/v1/
# 会污染所有其他题目的 baseline，违反 ADR-002
```

## Alternatives Considered

### A. 在 `prepare` 里搞所有事情（放弃）

让 `prepare` 既能查又能写。拒绝原因：破坏"prepare = 只读"约定。

### B. 单独开 `setup` 方法（放弃）

命名候选还有 `setup` / `pre_task` / `fixture`。选 `seed` 原因：
- 动词性强，一看就知道是写数据
- 和 Rails 社区惯用的 `db/seeds.rb` 语义对齐
- `setup` 和 `prepare` 语义接近，易混淆

### C. 把 seed 功能做到 data_packs 里按 validator_id 命名空间（放弃）

仍然是 `data_version='0'`，对全局查询已经污染了，隔离要靠 `data_version` 列本身，绕不过去。

## Related

- [ADR-001](ADR-001-all-business-tables-have-data-version.md) — 所有业务表有 data_version 列
- [ADR-002](ADR-002-data-packs-not-seeds.md) — baseline 数据走 data_packs 而非 seeds
- [architecture/validator-system.md](../architecture/validator-system.md) — 生命周期图
- [conventions/validator-writing.md](../conventions/validator-writing.md) — seed 的写法规范

## Code Location

- `app/validators/base_validator.rb` — `execute_prepare` 里的 `seed if respond_to?(:seed)`
- `spec/validators/base_validator_seed_hook_spec.rb` — 钩子行为测试
