---
topic: validator-system
updated_at: 2026-04-28
allow_legacy_models_for_contrast: true
related:
  - agent-sandbox.md
  - data-version.md
  - data-packs.md
  - multi-session.md
  - validator-linter.md
  - ../conventions/validator-writing.md
supersedes: ../archive/VALIDATOR_DESIGN.md
source_files:
  - app/validators/base_validator.rb
  - app/models/concerns/data_versionable.rb
  - app/models/validator_execution.rb
---

# 验证器系统（Validator System）

> Agent Benchmark 的引擎。每个 Task 一个 validator 子类；`prepare` 给出题面 + 设 data_version，Agent 操作完后 `verify` 打分。所有业务数据天然隔离、可回滚。

---

## 1. 它是什么，为什么需要

验证器系统是 Agent 评测沙盒的**执行引擎**：

- **人类出题**：写一个 `BaseValidator` 子类，定义 `prepare`（给 Agent 看的任务描述）、`verify`（客观断言 Agent 的结果）、`simulate`（自动化回归用，模拟一个完美 Agent）
- **Agent 答题**：通过 API 或 UI 拿到 prepare 信息 → 操作业务系统（增删改各业务表）
- **自动打分**：verify 基于断言权重（`add_assertion "xxx", weight: 60`）计算 0-100 分
- **自动清理**：同一 session 的所有改动一键回滚，不污染下次测试

---

## 2. 核心机制：RLS + data_version

### 2.1 数据如何隔离

1. **基线数据**（`data_version = '0'`）由 `data_packs/v1/` 加载，全局共享、只读。
2. **每个验证器 session** 在 `execute_prepare` 时生成唯一 16 位十六进制字符串（`SecureRandom.hex(8)`），写入 PostgreSQL 会话变量 `app.data_version`。
3. **所有业务表都有 RLS 策略**：只返回 `data_version = '0'` + `data_version = current_setting('app.data_version')` 的行。
4. **所有业务模型 include DataVersionable**：`before_create` 钩子自动把新记录的 `data_version` 填成当前 session 值。

### 2.2 生命周期

```
┌───────────────────── 1 次 Agent 任务 ─────────────────────┐

  execute_prepare
     │ ① SecureRandom.hex(8) → @data_version (e.g. "a3f9...")
     │ ② SET SESSION app.data_version = 'a3f9...'
     │ ③ 调用子类 seed（可选）—— 创建题目私有的预制数据
     │ ④ 调用子类 prepare，拿到 {task, hint, …}
     │ ⑤ 把 @data_version 和 instance 状态存到 validator_executions 表
     ▼
  Agent 操作期间
     │ 所有 insert/update 自动带 data_version='a3f9...'
     │ 所有 select 只看到 baseline + 'a3f9...'
     ▼
  execute_verify(cleanup: true)
     │ ① 从 validator_executions 恢复 @data_version
     │ ② SET SESSION app.data_version = 'a3f9...'
     │ ③ 调用子类 verify，累加断言
     │ ④ rollback_to_baseline —— DELETE WHERE data_version='a3f9...'
     ▼
  基线重新干净

└─────────────────────────────────────────────────────────────┘
```

代码位置：`app/validators/base_validator.rb`。

#### `seed` 钩子：题目私有的预制数据（ADR-005）

有些任务的起点并不是"干净的 baseline"，而是"假设用户已经做了若干操作"。例如：
- "把购物车里的某商品换成另一个" → 需要先有一条购物车记录
- "取消最近的待发货订单" → 需要先有一笔 `paid` 状态的订单

这类"题目私有预制数据"**不应该**进 data_packs（会污染 baseline、影响别的题目）。正确做法是在验证器里定义 `seed` 方法：

```ruby
class V200ChangeCartItemValidator < BaseValidator
  def seed
    # 此时 SET SESSION 已完成，@data_version 已就绪
    # create! 的记录会自动写入 @data_version（会话私有）
    user = User.find_by!(email: 'demo@example.com', data_version: '0')
    product = Product.find_by!(name: '矿泉水', data_version: '0')
    CartItem.create!(user: user, product: product, quantity: 2)
    # data_version 由 DataVersionable before_create 自动填入 @data_version
  end
end
```

详见 ADR-005。

---

## 3. 验证器 DSL

### 3.1 完整结构

```ruby
class V001AddToCartValidator < BaseValidator
  # 描述（API 返回给 Agent 的任务摘要）
  TASK_TITLE = "加购指定商品"
  TASK_DESC  = "将「有机苹果」加入购物车，数量 2"

  def seed
    # （可选）题目私有预制数据：用 @data_version 隔离
  end

  def prepare
    # 查 baseline 数据（只读）
    @product = Product.find_by!(name: '有机苹果', data_version: '0')
    @user    = User.find_by!(email: 'demo@example.com', data_version: '0')
    # 返回给 Agent 的题面信息
    {
      task: TASK_DESC,
      hint: "product_id=#{@product.id}",
    }
  end

  def simulate
    # 模拟"完美 Agent"的操作（用于自动化回归测试）
    CartItem.create!(
      user: @user, product: @product,
      quantity: 2
      # data_version 由 callback 自动注入 @data_version
    )
  end

  def verify
    items = CartItem
      .where(user: @user)
      .where(data_version: @data_version)   # ← 必须，否则 lint 报错
      .to_a

    add_assertion "购物车有新记录", weight: 40 do
      expect(items).not_to be_empty, "CartItem not found"
    end

    return if items.empty?   # guard clause

    add_assertion "商品正确", weight: 30 do
      expect(items.map(&:product_id)).to include(@product.id)
    end

    add_assertion "数量正确", weight: 30 do
      item = items.find { |i| i.product_id == @product.id }
      expect(item.quantity).to eq(2)
    end
  end
end
```

### 3.2 `add_assertion` 规则

- **权重总和必须 = 100**
- **失败信息必须具体**：`expect(x).to eq(y), "Expected #{y}, got #{x}"`
- **guard clause 必须**：第一个断言确认记录存在后，立即 `return if @records.empty?`

### 3.3 verify 的数据隔离

**Always**：
```ruby
# ✅
Record.where(user: @user, data_version: @data_version)

# ❌ 会看到其他 session 的数据
Record.where(user: @user)
```

---

## 4. Validator 的 ADR 演进

| ADR | 内容 |
|---|---|
| ADR-001 | 所有业务表有 data_version（触发：Category 污染事故） |
| ADR-002 | 数据只走 data_packs，不走 seeds |
| ADR-005 | 引入 `seed` 钩子承载题目私有预制数据 |
| ADR-006 | Validators 挂命名空间根，避免与业务模型撞车（Validators::Cart::V001 vs Cart） |
| ADR-007 | verify 用独立实例（跨请求状态不在内存共享，通过 DB 持久化传递） |

---

## 5. 命名与目录约定（ADR-006）

验证器按业务子域分子目录：

```
app/validators/
├── base_validator.rb
├── support/
│   └── data_packs/v1/
├── cart/
│   ├── v001_add_to_cart_validator.rb         → Validators::Cart::V001AddToCartValidator
│   └── v002_remove_from_cart_validator.rb
├── order/
│   └── v001_place_order_validator.rb
└── account/
    └── v001_update_profile_validator.rb
```

**为什么用 `Validators::Cart::` 命名空间？**
`app/validators/cart/` 目录下放 validator 文件，若不加命名空间，`Cart` 这个 module 名会和 `app/models/cart.rb` 里的 `Cart` model 类名冲突（autoloader 混乱）。在文件顶部写 `module Validators; module Cart` 即可。

---

## 6. 跨请求状态持久化（ADR-007）

`execute_prepare` 和 `execute_verify` 是**两次独立 HTTP 请求**，内存不共享。`@data_version`、`@product`、`@user` 等实例变量在 `prepare` 阶段通过 `ValidatorExecution#state` 字段（JSON）序列化存入 DB，`verify` 阶段反序列化恢复。

```ruby
# base_validator.rb（简化）
def execute_prepare
  @data_version = SecureRandom.hex(8)
  # ... prepare logic ...
  execution.update!(
    data_version: @data_version,
    state: serializable_state.to_json
  )
end

def execute_verify
  execution = ValidatorExecution.find_by!(...)
  @data_version = execution.data_version
  restore_state(JSON.parse(execution.state))
  # ... verify logic ...
end
```

**陷阱**：`@user` 存的是 ID，不是 ActiveRecord 对象（不可序列化）。`prepare` 里用 `@user_id = @user.id`，`verify` 里用 `@user = User.find(@user_id)`。

---

## 7. 延伸阅读
- [validator-linter.md](validator-linter.md) — 静态检测 data_version 遗漏
- [conventions/validator-writing.md](../conventions/validator-writing.md) — 具体写法标准
- [data-packs.md](data-packs.md) — baseline 数据加载
