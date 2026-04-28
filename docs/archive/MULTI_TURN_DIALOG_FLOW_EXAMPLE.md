> ⚠️ **Archived** — 此文件已被新 wiki 体系取代，仅保留作历史参考，勿模仿。

# 多轮对话 API 完整流程示例

本文档演示一个完整的多轮对话测试流程，帮助你理解 AI Agent 如何与 Simul User 交互。

## 测试场景

**任务：** 预订上海酒店，预算 500 元左右

**验证器：** v201_hotel_booking_multi_turn_validator

## 完整对话流程

### 第 1 步：获取任务列表

```bash
curl http://localhost:3000/api/tasks
```

**响应：**
```json
{
  "validators": [
    {
      "id": "v201_hotel_booking_multi_turn_validator",
      "task_id": "0b2d6f73-3d61-4dab-84da-4de740b906a3",
      "title": "酒店预订多轮对话",
      "description": "验证 Agent 是否能通过多轮对话获取完整信息并成功预订酒店",
      "is_multi_turn": true
    }
  ],
  "count": 1
}
```

### 第 2 步：启动训练会话

```bash
curl -X POST http://localhost:3000/api/tasks/v201_hotel_booking_multi_turn_validator/start \
  -H "Content-Type: application/json" \
  -d '{
    "agent_name": "MyAIAgent",
    "agent_version": "1.0.0"
  }'
```

**响应：**
```json
{
  "task": {
    "task": "帮我订一个上海的酒店，预算500元左右",
    "data_version": "dv_20260201123456_abc123",
    "user_id": 1,
    "context": {
      "session_token": "token_xyz789"
    }
  },
  "session_id": "sess_abc123def456",
  "task_id": "v201_hotel_booking_multi_turn_validator"
}
```

**重要信息提取：**
- `session_id`: `sess_abc123def456` （用于后续所有 API 调用）
- `data_version`: `dv_20260201123456_abc123` （创建业务数据时必须带上）
- 初始用户消息: "帮我订一个上海的酒店，预算500元左右"

---

### 第 3 步：开始多轮对话

#### 🔄 第 1 轮对话

**Agent 分析：** 用户想订酒店，但缺少入住日期和退房日期信息。

**Agent 发送消息（向用户提问）：**
```bash
curl -X POST http://localhost:3000/api/dialog/message \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "sess_abc123def456",
    "agent_message": "好的，我来帮您预订上海的酒店。请问您的入住日期和退房日期是什么时候呢？"
  }'
```

**Simul User 响应：**
```json
{
  "simul_user_message": "3天后入住，住1晚就可以了",
  "should_continue": true,
  "turn_number": 1,
  "metadata": {
    "total_messages": 2,
    "max_turns": 10
  }
}
```

**说明：**
- `simul_user_message` 由 LLM 动态生成，模拟真实用户回复
- `should_continue: true` 表示对话应继续
- `turn_number: 1` 表示这是第 1 轮对话

---

#### 🔄 第 2 轮对话

**Agent 分析：** 已获取入住日期（3天后）、退房日期（4天后），现在可以搜索酒店了。

**Agent 执行操作：**
1. 调用 `GET /hotels/search?city=上海&price_max=500` 搜索酒店
2. 找到符合条件的酒店（如：上海如家快捷酒店，价格 480 元）
3. 创建订单：
   ```ruby
   HotelBooking.create!(
     hotel_id: hotel.id,
     user_id: 1,
     data_version: "dv_20260201123456_abc123",  # ⚠️ 必须包含
     check_in_date: 3.days.from_now.to_date,
     check_out_date: 4.days.from_now.to_date,
     total_price: 480
   )
   ```

**Agent 发送消息（通知用户）：**
```bash
curl -X POST http://localhost:3000/api/dialog/message \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "sess_abc123def456",
    "agent_message": "我已为您预订了上海如家快捷酒店，价格480元，入住日期为3天后，退房日期为4天后。预订成功！"
  }'
```

**Simul User 响应：**
```json
{
  "simul_user_message": "好的，谢谢！",
  "should_continue": false,
  "turn_number": 2,
  "metadata": {
    "total_messages": 4,
    "max_turns": 10
  }
}
```

**说明：**
- `should_continue: false` 表示 Simul User 判断任务已完成，应结束对话
- Agent 应该停止对话并提交验证

---

### 第 4 步：提交验证

**Agent 判断：** `should_continue: false`，任务已完成，提交验证。

```bash
curl -X POST http://localhost:3000/api/verify/run \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "sess_abc123def456",
    "task_id": "v201_hotel_booking_multi_turn_validator"
  }'
```

**验证结果：**
```json
{
  "score": 1.0,
  "reason": "所有验证通过",
  "execution_status": "success",
  "metadata": {
    "validator_id": "v201_hotel_booking_multi_turn_validator",
    "total_score": 100,
    "max_score": 100,
    "assertions": [
      {
        "description": "创建了酒店订单",
        "passed": true,
        "weight": 30,
        "error": null
      },
      {
        "description": "酒店城市正确（上海）",
        "passed": true,
        "weight": 25,
        "error": null
      },
      {
        "description": "价格在预算范围内（480元 ≤ 500元）",
        "passed": true,
        "weight": 25,
        "error": null
      },
      {
        "description": "入住日期正确（3天后）",
        "passed": true,
        "weight": 20,
        "error": null
      }
    ],
    "dialog_turns": [
      {
        "turn": 1,
        "role": "simul_user",
        "message": "帮我订一个上海的酒店，预算500元左右"
      },
      {
        "turn": 2,
        "role": "agent",
        "message": "好的，我来帮您预订上海的酒店。请问您的入住日期和退房日期是什么时候呢？"
      },
      {
        "turn": 3,
        "role": "simul_user",
        "message": "3天后入住，住1晚就可以了"
      },
      {
        "turn": 4,
        "role": "agent",
        "message": "我已为您预订了上海如家快捷酒店，价格480元..."
      },
      {
        "turn": 5,
        "role": "simul_user",
        "message": "好的，谢谢！"
      }
    ]
  }
}
```

**结果分析：**
- **最终得分：** 100/100（满分）
- **执行状态：** success
- **所有断言通过：**
  - ✅ 创建了酒店订单（30 分）
  - ✅ 城市正确（25 分）
  - ✅ 价格符合预算（25 分）
  - ✅ 日期正确（20 分）
- **对话轮数：** 2 轮（5 条消息）

---

## API 调用时序图

```
Agent                    API                         Simul User
  |                       |                              |
  |--GET /api/tasks------>|                              |
  |<--任务列表-------------|                              |
  |                       |                              |
  |--POST /tasks/:id/start->|                            |
  |<--session_id + 初始消息-|<---生成初始消息----------|
  |                       |                              |
  |                       |                              |
  |--POST /dialog/message->|                             |
  | (Agent 提问)          |----生成回复------------->|
  |<--Simul User 回复------|<--"3天后入住，住1晚"-----|
  |                       |                              |
  | [Agent 创建订单]       |                              |
  |                       |                              |
  |--POST /dialog/message->|                             |
  | (Agent 确认)          |----判断是否结束---------->|
  |<--should_continue:false|<--"好的，谢谢"-----------|
  |                       |                              |
  |--POST /verify/run---->|                              |
  |<--验证结果（100分）----|                              |
```

---

## 关键要点

### 1. 对话何时结束？

有三种情况会结束对话：

1. **Simul User 判断任务完成**：`should_continue: false`
2. **达到最大轮数**：默认 10 轮，可自定义
3. **Agent 主动结束**：Agent 认为任务完成，不再调用 `/api/dialog/message`

### 2. 何时调用 `/api/dialog/message`？

Agent **每次**发送消息后都应调用此接口：

- ✅ 向用户提问时（获取更多信息）
- ✅ 通知用户操作结果时
- ✅ 请求用户确认时（敏感操作）
- ✅ 任何需要用户响应的场景

### 3. `data_version` 字段的作用

用于数据隔离，确保测试数据不影响生产数据。

**必须带上 `data_version` 的操作：**
```ruby
# ✅ 正确
HotelBooking.create!(
  hotel_id: hotel.id,
  data_version: params[:data_version],  # 必须包含
  check_in_date: date
)

# ❌ 错误（验证会失败：找不到订单）
HotelBooking.create!(
  hotel_id: hotel.id,
  check_in_date: date
  # 缺少 data_version
)
```

### 4. Simul User 如何生成回复？

Simul User 使用 LLM（如 GPT-4）动态生成回复，考虑以下因素：

- **对话历史**：之前所有对话内容
- **任务目标**：当前任务的目标（如"订上海酒店，预算500元"）
- **用户上下文**：用户画像、偏好、约束条件
- **真实性**：模拟真实用户行为（可能不完整、有疑问、需确认）

### 5. 调试技巧

**查看对话历史：**
```bash
rails runner "
  execution = ValidatorExecution.last
  DialogTurn.where(validator_execution_id: execution.id).order(:turn_number).each do |turn|
    puts \"第\#{turn.turn_number}条 - \#{turn.role}: \#{turn.message}\"
  end
"
```

**查看创建的订单：**
```bash
rails runner "
  dv = ValidatorExecution.last.data_version
  HotelBooking.where(data_version: dv).each do |booking|
    puts booking.inspect
  end
"
```

---

## 常见错误场景

### 错误 1：忘记调用 `/api/dialog/message`

```
Agent: [创建订单后直接调用 /api/verify/run]
结果：❌ 验证失败 - 对话不完整
```

**正确做法：** 创建订单后，发送确认消息并调用 `/api/dialog/message`

### 错误 2：缺少 `data_version` 字段

```ruby
HotelBooking.create!(
  hotel_id: hotel.id,
  check_in_date: date
  # 缺少 data_version
)
```

**验证结果：**
```json
{
  "score": 0.0,
  "reason": "未找到任何酒店订单"
}
```

**正确做法：** 所有业务数据创建时必须包含 `data_version`

### 错误 3：继续对话当 `should_continue: false`

```
Simul User: { "should_continue": false, ... }
Agent: [继续调用 /api/dialog/message]
结果：对话无意义延长
```

**正确做法：** 当 `should_continue: false` 时，立即调用 `/api/verify/run`

---

## 下一步

- 查看完整 API 文档：`docs/MULTI_TURN_VALIDATOR.md`
- 开发新验证器：`rails generate validator your_name "标题" "描述"`
- 运行测试：`rake validator:simulate_single[v201_hotel_booking_multi_turn_validator]`
