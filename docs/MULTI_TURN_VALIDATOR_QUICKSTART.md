# 多轮对话验证器快速上手指南

## 5 分钟快速体验

### 1. 配置 LLM API（必需）

编辑 `config/application.yml`：

```yaml
development:
  LLM_BASE_URL: "https://api.openai.com/v1"
  LLM_API_KEY: "sk-your-api-key-here"
  LLM_MODEL: "gpt-4"
```

### 2. 运行第一个测试

```bash
# 启动项目
bin/dev

# 新开终端，运行测试
rake validator:simulate_single[v201_hotel_booking_multi_turn_validator]
```

### 3. 查看测试结果

你会看到类似输出：

```
========================================
验证器: v201_hotel_booking_multi_turn_validator
标题: 酒店预订多轮对话
========================================

[对话记录]
第 1 轮:
  用户: 帮我订一个上海的酒店，预算500元左右
  Agent: 好的，请问您的入住日期和退房日期是？

第 2 轮:
  用户: 3天后入住，住1晚
  Agent: 已为您预订上海XX酒店...

[验证结果]
✓ 创建了酒店订单 (30分)
✓ 酒店城市正确 (25分)
✓ 价格在预算范围内 (25分)
✓ 入住日期正确 (20分)

最终得分: 100/100
```

## 甲方集成指南（4 步）

### 步骤 1: 获取任务列表

```bash
curl http://localhost:3000/api/tasks
```

响应：
```json
{
  "validators": [
    {
      "id": "v201_hotel_booking_multi_turn_validator",
      "task_id": "0b2d6f73-3d61-4dab-84da-4de740b906a3",
      "title": "酒店预订多轮对话",
      "is_multi_turn": true
    },
    {
      "id": "v001_flight_booking_validator",
      "task_id": "a1b2c3d4-5678-90ab-cdef-1234567890ab",
      "title": "单程机票预订",
      "is_multi_turn": false
    }
  ],
  "count": 2
}
```

**如何识别多轮对话验证器？**
查看 `is_multi_turn` 字段：
- `true` → 多轮对话验证器，需要使用 `POST /api/dialog/message` 接口
- `false` → 传统验证器，直接调用业务 API 完成任务

### 步骤 2: 启动训练会话

```bash
curl -X POST http://localhost:3000/api/tasks/v201_hotel_booking_multi_turn_validator/start \
  -H "Content-Type: application/json" \
  -d '{
    "agent_name": "MyAIAgent",
    "agent_version": "1.0.0"
  }'
```

响应：
```json
{
  "session_id": "sess_abc123",
  "task_id": "v201_hotel_booking_multi_turn_validator",
  "is_multi_turn": true,
  "task": {
    "data_version": "dv_xyz789",
    "title": "今天是2025年2月2日。帮我订一个上海的酒店，预算500元左右",
    "context": {
      "user_id": 123,
      "session_token": "token_xxx"
    }
  }
}
```

### 步骤 3: 多轮对话（Agent 发送消息获取 Simul User 回复）

**这是关键接口！** 每次 Agent 发送消息后，必须调用此接口获取 Simul User 的回复。

```bash
curl -X POST http://localhost:3000/api/dialog/message \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "sess_abc123",
    "agent_message": "好的，请问您的入住日期和退房日期是？"
  }'
```

响应：
```json
{
  "simul_user_message": "3天后入住，住1晚",
  "should_continue": true,
  "turn_number": 2
}
```

**重要说明：**
- `simul_user_message` 由 LLM 动态生成，不是预定义脚本
- `should_continue: true` 表示应继续对话，`false` 表示应结束并验证
- Agent 每次发送消息（提问、确认、通知）后，都要调用此接口

### 步骤 4: 完成任务后提交验证

```bash
curl -X POST http://localhost:3000/api/verify/run \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "sess_abc123",
    "agent_response": "已为您成功预订酒店"
  }'
```

响应：
```json
{
  "success": true,
  "score": 100,
  "max_score": 100,
  "assertions": [...],
  "dialog_turns": [...]
}
```

## 重要提示

### ⚠️ 数据隔离（必须遵守）

创建业务数据时**必须**包含 `data_version` 字段：

```ruby
# ✅ 正确
HotelBooking.create!(
  hotel_id: hotel.id,
  data_version: params[:data_version],  # 必须包含
  check_in_date: date
)

# ❌ 错误（会导致验证失败）
HotelBooking.create!(
  hotel_id: hotel.id,
  # 缺少 data_version
  check_in_date: date
)
```

### 📊 评分说明

每个验证器包含多个断言，每个断言有权重：
- ✓ 通过：获得该断言权重分数
- ✗ 失败：该断言不得分

总分 = 通过的断言权重之和

### 🔍 调试技巧

查看详细日志：
```bash
VERBOSE=1 rake validator:simulate_single[v201_hotel_booking_multi_turn_validator]
```

查看对话历史：
```bash
rails runner "
  DialogTurn.where(data_version: 'dv_xxx').order(:turn_number).each do |turn|
    puts \"\#{turn.role}: \#{turn.message}\"
  end
"
```

## 下一步

- 阅读完整文档：`docs/MULTI_TURN_VALIDATOR.md`
- 开发新验证器：`rails generate validator your_name "标题" "描述"`
- 查看示例代码：`app/validators/v201_v250/v201_hotel_booking_multi_turn_validator.rb`

## 常见问题

**Q: 测试失败显示"未找到订单"？**
A: 检查业务数据是否包含正确的 `data_version` 字段

**Q: Simul User 回复不合理？**
A: 检查 LLM API 配置，或调整 `user_context` 提供更多用户画像信息

**Q: 如何自定义对话轮数？**
A: 在验证器中设置 `self.max_turns = 5`（默认 10 轮）

**Q: 可以并发测试吗？**
A: 目前使用互斥锁确保同时只运行一个验证，避免数据冲突
