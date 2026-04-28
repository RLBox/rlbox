---
topic: adding-models
updated_at: 2026-04-28
related:
  - architecture/data-version.md
  - architecture/data-packs.md
  - decisions/ADR-001-all-business-tables-have-data-version.md
---

# ➕ 加新业务表 / 新字段的完整流程

> 目的：防止再犯「某表没有 data_version 然后用三件套绕过」这种错误。

## 场景 A：新增业务表

```bash
# 1. 用生成器（绝不手写 CreateXxx migration）
bin/rails g model Coupon code:string discount:decimal \
                         user:references status:string:default=active

# 自动得到：
#   - t.string :data_version, default: '0', null: false, limit: 50
#   - t.index  :data_version
#   - ApplicationRecord 继承 → 自动 include DataVersionable
```

**不要**做的事：
- ❌ `bin/rails g migration CreateCoupons` ← 跳过了 data_version 自动化
- ❌ 在 model 里写 `data_version_excluded!` ← 业务表禁用

## 场景 B：加字段到已有业务表

```bash
bin/rails g migration AddExpiryToCoupons expires_at:datetime
```
正常走 Rails 标准流程。data_version 列已经有了。

## 场景 C：baseline 数据要跟着加

如果这张表需要有 baseline 数据：

1. 新建 `app/validators/support/data_packs/v1/<model_plural>.rb`
2. 字母序自动安排位置（确保 FK 父表文件名字母序更靠前）
3. 在 `base.rb` 加清理：
```ruby
Coupon.where(data_version: '0').delete_all
```
4. 跑 `bin/rake validator:reset_baseline` 验证幂等

## 场景 D：加"真正的"系统表（罕见）

判断准则：**Agent 绝对不会读/写它**（只用于运维/鉴权/追踪）。

```ruby
class AuditLog < ApplicationRecord
  data_version_excluded!                           # ① 不注册到 models
  default_scope { unscope(where: :data_version) }  # ② 绕 default_scope
  skip_callback :create, :before, :set_data_version # ③ 跳过 before_create
end
```

同时 migration **不加** data_version 列（需要手写 migration 或传 `--no-data-version` 如果 generator 支持）。

三件套缺一不可。详见 [ADR-003](../decisions/ADR-003-business-vs-system-tables.md)。

## 场景 E：把业务表误设为系统表（纠错）

1. 写 migration 加 `data_version` 列：
```ruby
add_column :foos, :data_version, :string, null: false, default: '0', limit: 50
add_index  :foos, :data_version
```
2. 从 model 里删掉三件套
3. 在 `data_packs/v1/foos.rb` 重建 baseline
4. 在 `base.rb` 加清理
5. 跑 `rake validator:reset_baseline` + `rake validator:validate_packs`

## 提交前 checklist
- [ ] `bin/rake db:migrate` 通过
- [ ] `bin/rake validator:reset_baseline` 幂等（跑两次无报错）
- [ ] `bin/rake validator:validate_packs` 通过
- [ ] `bin/rake test` 通过（至少 `spec/models/<new_model>_spec.rb`）
- [ ] 新建 `docs/models/<new-model>.md` entity page
- [ ] 更新 `docs/models/INDEX.md` 表格
- [ ] 如果引入新规范 → 新开 ADR
