# 多会话 ID 实现方案文档

## 📖 目录

- [概述](#概述)
- [问题背景](#问题背景)
- [解决方案](#解决方案)
- [技术实现](#技术实现)
- [测试流程](#测试流程)
- [数据隔离机制](#数据隔离机制)
- [API 规范](#api-规范)

---

## 概述

本文档描述了验证器系统的**多会话 ID 支持**实现方案。该方案允许多个 AI Agent 同时测试同一任务，每个 Agent 拥有独立的会话 ID（session_id），数据完全隔离，互不干扰。

### 核心特性

- ✅ **多会话并发**：支持同一任务启动多个会话 ID
- ✅ **显式会话绑定**：APK 通过 Deeplink 传递 session_id，明确指定操作的会话
- ✅ **数据完全隔离**：基于 PostgreSQL RLS + data_version 机制，不同会话数据互不可见
- ✅ **向下兼容**：未传递 session_id 时，自动使用最新活跃会话（单会话模式）
- ✅ **零 APK 修改**：现有 APK 已支持 Deeplink 参数传递

---

## 问题背景

### 原始设计（单会话模式）

在原始设计中，验证器系统只支持**单会话模式**：

```ruby
# app/models/validator_execution.rb (原始代码)
def activate!
  transaction do
    # 取消同一用户的其他活跃会话（互斥）
    ValidatorExecution.where(user_id: user_id, is_active: true)
                      .where.not(id: id)
                      .update_all(is_active: false)
    
    # 激活当前会话
    update!(is_active: true)
  end
end
```

**问题**：
- ❌ 同一用户只能有一个活跃会话
- ❌ 创建新会话会自动取消旧会话
- ❌ 无法支持多个 AI Agent 并行测试

### 初次多会话尝试的缺陷

移除会话互斥后，遇到新问题：

```ruby
# app/controllers/application_controller.rb (修改后，存在问题)
def restore_validator_context
  # 自动选择"最新"活跃会话
  execution = ValidatorExecution.active_for_user(current_user.id).first
  # ...
end
```

**致命缺陷**：
- ❌ 用户/AI 无法选择操作哪个会话
- ❌ 系统总是使用"最新"会话，违背多会话初衷
- ❌ 多个云手机实例无法绑定到各自的会话

---

## 解决方案

### 核心思路

**通过 URL 参数显式绑定 session_id，确保用户明确知道操作的会话。**

### 实现流程

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. 后端创建会话                                                  │
│    POST /api/tasks/:id/start                                    │
│    → 返回: {"session_id": "abc-123", "task": {...}}            │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 2. ADB 启动 APK 并传递 session_id                               │
│    adb shell am start -a android.intent.action.VIEW \           │
│      -d "ai.clacky.trip01://?session_id=abc-123"                │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 3. APK 读取 session_id 并附加到 URL                             │
│    http://192.168.1.10:5010/?session_id=abc-123                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 4. ValidatorSessionBinder 中间件拦截请求                        │
│    提取 URL 参数: session_id=abc-123                            │
│    存储到 Rails session: session[:validator_execution_id]       │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 5. ApplicationController#restore_validator_context              │
│    优先读取: session[:validator_execution_id]                   │
│    设置 PostgreSQL: SET SESSION app.data_version = 'abc-123'    │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 6. AI 操作（所有数据自动关联到 session_id）                     │
│    创建订单 → data_version 自动设置为 'abc-123'                 │
│    查询数据 → RLS 自动过滤，只返回基线 + 'abc-123' 的数据       │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 7. 验证                                                          │
│    POST /api/verify/run                                         │
│    Body: {"task_id": "...", "session_id": "abc-123"}            │
│    → 验证 session_id=abc-123 对应的数据                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## 技术实现

### 1. 中间件：ValidatorSessionBinder

**文件**：`app/middleware/validator_session_binder.rb`

**功能**：从 URL 参数提取 `session_id`，存储到 Rails session

```ruby
class ValidatorSessionBinder
  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)
    
    # 从 URL 参数提取 session_id
    if request.params['session_id'].present?
      session_id = request.params['session_id']
      
      # 存储到 Rails session（持久化到 cookie）
      request.session[:validator_execution_id] = session_id
      
      Rails.logger.info "[ValidatorSessionBinder] Bound session_id=#{session_id}"
    end
    
    @app.call(env)
  end
end
```

**注册中间件**：`config/application.rb`

```ruby
require_relative '../app/middleware/validator_session_binder'

module Myapp
  class Application < Rails::Application
    # ...
    config.middleware.use ValidatorSessionBinder
  end
end
```

---

### 2. ApplicationController 修改

**文件**：`app/controllers/application_controller.rb`

**功能**：优先使用绑定的 session_id，回退到最新活跃会话

```ruby
def restore_validator_context
  return unless user_signed_in?
  
  begin
    execution = nil
    
    # 优先级 1: 从 Rails session 读取绑定的会话 ID（APK Deeplink 传参）
    if session[:validator_execution_id].present?
      execution = ValidatorExecution.find_by(
        execution_id: session[:validator_execution_id],
        user_id: current_user.id
      )
      
      if execution
        Rails.logger.info "[Validator Context] Using bound session: #{execution.execution_id}"
      else
        Rails.logger.warn "[Validator Context] Bound session not found, falling back"
        session.delete(:validator_execution_id)  # 清理无效 session_id
      end
    end
    
    # 优先级 2: 查找最新活跃会话（兼容旧行为）
    execution ||= ValidatorExecution.active_for_user(current_user.id).first
    
    return unless execution
    
    # 设置 PostgreSQL 会话变量
    data_version = execution.data_version
    ActiveRecord::Base.connection.execute("SET SESSION app.data_version = '#{data_version}'")
    
    Rails.logger.debug "[Validator Context] Restored data_version=#{data_version}"
  rescue StandardError => e
    Rails.logger.error "[Validator Context] Failed: #{e.message}"
  end
end
```

---

### 3. ValidatorExecution 模型修改

**文件**：`app/models/validator_execution.rb`

**修改**：移除会话互斥逻辑，允许多会话并存

```ruby
# 设置为活跃状态（允许同一用户拥有多个活跃会话）
def activate!
  # 直接激活当前会话，不取消其他会话
  update!(is_active: true)
end

# 类方法：获取用户的活跃验证会话列表（支持多个并发会话）
def self.active_for_user(user_id)
  active.for_user(user_id).order(created_at: :desc)
end
```

---

## 测试流程

### 单会话测试

```bash
# 1. 创建会话
response=$(curl -s -X POST http://192.168.1.10:5010/api/tasks/book_flight_sz_to_bj/start)
session_id=$(echo "$response" | jq -r '.session_id')
echo "会话ID: $session_id"

# 2. 启动 APK（传递 session_id）
adb shell am start -a android.intent.action.VIEW \
  -d "ai.clacky.trip01://?session_id=$session_id"

# 3. AI 在云手机上操作（所有数据自动关联到 $session_id）

# 4. 验证
curl -X POST http://192.168.1.10:5010/api/verify/run \
  -H "Content-Type: application/json" \
  -d "{\"task_id\":\"book_flight_sz_to_bj\",\"session_id\":\"$session_id\"}"
```

---

### 多会话并行测试

**场景**：3 个 AI Agent 并行测试同一任务

```bash
# Agent 1（云手机设备 1）
session_1=$(curl -s -X POST .../start | jq -r '.session_id')
adb -s device_1 shell am start -d "ai.clacky.trip01://?session_id=$session_1"

# Agent 2（云手机设备 2）
session_2=$(curl -s -X POST .../start | jq -r '.session_id')
adb -s device_2 shell am start -d "ai.clacky.trip01://?session_id=$session_2"

# Agent 3（云手机设备 3）
session_3=$(curl -s -X POST .../start | jq -r '.session_id')
adb -s device_3 shell am start -d "ai.clacky.trip01://?session_id=$session_3"

# 三个 Agent 的数据完全隔离
# - Agent 1 只能看到 data_version IN (0, session_1) 的数据
# - Agent 2 只能看到 data_version IN (0, session_2) 的数据
# - Agent 3 只能看到 data_version IN (0, session_3) 的数据
```

---

## 数据隔离机制

### PostgreSQL RLS 策略

**核心机制**：每个会话的数据通过 `data_version` 列标记，RLS 策略自动过滤查询和写入。

```sql
-- RLS 查询策略（只能看到基线 + 当前版本的数据）
CREATE POLICY "data_version_isolation_select" ON bookings
  FOR SELECT
  USING (
    data_version = 0  -- 基线数据（所有人可见）
    OR data_version::text = current_setting('app.data_version', true)  -- 当前会话数据
  );

-- RLS 写入策略（写入时自动使用当前版本）
CREATE POLICY "data_version_isolation_insert" ON bookings
  FOR INSERT
  WITH CHECK (
    data_version::text = current_setting('app.data_version', true)
  );
```

### 工作流程示例

```sql
-- Agent 1 操作（session_id = 'abc-123'）
SET SESSION app.data_version = 'abc-123';
INSERT INTO bookings (departure_city, ...) VALUES ('深圳', ...);
-- → data_version 自动设置为 'abc-123'（DataVersionable concern）

SELECT * FROM bookings;
-- → RLS 策略自动过滤：WHERE data_version IN (0, 'abc-123')
-- → 只返回基线数据 + Agent 1 的数据

-- Agent 2 操作（session_id = 'def-456'）
SET SESSION app.data_version = 'def-456';
INSERT INTO bookings (departure_city, ...) VALUES ('北京', ...);
-- → data_version 自动设置为 'def-456'

SELECT * FROM bookings;
-- → RLS 策略自动过滤：WHERE data_version IN (0, 'def-456')
-- → 只返回基线数据 + Agent 2 的数据
-- → 看不到 Agent 1 的数据！
```

---

## API 规范

### 1. 创建训练会话

**请求**：

```http
POST /api/tasks/:id/start
```

**响应**：

```json
{
  "task": {
    "instruction": "预订从深圳到北京的航班，选择最低价航班",
    "departure_city": "深圳",
    "arrival_city": "北京",
    "departure_date": "2025-02-15"
  },
  "session_id": "242dd189-9dc8-4f83-8da1-ad1c1c09fada",
  "task_id": "book_flight_sz_to_bj"
}
```

---

### 2. 验证接口

**请求**：

```http
POST /api/verify/run
Content-Type: application/json

{
  "task_id": "book_flight_sz_to_bj",
  "session_id": "242dd189-9dc8-4f83-8da1-ad1c1c09fada"
}
```

**响应（成功）**：

```json
{
  "score": 1.0,
  "reason": "验证通过",
  "execution_status": "success",
  "metadata": {
    "details": [
      {
        "child_verify_id": "step_1_订单已创建",
        "score": 1.0,
        "weight": 0.2
      },
      {
        "child_verify_id": "step_2_出发城市正确",
        "score": 1.0,
        "weight": 0.1
      },
      {
        "child_verify_id": "step_3_目的城市正确",
        "score": 1.0,
        "weight": 0.1
      },
      {
        "child_verify_id": "step_4_出发日期正确",
        "score": 1.0,
        "weight": 0.2
      },
      {
        "child_verify_id": "step_5_选择了最低价航班",
        "score": 1.0,
        "weight": 0.4
      }
    ]
  }
}
```

**响应（失败 - Agent 做错）**：

```json
{
  "score": 0.2,
  "reason": "订单已创建: 未找到订单; 选择了最低价航班: 实际价格 ¥1200.0 > 最低价 ¥800.0",
  "execution_status": "success",
  "metadata": {
    "details": [...]
  }
}
```

**响应（失败 - 系统错误）**：

```json
{
  "score": 0.0,
  "reason": "验证会话不存在或已过期: invalid-session-id",
  "execution_status": "fail"
}
```

---

## 优势总结

1. **明确的会话绑定**：用户/AI 通过 URL 参数显式指定操作的会话
2. **数据完全隔离**：基于 PostgreSQL RLS，不同会话数据互不可见
3. **支持并发测试**：多个云手机实例可同时测试同一任务
4. **向下兼容**：未传递 session_id 时，自动回退到单会话模式
5. **零 APK 修改**：现有 APK 已支持 Deeplink 传参，无需重新构建
6. **符合原始设计**：使用 `session[:validator_execution_id]`（VALIDATOR_DESIGN.md 第 70 行）

---

## 文件清单

### 新建文件

- `app/middleware/validator_session_binder.rb` - 中间件：绑定 session_id

### 修改文件

- `config/application.rb` - 注册中间件
- `app/controllers/application_controller.rb` - 优先使用绑定的 session_id
- `app/models/validator_execution.rb` - 移除会话互斥逻辑

### APK 文件

- ✅ 无需修改（已支持 Deeplink 传参）

---

**实施日期**：2025-01-28  
**版本**：v1.0
