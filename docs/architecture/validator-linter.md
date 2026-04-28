---
topic: validator-linter
updated_at: 2026-04-28
status: current
related:
  - validator-system.md
  - ../conventions/validator-writing.md
supersedes:
  - ../archive/DATA_VERSION_LINT_GUARANTEE.md
source_files:
  - lib/validator_linter.rb
  - lib/tasks/validator_lint.rake
  - config/validator_lint_rules.yml (optional)
---

# Validator Linter

## 1. 解决什么问题

手写 validator 最容易忘记 **`data_version` 过滤**。`Product.where(name: '有机苹果').first` 会穿透当前 session 看到别的 session 的数据，然后 verify 随机成功/失败，调试基本无解。

Linter 做四件事：

| 类别 | 等级 | 触发条件 |
|---|---|---|
| `data_version` | **HIGH** | `verify` 方法里查业务模型但没带 `data_version:` 条件 |
| `stale_field` | HIGH | 用到已被删除/重命名的字段（根据配置文件规则） |
| `missing_includes` | MEDIUM | 访问 `model.association.field` 但查询没 `.includes(:association)` |
| `view_alignment` | MEDIUM | validator 断言的字段在声明的视图文件里找不到 |

其中 `data_version` 检查是**零配置**、**基于运行时元数据**的——Linter 启动时从 `DataVersionable.models` 自动推导业务模型列表，所以新加模型不需要改 Linter 代码。

---

## 2. 使用

```bash
# 全量 lint
bin/rake validator:lint

# 单个 validator
bin/rake validator:lint_single[v001]
```

输出样例：

```
[HIGH] V001AddToCartValidator (line 42)
  → CartItem query in verify is missing data_version isolation
  → Suggestion: Add .where(data_version: @data_version) to scope the query to this session

Found 1 issue(s): 1 HIGH, 0 MEDIUM
```

退出码：有任何 issue → `exit 1`；`strict_mode.fail_on_high_severity` 打开时只要有 HIGH 就失败。

---

## 3. `data_version` 检查原理

核心代码在 `lib/validator_linter.rb` `check_data_version`：

```ruby
# 1. 从注册中心动态拿业务模型列表
business_models = (DataVersionable.models - DataVersionable.excluded_models)
                    .select { |m| m.column_names.include?('data_version') }
                    .map(&:name)

# 2. 在 verify 方法的源代码里匹配查询模式
business_models.each do |model|
  patterns = [
    /#{model}\.where\([^)]*\)/,
    /#{model}\.find_by\([^)]*\)/,
    /#{model}\.order\([^)]*\)/,
    /#{model}\.all/, /#{model}\.first/, /#{model}\.last/
  ]
  # 提取查询链，检查是否含 data_version: @data_version
end
```

关键特性：
- **只看 `verify` 方法**，不管 `prepare` 和 `simulate`
- 支持多行链式：`CartItem.where(user: u).joins(:product).where(products: {name: 'xxx'})`
- 允许 `data_version: '0'`（baseline 查询）也算通过

---

## 4. 正确 vs 错误

### ❌ 错：未过滤

```ruby
def verify
  user = User.where(data_version: '0').first
  item = CartItem.where(user_id: user.id).first   # ❌ 会看到其他 session 的 CartItem
  add_assertion("加购成功") { expect(item).not_to be_nil }
end
```

### ✅ 对：独立 where

```ruby
item = CartItem.where(data_version: @data_version)
               .joins(:product).where(products: { name: '有机苹果' }).first
```

### ✅ 对：参数里带

```ruby
item = CartItem.where(user_id: user.id, data_version: @data_version).first
```

### ✅ 对：baseline 查询

```ruby
apple = Product.find_by(name: '有机苹果', data_version: '0')   # 显式查基线
```

---

## 5. 配置文件（可选）

位置：`config/validator_lint_rules.yml`
**没有此文件时，lint 仍正常工作（零配置模式）**。

需要开启 stale_field / view_alignment 检查时创建：

```yaml
# config/validator_lint_rules.yml
strict_mode:
  enabled: true
  fail_on_high_severity: true

rules:
  stale_fields:
    Product:
      - old_price      # 已重命名为 unit_price
      - legacy_sku

  common_associations:
    CartItem:
      - product
      - user

  view_field_mappings:
    CartItem:
      validator_fields: [quantity, subtotal_cents]
      view_files:
        - app/views/carts/show.html.erb
```

---

## 6. CI 集成

```yaml
# .github/workflows/ci.yml
- name: Lint validators
  run: bin/rake validator:lint
```

---

## 8. References / 历史参考

老文档：[`archive/DATA_VERSION_LINT_GUARANTEE.md`](../archive/DATA_VERSION_LINT_GUARANTEE.md)（含历史示例，已归档）。
