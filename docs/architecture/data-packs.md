---
topic: data-packs
updated_at: 2026-04-28
related:
  - architecture/agent-sandbox.md
  - architecture/data-version.md
  - decisions/ADR-002-data-packs-not-seeds.md
source_files:
  - app/validators/support/data_packs/
  - lib/tasks/validator.rake
  - lib/data_pack_validator.rb
---

# 📦 Data Packs — 唯一的数据加载入口

> **项目的所有 baseline 数据只通过 `data_packs/v1/` 加载。**
> `db/seeds.rb` **不是**入口（只留一行注释）。原因见 [ADR-002](../decisions/ADR-002-data-packs-not-seeds.md)。

## 1. 命令

```bash
bin/rake validator:reset_baseline   # 清理 + 重新加载（幂等）
bin/rake validator:validate_packs   # 校验完整性（schema_version, 必需列, data_version='0'）
```

## 2. 目录结构

> **硬规则**：所有 v1 版本数据包**必须**放在 `v1/` 目录下（非递归）。
> 根目录只存文档，**不扫描、不加载**根目录的 `.rb`。
> 加载器扫描路径：`data_packs/v1/*.rb`。

```
app/validators/support/data_packs/
└── v1/                       ← ⚠️ 所有 data pack 必须在这里
    ├── base.rb                 ← ⚠️ 唯一允许 delete_all
    ├── <module_a>.rb           ← 业务模块 A 的全量数据
    ├── <module_b>.rb           ← 业务模块 B 的全量数据
    └── z_<module_c>.rb         ← 需最后加载的模块（z_ 前缀 hack 字母序）
```

## 3. 加载顺序

`lib/tasks/validator.rake` 按**字母序**加载 `v1/*.rb`，但有两个特例：
- `base.rb` **强制最先**（无论字母序）
- `z_*.rb` **强制最后**（用 `z_` 前缀 hack 字母序）

**字母序决定 FK 加载顺序**：确保父表文件名字母序排在子表前面即可（如 `categories.rb` < `products.rb`）。

## 4. 命名约定（金规则）

### ✅ 一个业务模块 = 一个文件

```
categories.rb   # 所有分类数据
products.rb     # 所有商品数据
users.rb        # 演示用户
```

### ❌ 禁止的命名模式

```
categories.rb + categories_supplement.rb + categories_phase2.rb   ← 分裂
products_fix.rb                                                    ← 修复不该独立成文件
orders_all.rb / orders_extended.rb                                 ← 语义冗余后缀
```

### ✅ 合法的前缀/后缀

| 场景 | 模式 | 例子 |
|---|---|---|
| 基础文件必须最先 | `base.rb` | — |
| 必须最后加载 | `z_` 前缀 | `z_product_variants.rb`（跨多业务依赖） |
| 父模块优先加载的子补充 | 父名前缀 | `tours.rb` + `tours_activities_supplement.rb` |

## 5. 文件模板

```ruby
# frozen_string_literal: true

# <module>_v1 数据包
# 加载方式: rake validator:reset_baseline

puts "正在加载 <module>_v1 数据包..."

# ---- 依赖检查（可选）----
raise "categories 未加载" if Category.count.zero?

# ---- 数据主体 ----
# 优先用 insert_all（快，绕 callbacks；rake 已 SET SESSION 自动落 '0'）
Product.insert_all([
  {
    name: '有机苹果', price: 12.8,
    image_url: ImageSeedHelper.random_image_from_category(:products),
    data_version: '0',
    created_at: Time.current, updated_at: Time.current
  },
  # ...
])

# 特殊情况（自引用 FK / 需要 ID 回写）才用 create!
puts "✓ 数据包加载完成"
```

## 6. 硬规则

| ✅ 必须 | ❌ 禁止 |
|---|---|
| 只用 `rake validator:reset_baseline` 加载 | `rails db:seed` 加载 baseline |
| 图片用 `ImageSeedHelper.random_image_from_category(:xxx)` | 直写 `https://images.unsplash.com/...` |
| `insert_all` 批量写入（快，跳过 callbacks） | `find_or_create_by!`（语义混淆） |
| `base.rb` 唯一可以 `delete_all`（且按 FK 顺序） | 其他 pack 里 `destroy_all` / `delete_all` |
| 新增独立业务模块 → 新文件 | 修 bug / 加字段 → 新文件（应该编辑已有文件） |
| 一个模块 = 一个文件 | 同一模块拆成多文件 |

## 7. base.rb 的特殊性

它是唯一允许清理的地方，且必须按 FK 逆序（叶子先删）：

```ruby
# app/validators/support/data_packs/v1/base.rb
# 按 FK 顺序删（叶子表先删，根表后删）
OrderItem.where(data_version: '0').delete_all    # ← 叶子
Order.where(data_version: '0').delete_all
CartItem.where(data_version: '0').delete_all
Product.where(data_version: '0').delete_all
Category.where(data_version: '0').delete_all     # ← 根
User.where(data_version: '0').delete_all
```

**为什么要清？** 多次 `reset_baseline` 之间，`insert_all` 会主键冲突。清了就幂等。

## 8. 图片资源

```bash
bin/rake images:seed   # 下载到本地（只需首次）
```
分类：`:people | :products | :covers | :landscapes | :interiors`

```ruby
require_relative '../../../../../app/helpers/image_seed_helper'
image_url: ImageSeedHelper.random_image_from_category(:products)
```

## 9. 典型错误（再犯扣绩效）

1. **把数据塞进 `db/seeds.rb`** → 违反 ADR-002，rollback 失效
2. **在 simulate 或 prepare 里 `create!(data_version: '0')`** → 污染 baseline
3. **自引用 FK 用 `insert_all`** → 拿不到父行 ID。正确：先插 roots 用 `create!` 拿 id，再插 children
4. **新加字段时新开一个补充文件** → 违反"一模块一文件"原则，直接编辑已有文件
5. **把 data pack 放在 `data_packs/` 根目录** → 根目录不扫描，文件必须进 `v1/`

## 10. 延伸阅读
- [data-version.md](data-version.md) — data_version 写入/过滤机制
- [ADR-002](../decisions/ADR-002-data-packs-not-seeds.md) — 为什么不用 db/seeds.rb
