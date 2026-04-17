# 多轮对话验证器使用文档

## 概述

多轮对话验证器框架用于测试 AI Agent 在处理模糊请求和多轮对话场景下的智能反应能力。系统使用 AI 模拟用户（Simul User）生成动态对话，验证 Agent 是否能正确理解意图、主动询问缺失信息、并完成任务目标。

## 核心特性

- **AI 驱动的用户模拟**：使用 LLM 动态生成用户消息，非预定义脚本
- **多轮对话支持**：支持最多 10 轮对话交互
- **对话历史记录**：完整记录每轮对话内容用于分析
- **自动验证**：验证 Agent 是否完成任务目标和满足业务规则
- **RLS 数据隔离**：使用 PostgreSQL Row-Level Security 确保测试数据独立

## 快速开始

### 1. 环境配置

在 `config/application.yml` 中配置 LLM API：

```yaml
development:
  LLM_BASE_URL: "https://api.openai.com/v1"
  LLM_API_KEY: "your-api-key-here"
  LLM_MODEL: "gpt-4"

test:
  LLM_BASE_URL: "https://api.openai.com/v1"
  LLM_API_KEY: "your-api-key-here"
  LLM_MODEL: "gpt-4"
```

### 2. 运行测试

**测试单个验证器（推荐用于开发调试）：**
```bash
rake validator:simulate_single[v201_hotel_booking_multi_turn_validator]
```

**测试所有验证器：**
```bash
rake validator:simulate
```

**查看详细日志：**
```bash
VERBOSE=1 rake validator:simulate_single[v201_hotel_booking_multi_turn_validator]
```

### 3. 测试结果解读

测试输出示例：

```
========================================
验证器: v201_hotel_booking_multi_turn_validator
标题: 酒店预订多轮对话
========================================

[Prepare 阶段]
准备数据: {:task=>"帮我订一个上海的酒店，预算500元左右", ...}

[Simulate 阶段]
第 1 轮对话:
  Simul User: 帮我订一个上海的酒店，预算500元左右
  Agent: 好的，请问您的入住日期和退房日期是？

第 2 轮对话:
  Simul User: 3天后入住，住1晚
  Agent: 已为您预订上海XX酒店，价格480元...

[Verify 阶段]
✓ 创建了酒店订单 (30分)
✓ 酒店城市正确 (25分)
✓ 价格在预算范围内 (25分)
✓ 入住日期正确 (20分)

最终得分: 100/100
```

## API 接口文档

系统提供四个 REST API 接口供外部 AI Agent 调用：

### 1. 获取任务列表

```http
GET /api/tasks
```

**响应示例：**
```json
{
  "validators": [
    {
      "id": "v201_hotel_booking_multi_turn_validator",
      "task_id": "0b2d6f73-3d61-4dab-84da-4de740b906a3",
      "title": "酒店预订多轮对话",
      "description": "验证 Agent 是否能通过多轮对话获取完整信息并成功预订酒店",
      "is_multi_turn": true
    },
    {
      "id": "v001_flight_booking_validator",
      "task_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "title": "单程机票预订",
      "description": "验证 Agent 是否能正确预订单程机票",
      "is_multi_turn": false
    }
  ],
  "count": 2
}
```

**字段说明：**
- `is_multi_turn`: 布尔值，标识是否为多轮对话验证器
  - `true`: 支持多轮对话，需要使用 `POST /api/dialog/message` 接口
  - `false`: 传统验证器，直接调用业务 API 完成任务后验证

### 2. 启动训练会话

```http
POST /api/tasks/:id/start
Content-Type: application/json

{
  "agent_name": "MyAIAgent",
  "agent_version": "1.0.0"
}
```

**响应示例：**
```json
{
  "session_id": "sess_abc123",
  "task_id": "v201_hotel_booking_multi_turn_validator",
  "is_multi_turn": true,
  "task": {
    "task": "帮我订一个上海的酒店，预算500元左右",
    "data_version": "dv_xyz789",
    "user_id": 123,
    "context": {
      "session_token": "token_xxx"
    }
  }
}
```

**重要参数说明：**
- `session_id`: 本次会话的唯一标识，用于后续所有 API 调用
- `is_multi_turn`: 是否为多轮对话验证器（`true` 需要使用 `POST /api/dialog/message`）
- `task.data_version`: RLS 数据隔离版本号，Agent 创建的所有数据必须带上此字段
- `task.task`: 模拟用户的初始请求
- `task.context`: 包含 user_id、session_token 等用于 Agent 调用业务 API

### 3. 多轮对话（Agent 发送消息获取 Simul User 回复）

**这是关键接口！** Agent 每次发送消息后，调用此接口获取 Simul User 的回复。

```http
POST /api/dialog/message
Content-Type: application/json

{
  "session_id": "sess_abc123",
  "agent_message": "好的，请问您的入住日期和退房日期是？"
}
```

**响应示例：**
```json
{
  "simul_user_message": "3天后入住，住1晚",
  "should_continue": true,
  "turn_number": 2,
  "metadata": {
    "total_messages": 4,
    "max_turns": 10
  }
}
```

**参数说明：**
- `session_id`: 会话 ID（从 `POST /api/tasks/:id/start` 获取）
- `agent_message`: Agent 的消息（提问、确认、通知等）

**响应字段：**
- `simul_user_message`: Simul User 的回复（由 LLM 动态生成）
- `should_continue`: 是否应继续对话（`false` 表示任务完成或达到最大轮数）
- `turn_number`: 当前对话轮数

**使用场景：**
1. Agent 需要更多信息时，发送提问消息
2. Agent 完成操作后，发送确认消息
3. Agent 需要用户确认敏感操作时（如付款）

**重要：**
- 每次 Agent 发送消息后，**必须**调用此接口获取用户回复
- 当 `should_continue: false` 时，应结束对话并调用 `POST /api/verify/run` 验证
- Simul User 的回复由 LLM 动态生成，不是预定义脚本

### 4. 提交验证请求

Agent 完成任务后调用此接口进行验证：

```http
POST /api/verify/run
Content-Type: application/json

{
  "session_id": "sess_abc123",
  "agent_response": "已为您成功预订上海希尔顿酒店，入住日期为2024-02-05，价格480元"
}
```

**响应示例：**
```json
{
  "success": true,
  "score": 100,
  "max_score": 100,
  "assertions": [
    {
      "description": "创建了酒店订单",
      "passed": true,
      "weight": 30,
      "error": null
    },
    {
      "description": "酒店城市正确",
      "passed": true,
      "weight": 25,
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
      "message": "好的，请问您的入住日期和退房日期是？"
    }
  ]
}
```

## Agent 集成指南

### 对话流程

1. **获取任务**：调用 `GET /api/tasks` 获取可用任务列表
2. **启动会话**：调用 `POST /api/tasks/:id/start` 获取 `session_id` 和初始消息
3. **多轮对话**：
   - Agent 处理用户消息，调用业务 API（订酒店、买票等）
   - 创建业务数据时**必须**带上 `data_version` 字段
   - Agent 发送消息后，调用 `POST /api/dialog/message` 获取 Simul User 回复
   - 重复直到 `should_continue: false` 或任务完成
4. **提交验证**：调用 `POST /api/verify/run` 获取评分和详细反馈

### 数据隔离规则（重要）

**所有业务数据创建时必须包含 `data_version` 字段：**

```ruby
# 正确示例
HotelBooking.create!(
  hotel_id: hotel.id,
  user_id: current_user.id,
  data_version: params[:data_version],  # ✅ 必须包含
  check_in_date: check_in_date,
  check_out_date: check_out_date
)

# 错误示例
HotelBooking.create!(
  hotel_id: hotel.id,
  user_id: current_user.id,
  # ❌ 缺少 data_version 字段
  check_in_date: check_in_date
)
```

**为什么需要 data_version？**
- 确保测试数据与生产数据隔离
- 支持并发测试多个 Agent
- 测试结束后自动清理数据

## 已实现验证器列表

### v201: 酒店预订多轮对话

**任务描述：** 用户提供模糊的酒店预订请求，Agent 需通过提问获取完整信息并完成预订

**初始消息：** "帮我订一个上海的酒店，预算500元左右"

**验证指标：**
1. 创建了酒店订单（30分）
2. 酒店城市正确（25分）
3. 价格在预算范围内（25分）
4. 入住日期正确（20分）

**预期对话流程：**
- User: 帮我订一个上海的酒店，预算500元左右
- Agent: 好的，请问您的入住日期和退房日期是？（主动询问缺失信息）
- User: 3天后入住，住1晚
- Agent: 已为您预订XX酒店...

## 开发新的多轮对话验证器

### 1. 生成验证器文件

```bash
rails generate validator your_validator_name "验证器标题" "验证器描述"
```

### 2. 继承 MultiTurnBaseValidator

```ruby
module V501V550
  class V502FlightBookingMultiTurnValidator < MultiTurnBaseValidator
    self.validator_id = 'v502_flight_booking_multi_turn_validator'
    self.task_id = SecureRandom.uuid  # Auto-generated by generator
    self.title = '航班预订多轮对话'
    self.description = '验证 Agent 是否能通过多轮对话获取完整信息并成功预订航班'
    self.max_turns = 10  # 可选：自定义最大对话轮数

    # 准备测试数据
    def prepare
      @departure_city = '北京'
      @arrival_city = '上海'
      @departure_date = 7.days.from_now.to_date
      
      { 
        task: initial_task_goal,
        departure_city: @departure_city,
        arrival_city: @arrival_city,
        departure_date: @departure_date
      }
    end

    # 定义初始任务目标（模拟用户的初始请求）
    def initial_task_goal
      "我想订一张去#{@arrival_city}的机票"
    end

    # 可选：提供用户上下文信息给 Simul User
    def user_context
      {
        name: "张三",
        preferences: "喜欢早班飞机",
        budget: 1000
      }
    end

    # 验证任务完成情况
    def verify
      add_assertion "创建了航班订单", weight: 30 do
        all_bookings = FlightBooking
          .joins(:flight)
          .where(data_version: @data_version)
          .order(created_at: :desc)
          .to_a
        
        expect(all_bookings).not_to be_empty, "未找到任何航班订单"
        @flight_bookings = all_bookings
      end

      return if @flight_bookings.nil? || @flight_bookings.empty?

      add_assertion "出发城市正确", weight: 25 do
        @flight_bookings.each do |booking|
          expect(booking.flight.departure_city).to eq(@departure_city),
            "出发城市错误。期望: #{@departure_city}, 实际: #{booking.flight.departure_city}"
        end
      end

      add_assertion "到达城市正确", weight: 25 do
        @flight_bookings.each do |booking|
          expect(booking.flight.arrival_city).to eq(@arrival_city),
            "到达城市错误。期望: #{@arrival_city}, 实际: #{booking.flight.arrival_city}"
        end
      end

      add_assertion "出发日期正确", weight: 20 do
        @flight_bookings.each do |booking|
          expect(booking.flight.departure_date).to eq(@departure_date),
            "出发日期错误。期望: #{@departure_date}, 实际: #{booking.flight.departure_date}"
        end
      end
    end
  end
end
```

### 3. 测试验证器

```bash
rake validator:simulate_single[v502_flight_booking_multi_turn_validator]
```

## 高级功能

### 自定义对话轮数

默认最大对话轮数为 10，可以通过设置 `max_turns` 自定义：

```ruby
class MyValidator < MultiTurnBaseValidator
  self.max_turns = 5  # 限制最多 5 轮对话
end
```

### 提供用户上下文

重写 `user_context` 方法为 Simul User 提供额外信息：

```ruby
def user_context
  {
    name: "李四",
    age: 30,
    location: "北京",
    preferences: "喜欢经济型酒店",
    constraints: "对价格敏感"
  }
end
```

Simul User 会根据这些信息生成更符合角色设定的回复。

### 处理 Agent 响应（可选）

如果需要在验证器中直接处理 Agent 响应（用于本地测试），可以重写 `process_user_message` 方法：

```ruby
def process_user_message(user_message)
  # 这里可以调用你的 Agent API 或实现简单的规则引擎
  # 返回 Agent 的响应消息
  
  if user_message.include?("订酒店")
    "好的，请问您的入住日期和退房日期是？"
  elsif user_message =~ /(\d+)天后/
    days = $1.to_i
    check_in = days.days.from_now.to_date
    # 创建订单逻辑...
    "已为您预订成功"
  else
    "抱歉，我没有理解您的需求"
  end
end
```

## 常见问题

### Q: Simul User 如何生成回复？

A: Simul User 使用 LLM 根据对话历史、任务目标和用户上下文动态生成回复。它会模拟真实用户的行为模式：
- 初始请求可能不完整（如"订个酒店"）
- 回答问题时逐步提供信息
- 对敏感操作请求确认
- 表达不满或质疑不合理的建议

### Q: 如何调试对话内容？

A: 使用 `VERBOSE=1` 环境变量查看详细日志：

```bash
VERBOSE=1 rake validator:simulate_single[v201_hotel_booking_multi_turn_validator]
```

或查询数据库中的对话记录：

```ruby
rails runner "
  execution = ValidatorExecution.last
  DialogTurn.where(validator_execution_id: execution.id).order(:turn_number).each do |turn|
    puts \"第\#{turn.turn_number}轮 - \#{turn.role}: \#{turn.message}\"
  end
"
```

### Q: 测试数据会影响生产环境吗？

A: 不会。所有测试数据都带有 `data_version` 标识，通过 PostgreSQL RLS 实现数据隔离，测试结束后会自动清理。

### Q: 如何模拟不同类型的用户？

A: 通过 `user_context` 方法提供不同的用户画像：

```ruby
# 预算敏感型用户
def user_context
  { preferences: "价格优先", budget: 300, constraints: "只要便宜" }
end

# 品质追求型用户
def user_context
  { preferences: "品质优先", budget: 2000, constraints: "要五星级酒店" }
end
```

### Q: 验证失败如何排查？

A: 按以下步骤排查：

1. 检查 Agent 是否创建了业务数据
2. 确认业务数据包含正确的 `data_version`
3. 查看对话历史是否符合预期
4. 检查验证断言的具体错误信息
5. 使用 `rails runner` 手动查询数据库

```bash
rails runner "
  dv = ValidatorExecution.last.data_version
  puts HotelBooking.where(data_version: dv).count
  puts HotelBooking.where(data_version: dv).first.inspect
"
```

## 性能优化

### 并发测试

系统使用 `VERIFY_LOCK` 互斥锁确保同时只有一个验证在运行，避免数据冲突。

### 数据清理

测试结束后自动清理测试数据。如需手动清理：

```ruby
rails runner "
  data_version = 'dv_xyz789'
  HotelBooking.where(data_version: data_version).delete_all
  DialogTurn.where(data_version: data_version).delete_all
"
```

## 技术架构

### 核心组件

1. **MultiTurnBaseValidator**: 多轮对话验证器基类
2. **AiSimulUserService**: AI 驱动的用户模拟服务
3. **DialogTurn**: 对话历史记录模型
4. **LlmService**: LLM API 调用服务
5. **API Controllers**: REST API 接口

### 数据流

```
验证器启动
    ↓
prepare() - 准备测试数据
    ↓
simulate() - 执行多轮对话
    ↓
Simul User 生成初始消息 (LLM)
    ↓
Agent 处理消息并回复
    ↓
Simul User 生成下一条消息 (LLM)
    ↓
重复直到任务完成或达到最大轮数
    ↓
verify() - 验证任务完成情况
    ↓
返回评分和详细报告
```

## 相关文档

- [验证器设计文档](./VALIDATOR_DESIGN.md)
- [验证器生成器使用指南](./VALIDATOR_GENERATOR.md)
- [API 文档](./API.md)

## 联系支持

如有问题或建议，请联系开发团队或提交 Issue。
