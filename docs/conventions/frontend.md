---
topic: frontend
updated_at: 2026-04-28
related:
  - conventions/validator-writing.md
source_files:
  - app/javascript/controllers/
  - app/views/
supersedes: ../archive/frontend-guidelines.md
---

# 🎨 前端开发规范（Stimulus + Turbo + TypeScript）

> 本页是 `CLAUDE.md` 「FRONTEND DEVELOPMENT RULES」章节的完整版。
> CLAUDE.md 只保留硬规则摘要，细则在此。

## 1. 技术栈基线

- **Stimulus** — 所有交互；**禁止** inline JS / jQuery / 裸 JS
- **Turbo Stream** — 响应式 DOM 更新（**不用** `<turbo-frame>`，**不用** `turbo_stream_from`）
- **TypeScript** — controller 一律 `.ts`
- **Tailwind v3** — 所有样式；禁止自定义 CSS 文件除非必要
- **Lucide icons** — `<%= lucide_icon "icon-name", class: "w-5 h-5" %>`；**禁止 emoji**

## 2. 布局规范（移动优先 App）

**rlbox 是移动优先的应用模板**，所有派生项目都通过 `apk/` 目录的 Android TWA 套壳分发。布局决策必须以移动端体验为第一优先级。

### ❌ 永远不要在用户侧页面容器上使用 `max-w-*`！

```html
<!-- ❌ 错误：内容被挤在中间一小块 -->
<div class="max-w-5xl mx-auto">...</div>

<!-- ✅ 正确：全屏 + padding -->
<div class="min-h-screen bg-surface">
  <div class="px-4 py-6">...</div>
</div>
```

**允许** `max-w-*` 的地方：
- Admin 后台页面（`admin/` views）
- Modal/card 浮层（`max-w-md` on login card）
- 纯文字段落的可读性控制（`<p class="max-w-prose">`）

## 3. Stimulus Controller 规则

### 3.1 读 header 注释，不要猜

每个 controller 顶部有 target / value / action 说明。用前先读：

```bash
head -30 app/javascript/controllers/xxx_controller.ts
```

### 3.2 View 与 controller 的 class 同步

如果 view 用 `class="text-gray-900 text-gray-500"` 表示 active/inactive，controller 的 `toggle` 方法必须精确操作这两个 class，不能留旧的。

**流程**：
- 改 view class 前 → `grep -rn "targetName" app/javascript/controllers/`，确认无旧 class 引用残留
- 改 controller 逻辑后 → 打开对应 view 确认 class 名字一致
- 改完任何 `.ts` 文件 → `npm run build` 重生成 JS bundle

### 3.3 架构校验

`rake test` 会跑三个校验器（**违反 = 真实错误**，不是误报）：

| 校验器 | 检查什么 |
|---|---|
| `spec/javascript/stimulus_validation_spec.rb` | Stimulus controller ↔ view target/action 一致 |
| `spec/javascript/turbo_architecture_validation_spec.rb` | Turbo Stream 模式合规 |
| `spec/javascript/project_conventions_validation_spec.rb` | 命名 / 文件位置 / 入口规范 |

## 4. Turbo Stream

### 4.1 定义

> **Turbo Stream = 响应格式**（`render xxx.turbo_stream.erb` 做局部 DOM 更新）。
> **不是** view 里的 `turbo_stream_from`，**不是** `<turbo-frame>` 包裹。

### 4.2 前端规则

```typescript
// ❌ 禁止
fetch('/endpoint', ...)                    // 绕过 Turbo Drive，要手动更新 DOM
event.preventDefault(); form.requestSubmit()  // preventDefault 会直接阻断提交

// ✅ Stimulus 只做 UI（toggle / show-hide）
// 数据提交交给 form + Turbo
```

### 4.3 后端规则

- **默认** → 渲染 HTML 视图
- **局部更新** → 建 `action.turbo_stream.erb` 模板
- ❌ 禁用 `respond_to` + `format.html/json/xml`（多余分支）
- ❌ 禁用 `render json:`（JSON 只在 `app/controllers/api/` 命名空间允许）
- ❌ 禁用 `head :ok`（前端无法判断该做什么 UI）

## 5. ActionCable Channel 模式

### 调用图

```
前端 this.perform('methodName', {params})
   ↓
Channel#methodName(data)   ← 方法名一致
   ↓
ActionCable.server.broadcast(channel, {type: 'event-name', data: {}})
   ↓
前端 handleEventName(data)   ← 按 type 路由
```

> **不要手动解析 message**。type-based routing 已自动处理。

### 生成器

```bash
rails generate channel xxx [action1] [action2] [--auth]
```
同时生成 `xxx_channel.rb`（WebSocket）+ `xxx_controller.ts`（**同一个 controller 处理 WS + UI**）。

## 6. 视觉规则

| ✅ 必须 | ❌ 禁止 |
|---|---|
| 用设计系统 token（`bg-primary`、`text-muted`） | 直写 `bg-white` / `text-black` |
| HSL 颜色定义在 `application.css` / `tailwind.config.js` | RGB 包进 `hsl()` |
| `application.css` 已有组件（`.btn-*` / `.card-*` / `.alert-*` / `.badge-*` / `.form-*`） | 自造重复组件 |
| 自定义组件放 `application.css` 底部 | 修改 `components.css` |
| `group` 只写在 HTML | `@apply group` 在 CSS（坏行为） |
| Lucide icon | emoji |

## 7. 生成器速查

| 目标 | 命令 | 备注 |
|---|---|---|
| 用户登录系统 | `rails g authentication [--navbar-style=STYLE]` | 确保无 User 再跑 |
| 假支付 | `rails g stripe_pay [--auth]` | 生成 Payment（不是 Order） |
| LLM 接入 | `rails g llm` | 配 `LLM_BASE_URL/KEY/MODEL` |
| 新 controller | `rails g controller xxx [--auth] [--single]` | — |
| 新 channel | `rails g channel xxx [--auth]` | — |
| 新 Stimulus controller | `rails g stimulus_controller xxx` | — |
| 管理后台 CRUD | `rails g admin_crud xxx` | 模型先建好 |
| PWA | `rails g pwa` | 自动读 appname + 主题色 |

## 8. 永不修改的文件

- `app/views/layouts/application.html.erb`
- `app/controllers/admin/base_controller.rb`
- `app/javascript/controllers/clipboard_controller.ts`
- `app/javascript/controllers/dropdown_controller.ts`
- `app/javascript/controllers/theme_controller.ts`

## 9. 其他硬规则

- `FriendlyId` 已装；用户端 slug → `friendly_id :title, use: :slugged`；后台/API 用 raw ID
- **禁止 nested form**
- 图片：`ImageSeedHelper.random_image_from_category(:xxx)`；禁用直链 Unsplash URL
- 图片处理：`ImageProcessing::Vips`；禁用 MiniMagick / 直接 Vips::Image

## 10. 延伸阅读

- [validator-writing.md](validator-writing.md) — 数据层写法
- CLAUDE.md 根目录 → MANDATORY PROJECT WORKFLOW（初次上手 Step 1-5）
