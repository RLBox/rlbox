# Validator Generator 快速参考

## 命令格式

```
生成 validator: [任务描述], 模块 [module_name], 编号 [number]
```

- **任务描述**（必需）：要测试的任务内容
- **模块名**（可选）：业务模块，默认 `common`
- **编号**（可选）：手动指定编号，默认自动分配

## 命名规则速查

| 项目 | 格式 | 示例 |
|------|------|------|
| 目录 | `{module}/` | `hotel/` |
| 文件名 | `{module}_{编号}_validator.rb` | `v001_hotel_validator.rb` |
| 类名 | `{Module}{编号}Validator` | `V001HotelValidator` |
| validator_id | `{module}_{编号}_validator` | `v001_hotel_validator` |
| 编号格式 | 三位数字 | `001`, `002`, `003` |

## 常用模块

| 模块 | 用途 |
|------|------|
| `hotel` | 酒店预订 |
| `flight` | 机票预订 |
| `train` | 火车票预订 |
| `attraction` | 景点门票 |
| `car` | 租车 |
| `common` | 通用任务（默认） |

## 快速示例

### 1. 最简单（自动一切）
```
生成 validator：预订酒店
```
→ `common/v001_common_validator.rb` (默认模块，自动编号)

### 2. 指定模块
```
生成 validator：预订酒店，模块 hotel
```
→ `hotel/v001_hotel_validator.rb` (指定模块，自动编号)

### 3. 指定模块和编号
```
生成 validator：预订酒店，模块 hotel，编号 005
```
→ `hotel/v005_hotel_validator.rb` (指定模块和编号)

### 4. 编号冲突处理
```
生成 validator：预订酒店，模块 hotel，编号 003
```
如果 003 已存在：
→ `hotel/v004_hotel_validator.rb` (自动递增)
→ 提示：⚠️ 编号 003 已存在，已自动递增到 004

## 文件结构

```ruby
# frozen_string_literal: true

require_relative '../base_validator'

# 验证用例 v001_hotel: [任务标题]
# 任务描述: ...
# 复杂度分析: ...
# 评分标准: ...

class V001HotelValidator < BaseValidator
  self.validator_id = 'v001_hotel_validator'
  self.task_id = '[自动生成的UUID]'
  self.title = '[任务标题]'
  self.timeout_seconds = 240
  
  def prepare
    # 设置实例变量，返回任务参数 Hash
  end
  
  def verify
    # 使用 add_assertion 验证结果
  end
  
  def simulate
    # (可选) 模拟 AI Agent 操作
  end
end
```

## 关键要点

✓ **DO**
- 使用三位数字编号（001, 002, 003）
- 按业务模块分类
- 权重总和 = 100
- 提供清晰的错误消息
- 使用 `return unless` 提前退出

✗ **DON'T**
- 不使用旧格式（v001_v050）
- 不添加模块命名空间
- 不使用 description 字段
- 不硬编码 UUID
- 不使用不规范的编号格式

## 编号管理

```ruby
# 使用辅助工具
require_relative 'validator_number_helper'

helper = ValidatorNumberHelper.new

# 查找下一个编号
next_num = helper.find_next_number('hotel')  # => "001"

# 检查编号是否存在
exists = helper.number_exists?('hotel', '001')  # => true/false

# 获取可用编号（自动处理冲突）
result = helper.get_available_number('hotel', '003')
# => { number: "003", conflict: false, message: "..." }
# 或 { number: "004", conflict: true, message: "⚠️ ..." }

# 列出所有 validator
validators = helper.list_validators('hotel')
# => [{ number: "001", file: "...", class_name: "V001HotelValidator" }, ...]
```

## 目录结构

```
~/fliggy/app/validators/
├── hotel/
│   ├── v001_hotel_validator.rb
│   ├── v002_hotel_validator.rb
│   └── v003_hotel_validator.rb
├── flight/
│   └── v001_flight_validator.rb
├── train/
│   └── v001_train_validator.rb
├── attraction/
│   └── v001_attraction_validator.rb
├── car/
│   └── v001_car_validator.rb
└── common/
    ├── v001_common_validator.rb
    └── v002_common_validator.rb
```

## 常见问题

**Q: 如何重新生成已存在的编号？**
A: 手动删除旧文件，或使用不同的编号。

**Q: 编号可以跳号吗？**
A: 可以，但不推荐。建议连续编号便于管理。

**Q: 可以自定义模块名吗？**
A: 可以，使用任意小写字母和下划线的组合。

**Q: 旧的 v001_v050 格式还能用吗？**
A: 暂时兼容，但新生成默认使用新格式。

**Q: 如何迁移旧 validator？**
A: 参考 README_UPGRADE.md 中的迁移指南。
