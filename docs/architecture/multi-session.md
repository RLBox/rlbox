---
topic: multi-session
updated_at: 2026-04-28
status: current
related:
  - validator-system.md
  - data-version.md
supersedes:
  - ../archive/MULTI_SESSION_IMPLEMENTATION.md
source_files:
  - app/middleware/validator_session_binder.rb
  - app/controllers/application_controller.rb
  - app/models/validator_execution.rb
  - config/application.rb
---

# 多会话并发（Multi-Session）

## 1. 解决什么问题

一个浏览器 / 一个用户账号，**同时跑多个 Validator 训练会话**，每个会话看到不同的数据版本，互不干扰。

典型场景：
- 同一个 demo 账号，在三个浏览器 tab 里分别运行 V001、V010、V020
- 云手机农场：N 台云机用同一个 demo 用户并行跑 N 个训练任务
- 人类标注员需要同时看多个正在执行的 validator 状态

单会话模式下这些都会互相覆盖数据。

---

## 2. 核心设计：独立 Cookie + URL 参数

```
       ┌──────────────────────────────────────────────────────────────┐
       │  Tab 1                           Tab 2                        │
       │  URL: /?session_id=abc           URL: /?session_id=xyz       │
       └────────────┬─────────────────────────────┬──────────────────┘
                    │                             │
                    ▼                             ▼
       ┌──────────────────────────────────────────────────────────────┐
       │              ValidatorSessionBinder (Rack middleware)         │
       │  - 读 query string 里的 session_id                             │
       │  - 写独立 cookie: validator_session_id=<session_id>            │
       │  - 每个 tab URL 不同 → 每次请求都用 URL 参数覆写 cookie         │
       └────────────────────────────┬─────────────────────────────────┘
                                    │
                                    ▼
       ┌──────────────────────────────────────────────────────────────┐
       │       ApplicationController#restore_validator_context         │
       │  1. 读 cookie validator_session_id                            │
       │  2. 查 ValidatorExecution                                     │
       │  3. SET app.data_version = execution.data_version             │
       └────────────────────────────┬─────────────────────────────────┘
                                    │
                                    ▼
       ┌──────────────────────────────────────────────────────────────┐
       │    DataVersionable scope 自动过滤：                            │
       │    data_version IN ('0', <当前 session 的 data_version>)       │
       └──────────────────────────────────────────────────────────────┘
```

**关键 insight**：为什么不用 Rails session？因为 Rails session 存在同一个 cookie 里，同一浏览器所有 tab **共享**。Tab A 打开 `?session_id=abc` 会覆盖 Tab B 的 `session_id=xyz`。

真正实现 tab 独立的方式是：**每个 tab 的请求 URL 都带自己的 `?session_id=xxx`**，middleware 在每次请求时都**用 URL 参数覆写 cookie**。结果：cookie 只是个兜底/快照，真相源永远是 URL。

---

## 3. 关键组件

### 3.1 `ValidatorSessionBinder` middleware

位置：`app/middleware/validator_session_binder.rb`
注册：`config/application.rb` 用 `config.middleware.use ValidatorSessionBinder`

职责：
1. 从 `query_string` 里提取 `session_id`
2. 如果存在，把它写到 `validator_session_id` cookie（httponly, 24h 过期）

### 3.2 `ApplicationController#restore_validator_context`

`before_action`，负责：
1. 读 `validator_session_id` cookie
2. 查 `ValidatorExecution.find_by(session_id: ...)`
3. 如果找到，`SET SESSION app.data_version = execution.data_version`

没有 session_id（普通用户浏览）→ 用 baseline（`data_version = '0'`）。

---

## 4. 使用方式

从 prepare API 拿到 `session_id`：

```json
POST /api/validators/execute_prepare
→ {
    "session_id": "abc123",
    "task": "将「有机苹果」加入购物车",
    ...
  }
```

然后在所有后续请求的 URL 里附带：

```
GET  /products?session_id=abc123
POST /cart_items?session_id=abc123
GET  /api/validators/execute_verify?session_id=abc123
```

---

## 5. 并发限制与注意事项

- **同一 `session_id` 不要在多个真实并发请求里用**：PostgreSQL 的 `SET SESSION` 是连接级别的，Rails 连接池可能分配到不同的连接
- `bin/dev` 模式（Puma 单线程）下并发问题不严重；生产多进程模式下每个进程有自己的连接池，问题更小
- 真正的大规模并发场景（N 台云机同时跑）：每台机器用独立 `session_id`，互相之间不共享 cookie

---

## 6. References / 历史参考

老文档：[`archive/MULTI_SESSION_IMPLEMENTATION.md`](../archive/MULTI_SESSION_IMPLEMENTATION.md)（已归档）
- [validator-system.md](validator-system.md) — execute_prepare / execute_verify 生命周期
- [data-version.md](data-version.md) — SET SESSION app.data_version 机制
