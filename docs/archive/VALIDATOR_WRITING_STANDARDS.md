> ⚠️ **Archived** — 此文件已被新 wiki 体系取代，仅保留作历史参考，勿模仿。

# Validator 编写标准

## 一、题目格式（用户视角）

**格式：** `给/帮 [受益人] + 动词 + 核心目标 + （关键约束）`

**✅ 正确示例：**
- `给张三预订韩国5G高速WiFi（租1台用5天）`
- `给张三预订后天入住一晚深圳的经济型酒店（预算≤500元，选性价比最高的）`
- `给张三和李四订明天去上海的机票（选最便宜的经济舱）`

**❌ 错误示例：**
- `预订后天入住一晚深圳的经济型酒店（1间房，1成人，入住人填张三）` ← 像表单字段
- `订WiFi邮寄到北京朝阳区建国路118号，联系人张三13800138000` ← 像操作手册

**应该包含：** 受益人、核心目标、关键约束（预算/最便宜/时间要求）  
**不应包含：** 具体地址、电话号码、操作步骤、表单字段细节

---

## 二、日期/时间处理

### 2.1 周末日期描述原则

**❌ 禁止使用"本周末"** - 周六/周日有歧义
**✅ 使用"下周六"** - 明确无歧义

### 2.2 下周六日期计算

```ruby
# 标题和描述统一使用"下周六"
self.title = '给张三等4人预订下周六广州长隆野生动物世界成人票（最便宜）'
self.description = '帮张三、李四、王芳、刘强这4个人订下周六的长隆门票，要最便宜的那家'

# prepare：计算下周六日期
today = Date.current

if today.saturday?
  @visit_date = today + 7.days  # 今天是周六，选择下一个周六
else
  days_until_next_saturday = (6 - today.wday) % 7
  days_until_next_saturday = 7 if days_until_next_saturday == 0  # 今天是周日
  @visit_date = today + days_until_next_saturday.days
end
```

### 2.3 数据包日期范围

**所有与日期相关的数据包必须覆盖 14 天以上：**

```ruby
start_date = Date.today - 1.day  # 支持西时区用户
end_date = start_date + 14.days  # 至少 14 天
```

### 2.4 数据包完整性验证（⚠️ CRITICAL）

**问题场景（v261 案例）：**
- 验证器 v261 测试"预订泰国5天境外游"
- 数据包 `tour_groups.rb` 只有国内目的地，**没有泰国数据**
- 验证器使用 fallback 逻辑找到任意境外游产品，表面通过但**测试无效**
- 用户发现问题后要求："**绝对杜绝这种情况，没有就新增数据到数据包**"

**强制规则：**

1. **验证器需要什么数据，数据包必须提供精确数据**
   - ❌ 依赖 fallback 逻辑：`@product ||= Product.where(...).first`
   - ✅ 精确查询必须成功：`@product = Product.find_by!(...)`

2. **创建验证器前，先检查数据包是否完整**
   ```bash
   # 检查是否存在所需数据
   rails runner "puts TourGroupProduct.where(destination: '泰国', data_version: 0).count"
   # 如果返回 0，必须先添加数据包
   ```

3. **新增数据必须合并到现有数据包文件**
   - ✅ 编辑 `app/validators/support/data_packs/v1/tour_groups.rb` 添加泰国等境外目的地
   - ❌ 创建新文件 `tour_groups_international.rb`（禁止拆分）

4. **数据包更新后必须重新加载并验证**
   ```bash
   rake validator:reset_baseline  # 重新加载所有数据包
   rails runner "puts TourGroupProduct.where('destination LIKE ?', '%泰国%').count"  # 验证数据
   rake validator:simulate_single[v261_book_international_travel_with_insurance_validator]  # 测试
   ```

**v261 修复方案：**
```ruby
# tour_groups.rb - 添加境外目的地到现有配置
destinations_config = [
  # ... 原有国内目的地 ...
  
  # 境外游目的地（新增）
  { name: '泰国', cities: ['曼谷', '普吉', '芭提雅', '清迈'], 
    attractions: ['大皇宫', '玉佛寺', '四面佛', '水上市场', '芭提雅海滩', '皮皮岛'], 
    departure_cities: ['上海', '北京', '广州', '深圳', '成都', '杭州'] },
  { name: '日本', cities: ['东京', '大阪', '京都', '北海道'], 
    attractions: ['富士山', '浅草寺', '清水寺', '奈良公园', '心斋桥'], 
    departure_cities: ['上海', '北京', '广州', '深圳', '成都'] },
  # ... 其他境外目的地 ...
]
```

**经验教训：**
- **预防 > 修复**：创建验证器前先审查数据包是否完整
- **精确 > 兜底**：验证器不应依赖 fallback 逻辑来容忍数据缺失
- **合并 > 拆分**：同模块数据必须在一个文件中管理
- **验证 > 假设**：修改数据包后必须运行 `reset_baseline` 和验证命令

---

## 三、demo_user 数据使用

**数据文件：** `app/validators/support/data_packs/v1/demo_user.rb`

**家庭关系说明：**
```
┌─────────────────────────────────────────────────────────────┐
│ 家庭1：张三一家（三口之家 + 爷爷）                           │
│   - 张建国（男，65岁，1959年生）- 爷爷（张三的父亲）         │
│   - 张三（男，34岁，1990年生）- 丈夫/父亲                    │
│   - 王芳（女，39岁，1985年生）- 妻子/母亲                    │
│   - 小明（男，9岁，2015年生）- 儿子                          │
├─────────────────────────────────────────────────────────────┤
│ 家庭2：刘强一家（三口之家）                                  │
│   - 刘强（男，36岁，1988年生）- 丈夫/父亲                    │
│   - 陈静（女，35岁，1989年生）- 妻子/母亲                    │
│   - 小红（女，6岁，2018年生）- 女儿                          │
├─────────────────────────────────────────────────────────────┤
│ 其他关系：                                                   │
│   - 李四（男，34岁，1990年生）- 张三的弟弟                   │
└─────────────────────────────────────────────────────────────┘
```

**demo@travel01.com 提供：**

**passengers（出行人）:**

| 姓名 | 年龄 | 出生年份 | 身份证号 | 电话 | 关系 | 适用场景 |
|------|-----|----------|------------------|-------------|------|----------|
| 张建国 | 65岁 | 1959年 | 110101195912155555 | 13200132000 | 老人 | **老年人保险/酒店/机票** |
| 张三 | 34岁 | 1990年 | 110101199001011234 | 13800138000 | 成人 | 酒店/机票/门票 |
| 李四 | 34岁 | 1990年 | 110101199001012345 | 13900139000 | 成人 | 酒店/机票/门票 |
| 王芳 | 39岁 | 1985年 | 110101198506153456 | 13700137001 | 成人 | 酒店/机票/门票 |
| 刘强 | 36岁 | 1988年 | 110101198803214567 | 13600136001 | 成人 | 酒店/机票/门票 |
| 陈静 | 35岁 | 1989年 | 110101198904158901 | 13300133001 | 成人 | 酒店/机票/门票 |
| 小明 | 9岁 | 2015年 | 110101201507085678 | 13500135001 | 儿童 | 儿童票/亲子游 |
| 小红 | 6岁 | 2018年 | 110101201808126789 | 13400134001 | 儿童 | 儿童票/亲子游 |

**addresses（收货地址）:**
- 张三（北京朝阳SOHO）
- 李四（上海浦东陆家嘴）
- 王芳（广州天河珠江新城）
- 刘强（深圳南山科技园）
- 小明（成都高新区）

**contacts（联系人）:**
- 张三 (13800138000)
- 王芳 (13700137001)
- 刘强 (13600136001)

**联系人选择原则：**
- 联系人不必是受益人本人，可以是任何有联系方式的人
- 只要该人的联系信息（姓名、电话）在 passengers 或 contacts 中存在即可
- 例如：给张三、李四预订门票，联系人可以选择张三、李四、王芳、刘强中的任意一人

**使用规则：**

| 场景 | 使用数据 | verify 字段 | delivery_method |
|------|---------|------------|----------------|
| 酒店入住人/机票/火车票 | passengers | guest_name/passenger_id | - |
| **酒店套餐预订** | **passengers** | **contact_name + contact_phone** | - |
| **邮轮预订** | **passengers** | **contact_name + contact_phone + passenger_info** | - |
| **景点门票/活动** | **passengers** | **contact_phone + passenger_ids** | - |
| **WiFi/SIM卡邮寄** | **addresses** | **contact_info: {name, phone, address}** | **'mail'（只支持邮寄）** |
| **签证申请** | **passengers + addresses** | **contact_name, contact_phone, delivery_address** | **'mail'（只支持邮寄）** |

**⚠️ 业务规则约束：**

**WiFi/SIM卡/签证申请：只支持邮寄方式（delivery_method: 'mail'）**
- ❌ 禁止：`home_pickup: true`（上门取件/自取）
- ✅ 必须：`delivery_method: 'mail'`
- 原因：前端只支持邮寄配送，不支持上门取件功能

**❌ 禁止：**
- 硬编码姓名、电话、地址
- 在 simulate 中创建新用户：`User.find_or_create_by!(...)`
- 在签证/WiFi/SIM卡业务中使用 `home_pickup: true` 或 `delivery_method: 'pickup'`

---

## 四、verify 断言规则

### 4.1 查询过滤原则

**第一条断言必须查询并存储订单：**
```ruby
add_assertion "创建了订单", weight: 20 do
  @orders = ModelName
    .where(data_version: @data_version)  # ✅ 必须：会话隔离
    .where(core_entity: @value)          # ✅ 核心实体（酒店名/景点名）
    # ❌ 不要过滤待验证属性（日期/价格/房型）
    .order(created_at: :desc)
    .to_a
  
  expect(@orders).not_to be_empty
  @order = @orders.first
end

return if @order.nil?  # Guard clause
```

**✅ 必须包含：** `data_version: @data_version`、核心业务实体  
**❌ 不能包含：** 待验证的属性（日期、价格、房型）

**为什么？** 如果查询包含 `visit_date: @expected_date`，日期错误时报"未找到订单"而不是"日期错误"，失去评分粒度。

### 4.2 断言权重分配

- **订单存在** (20-25%): 查询订单 + 存储到实例变量
- **核心实体** (10-15%): 酒店名/景点名/航班号正确
- **关键属性** (10-15% 每个): 日期、价格、数量、入住人信息
- **业务逻辑** (20-30%): 最便宜、性价比最高、优化选择

**总和必须 = 100%**

### 4.3 乘客/联系人信息验证

**核心原则：** prepare 查询 `data_version: 0` → simulate 使用实例变量 → verify 验证

#### 单人场景

**示例1：成人酒店预订**
```ruby
# prepare
@passenger = User.find_by!(email: 'demo@travel01.com', data_version: 0)
  .passengers.find_by!(name: '张三', data_version: 0)
@expected_phone = @passenger.phone

# simulate
ModelName.create!(
  passenger_name: @passenger.name,
  passenger_phone: @expected_phone,
  data_version: @data_version
)

# verify（10分）
add_assertion "乘客信息正确", weight: 10 do
  expect(@order.passenger_phone).to eq(@expected_phone)
end
```

**示例2：酒店套餐预订（v098）**
```ruby
# prepare - 预查询乘客信息（避免 simulate 中查询 data_version: 0）
user = User.find_by!(email: 'demo@travel01.com', data_version: 0)
@passenger = user.passengers.find_by!(name: '张三', data_version: 0)
@expected_contact_name = @passenger.name
@expected_contact_phone = @passenger.phone

# simulate - 使用实例变量，避免重复查询
passenger = user.passengers.find_by!(name: '张三', data_version: 0)
HotelPackageOrder.create!(
  contact_name: passenger.name,
  contact_phone: passenger.phone,
  data_version: @data_version
)

# verify（10分）
add_assertion "联系人信息正确（张三）", weight: 10 do
  expect(@package_order.contact_name).to eq(@expected_contact_name),
    "联系人姓名错误。期望: #{@expected_contact_name}, 实际: #{@package_order.contact_name}"
  expect(@package_order.contact_phone).to eq(@expected_contact_phone),
    "联系人电话错误。期望: #{@expected_contact_phone}, 实际: #{@package_order.contact_phone}"
end
```

**示例3：老年人保险（v080）**
```ruby
# prepare - 必须使用张建国（65岁），不是张三（34岁）
user = User.find_by!(email: 'demo@travel01.com', data_version: 0)
@zhangjianguo = user.passengers.find_by!(name: '张建国', data_version: 0)  # 65岁老人
@expected_insured_name = @zhangjianguo.name
@expected_insured_id_number = @zhangjianguo.id_number

# simulate
insured_persons_data = [{ name: @zhangjianguo.name, id_number: @zhangjianguo.id_number }]
InsuranceOrder.create!(
  insured_persons: insured_persons_data,
  data_version: @data_version
)

# verify（5分）
add_assertion "被保险人信息正确（张建国）", weight: 5 do
  insured_persons = @insurance_order.insured_persons || []
  zhangjianguo_record = insured_persons.find { |p| p['name'] == @expected_insured_name }
  expect(zhangjianguo_record).not_to be_nil
  expect(zhangjianguo_record['id_number']).to eq(@expected_insured_id_number)
end
```

#### 多人场景（邮轮预订）

**业务特点：**
- 多人共用一个订单，包含乘客信息数组（passenger_info）
- 可以从乘客中任选一人作为联系人
- 需要验证联系人电话与姓名匹配

**代码模式（v095 案例）：**
```ruby
# prepare
user = User.find_by!(email: 'demo@travel01.com', data_version: 0)
@zhangsan = user.passengers.find_by!(name: '张三', data_version: 0)
@lisi = user.passengers.find_by!(name: '李四', data_version: 0)
@expected_passenger_names = [@zhangsan.name, @lisi.name]

# 有效联系人电话映射
@valid_contact_phones = {
  '张三' => @zhangsan.phone,
  '李四' => @lisi.phone
}

# simulate：随机选择联系人
contact_names = ['张三', '李四']
selected_contact_name = contact_names.sample
contact_passenger = selected_contact_name == '张三' ? zhangsan : lisi

# 创建乘客信息数组
passenger_info = [
  { name: zhangsan.name, id_number: zhangsan.id_number, phone: zhangsan.phone },
  { name: lisi.name, id_number: lisi.id_number, phone: lisi.phone }
]

CruiseOrder.create!(
  contact_name: contact_passenger.name,
  contact_phone: contact_passenger.phone,
  passenger_info: passenger_info,
  quantity: 2,
  data_version: @data_version
)

# verify：乘客信息（10分）+ 联系人（5分）= 合计15分
add_assertion "乘客信息正确（张三、李四）", weight: 10 do
  passenger_list = @order.passenger_list  # 模型方法解析 passenger_info
  expect(passenger_list).not_to be_empty,
    "乘客信息缺失"
  
  passenger_names = passenger_list.map { |p| p['name'] || p[:name] }.compact.sort
  expect(passenger_names).to match_array(@expected_passenger_names.sort),
    "乘客信息错误。期望: #{@expected_passenger_names.sort.join('、')}, 实际: #{passenger_names.join('、')}"
end

add_assertion "联系人信息正确（张三或李四）", weight: 5 do
  valid_contacts = ['张三', '李四']
  expect(valid_contacts).to include(@order.contact_name),
    "联系人姓名错误。期望: 张三或李四, 实际: #{@order.contact_name}"
  
  expected_phone = @valid_contact_phones[@order.contact_name]
  expect(@order.contact_phone).to eq(expected_phone),
    "联系人电话与姓名不匹配。联系人: #{@order.contact_name}, 期望电话: #{expected_phone}, 实际电话: #{@order.contact_phone}"
end
```

**关键点：**
- ✅ 乘客信息验证：使用 `match_array` 验证数组包含所有期望乘客
- ✅ 联系人验证：支持任选一人，动态验证电话匹配
- ✅ 权重分配：乘客信息（10分）> 联系人（5分）
- ❌ 不要固定联系人：`expect(@order.contact_name).to eq('张三')`

#### 多人场景（门票/活动）

**标题格式：**
- 2-3人：列全名 → `给张三、李四、王芳预订长城门票（3人，最便宜）`
- 4人以上：简化 → `给张三等4人预订下周六广州长隆野生动物世界成人票（最便宜）`

**代码模式：**
```ruby
# prepare
user = User.find_by!(email: 'demo@travel01.com', data_version: 0)
@zhangsan = user.passengers.find_by!(name: '张三', data_version: 0)
@lisi = user.passengers.find_by!(name: '李四', data_version: 0)
@wangfang = user.passengers.find_by!(name: '王芳', data_version: 0)
@expected_contact_phone = @zhangsan.phone
@expected_passenger_names = [@zhangsan.name, @lisi.name, @wangfang.name]

# simulate
TicketOrder.create!(
  contact_phone: @expected_contact_phone,
  passenger_ids: [@zhangsan.id, @lisi.id, @wangfang.id],
  quantity: 3,
  data_version: @data_version
)

# verify：联系人（10分）+ 游客信息（10分）= 合计20分
add_assertion "联系人信息正确", weight: 10 do
  @orders.each { |o| expect(o.contact_phone).to eq(@expected_contact_phone) }
end

add_assertion "游客信息正确", weight: 10 do
  all_ids = @orders.flat_map { |o| o.passenger_ids || [] }.compact.uniq
  actual_names = Passenger.where(id: all_ids, data_version: 0).pluck(:name).sort
  expect(actual_names).to match_array(@expected_passenger_names.sort)
end
```

#### 多人签证申请

**业务特点：**
- 多人共用一个订单，只需填写一个联系人和收货地址
- 可以从申请人中任选一人作为联系人
- 收货地址必须与联系人的地址一致
- **⚠️ 只支持邮寄方式（delivery_method: 'mail'），禁止使用上门取件**

**代码模式（v075 案例）：**
```ruby
# prepare
@country_name = '美国'
@traveler_count = 2

# simulate：随机选择联系人
user = User.find_by!(email: 'demo@travel01.com', data_version: 0)
contact_names = ['张三', '李四']
selected_contact_name = contact_names.sample
contact_passenger = user.passengers.find_by!(name: selected_contact_name, data_version: 0)
contact_address = user.addresses.find_by!(name: selected_contact_name, data_version: 0)
full_address = "#{contact_address.province}#{contact_address.city}#{contact_address.district}#{contact_address.detail}"

VisaOrder.create!(
  traveler_count: @traveler_count,
  contact_name: contact_passenger.name,
  contact_phone: contact_passenger.phone,
  delivery_method: 'mail',  # ✅ 必须：只支持邮寄方式
  delivery_address: full_address,
  data_version: @data_version
)

# verify：配送方式（5分）+ 联系人（2分）+ 电话匹配（2分）+ 地址匹配（1分）= 合计10分
add_assertion "使用邮寄方式", weight: 5 do
  expect(@visa_order.delivery_method).to eq('mail'),
    "配送方式错误。期望: mail（邮寄），实际: #{@visa_order.delivery_method}"
end

add_assertion "联系人姓名正确（张三或李四）", weight: 2 do
  valid_names = ['张三', '李四']
  expect(valid_names).to include(@visa_order.contact_name)
end

add_assertion "联系电话与联系人匹配", weight: 2 do
  valid_pairs = { '张三' => '13800138000', '李四' => '13900139000' }
  expected_phone = valid_pairs[@visa_order.contact_name]
  expect(@visa_order.contact_phone).to eq(expected_phone)
end

add_assertion "收货地址与联系人匹配", weight: 1 do
  valid_addresses = {
    '张三' => /北京.*朝阳.*建国路.*SOHO/,
    '李四' => /上海.*浦东.*陆家嘴.*1000/
  }
  expected_pattern = valid_addresses[@visa_order.contact_name]
  expect(@visa_order.delivery_address).to match(expected_pattern)
end
```

**关键点：**
- ✅ **必须验证邮寄方式**：`expect(@order.delivery_method).to eq('mail')`（5分）
- ❌ 不要固定联系人：`expect(@order.contact_name).to eq('张三')`
- ✅ 支持任选：`expect(['张三', '李四']).to include(@order.contact_name)`
- ✅ 动态验证电话和地址：根据联系人姓名匹配对应的电话和地址

**不同场景对比：**

| 维度 | 门票/活动 | 邮轮预订 | 酒店套餐 | 签证申请 |
|------|---------|---------|---------|---------|
| 订单结构 | quantity=4 + passenger_ids | quantity=2 + passenger_info | quantity=1 + contact | traveler_count=2 + 单个联系人 |
| 联系人要求 | 固定一人 | 多人任选其一 | 固定一人 | 多人任选其一 |
| 验证字段 | contact_phone + passenger_ids | contact_name + contact_phone + passenger_info | contact_name + contact_phone | contact_name + contact_phone + delivery_address |
| 权重分配 | 联系人10分 + 游客10分 | 乘客10分 + 联系人5分 | 联系人10分 | 联系人3分 + 电话3分 + 地址4分 |

### 4.4 特殊字段验证

**WiFi租赁/SIM卡收货地址（20-25分）：**
```ruby
# prepare
# WiFi租赁：按受益人姓名查询（给张三订WiFi → 查张三地址）
@address = User.find_by!(email: 'demo@travel01.com', data_version: 0)
  .addresses.find_by!(name: '张三', data_version: 0)

# SIM卡/电话卡：查询默认地址（is_default: true）
@address = User.find_by!(email: 'demo@travel01.com', data_version: 0)
  .addresses.find_by!(is_default: true, data_version: 0)

# simulate
full_address = "#{@address.province}#{@address.city}#{@address.district}#{@address.detail}"
InternetOrder.create!(
  delivery_method: 'mail',
  contact_info: { name: @address.name, phone: @address.phone, address: full_address }.to_json,
  data_version: @data_version
)

# verify
add_assertion "收货地址正确", weight: 20 do
  expect(@order.delivery_method).to eq('mail')
  contact_info = JSON.parse(@order.contact_info)
  expect(contact_info['name']).to eq(@address.name)
  expect(contact_info['phone']).to eq(@address.phone)
  expect(contact_info['address']).to include('北京')
end
```

---

## 五、检查清单

### 题目检查
- [ ] 格式："给XX预订..." 或 "帮XX订..."
- [ ] 包含受益人和关键约束
- [ ] **多人场景：description 必须包含具体人名（如：张三、李四、王芳、刘强）**
- [ ] 删除具体地址、电话、操作步骤

### 数据引用检查
- [ ] 乘客信息在 prepare 中预查询（避免 simulate 中使用 data_version: 0）
- [ ] 需身份证号的用 passengers（酒店/机票/保险）
- [ ] **需收货地址的用 addresses：WiFi租赁（按受益人姓名）、SIM卡（is_default: true）、签证申请（按联系人姓名）**
- [ ] **签证/WiFi/SIM卡业务：必须使用 `delivery_method: 'mail'`（只支持邮寄）**
- [ ] 删除 `User.find_or_create_by!` 创建用户
- [ ] simulate 中无 `data_version: 0` 的查询或创建

### 验证断言检查
- [ ] 第一条断言查询订单 + 包含 `data_version: @data_version`
- [ ] 查询只过滤核心实体，不过滤待验证属性
- [ ] 单人场景：乘客信息验证（10分）
- [ ] **多人门票/活动场景：联系人（10分）+ 游客信息（10分）= 20分**
- [ ] **邮轮多人场景：乘客信息（10分）+ 联系人（5分，支持任选）= 15分**
- [ ] **酒店套餐单人场景：联系人（10分）**
- [ ] **签证多人场景：配送方式（5分）+ 联系人姓名（2分，支持任选）+ 电话匹配（2分）+ 地址匹配（1分）= 10分**
- [ ] **收货地址验证：邮寄方式 + 姓名 + 电话 + 地址（20-25分）**
- [ ] **签证/WiFi/SIM卡：必须验证 `delivery_method: 'mail'`**
- [ ] 权重总和 = 100%

---

**核心原则：**
- 题目 = 用户说话方式（自然语言）
- prepare = Agent 任务参数（结构化数据）
- simulate = 真实操作模拟（使用 demo_user 数据）
- verify = 精确评分断言（分离查询和验证逻辑）
