---
topic: adr-015
updated_at: 2026-05-03
status: accepted
decision_date: 2026-05-03
supersedes: none
related:
  - architecture/data-packs.md
  - decisions/ADR-005-validator-seed-hook.md
---

# ADR-015 Data Pack `depends_on` 加载顺序

## Status
✅ **Accepted** — 2026-05-03

## Context

`app/validators/support/data_packs/v1/*.rb` 里每个文件是一段裸 Ruby，由 rake task 和 `BaseValidator#ensure_baseline_data_loaded` 各自用 `load file` 依次执行。**加载顺序决定正确性**：`orders` pack 依赖 `users` 和 `products` 的 baseline 记录，必须后加载。

### 原设计：`base.rb` 优先 + 字母序

```ruby
# 当前 rlbox 主干逻辑（validator.rake / base_validator.rb 都有）
pack_files = Dir.glob(dir.join('*.rb')).sort
base = pack_files.find { |f| basename == 'base.rb' }
pack_files.unshift(base) if base
pack_files.each { |f| load f }
```

这套规则在 rlbox 刚起步时够用：只有 `base.rb` 和 `demo_user.rb`，字母序恰好正确。

### 事故轨迹

在 duvy 项目做 Feed-Product 关联（has_many :through）时，需要：
- `users` baseline
- `feeds` baseline（依赖 users 作者）
- `products` baseline
- `feed_products` baseline（依赖 feeds + products）

文件取名：`feed.rb` / `feed_product.rb` / `product.rb` / `user.rb`。字母序跑下来：

```
base.rb → feed.rb → feed_product.rb → product.rb → user.rb
          ↑         ↑                               ↑
          依赖      依赖 product 还没加载            最后才加
```

绕了一圈的"解决方案"是改文件名凑字母序（`aaa_user.rb` / `bbb_product.rb`），或者把所有数据揉进 `base.rb`。两个都是技术债。

### 设计约束

1. **向后兼容**：现有所有 fork 项目的 data pack 文件**零改动**可继续工作
2. **显式优于隐式**：想声明依赖时，**不要**靠文件名 hack，要有专门语法
3. **不引入 DSL / class 改造**：data pack 文件保持"脚本"形态（顶部直接 `require` + `Model.insert_all`），方便 debug
4. **循环依赖必须爆炸**：不能"悄悄"选一个顺序跑下去

## Decision

**基于注释的 `depends_on:` 声明 + 拓扑排序 loader**。

### 文件头语法

```ruby
# frozen_string_literal: true
# depends_on: base, products, users
#
# （剩下的脚本）

Model.insert_all([...])
```

规则：
- 声明行必须出现在**文件头 40 行以内**的连续注释/空行区
- 一旦遇到第一行非注释非空的代码，header 扫描结束（避免 body 里的字符串/docstring 误触发）
- 多个名字用逗号分隔，每个名字是**其他 pack 的 basename 去掉 `.rb`**（例如 `base` 指向 `base.rb`）

### Loader 行为

新类 `DataPackLoader`（`lib/data_pack_loader.rb`）：

1. 扫 `dir/*.rb`，解析每个文件的 `depends_on:` 注释
2. **遗留规则保留**：如果 `base.rb` 存在，且没有任何文件显式 `depends_on: base`，则给所有其他文件**自动追加** `base` 依赖——保证旧项目不改 base.rb 也能跑
3. 校验每条 depends_on 指向的文件存在，否则抛 `MissingDependencyError`
4. Kahn 算法拓扑排序，同层按字母序（确定性）
5. 循环依赖抛 `CycleError`，列出卡住的文件名

调用点替换（两处）：
- `lib/tasks/validator.rake` 的 `reset_baseline` task
- `app/validators/base_validator.rb` 的 `ensure_baseline_data_loaded`

### 测试

`spec/lib/data_pack_loader_spec.rb` 覆盖 11 个场景：空目录 / 字母序 fallback / base 隐式优先 / 显式链式依赖 / 同层字母排序 / 多依赖 / 直接环 / 间接环 / missing dep / header 扫描边界 / 显式+隐式混合。

## Consequences

### Positive
- **零迁移成本**：旧 pack 文件不改依然正常（实测 rlbox `base.rb` + `demo_user.rb` 走新 loader 和旧逻辑行为一致）
- **声明式依赖**：派生项目加 `feed_products.rb` 时顶部写 `# depends_on: feeds, products` 即可，不用改文件名
- **确定性**：同一组文件在任何机器上加载顺序完全一致（字母序 tiebreak 保证）
- **早期失败**：循环依赖 / 找不到依赖 → 立即报错，不会走到一半脏数据

### Negative
- **注释不是代码**：typo 不会被编辑器标红（`# depends_on: pruducts` 会被视为无效声明忽略）—— 将来可加 `rake validator:lint_packs` 校验 depends_on 指向的文件都存在
- **只支持文件级依赖**：不能表达"这条 insert 依赖那条 insert"。如果真有这种精细需求，应该合并成同一个 pack 文件

### Migration path for existing forks

1. `git pull` rlbox → 自动拿到新 loader
2. 老 pack 文件不动，观察 `rake validator:reset_baseline` 结果
3. 遇到新的跨 pack 依赖时，只在**新 pack 文件**顶部加 `# depends_on: X` 即可

## 为什么不用 class-based DSL？

```ruby
# 曾考虑但否决：
class FeedProductPack < DataPack::Base
  depends_on :feeds, :products
  def call; ... end
end
```

否决原因：
1. 强制 fork 全部重写 data pack（生态里已有 50+ 文件）
2. 把脚本变成 class 反而不好 debug（`load` → `require` 的变化）
3. 信息量相同（一条声明 vs 一行注释），但改造成本大 100 倍

本决策选了最小侵入方案，保留未来升级到 DSL 的自由（如果真有人需要）。

## Related

- [architecture/data-packs.md](../architecture/data-packs.md) — data pack 总览
- [ADR-005](ADR-005-validator-seed-hook.md) — per-validator seed hook（pack 之外的另一种种子机制）
- ADR-014 — 同期反哺的 rls_policy generator
