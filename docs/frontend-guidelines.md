# 前端布局规范（Mobile-First App）

rlbox 是移动优先的应用模板，所有派生项目都通过 `apk/` 目录的 Android TWA 套壳分发。
布局决策必须以移动端体验为第一优先级。

## 布局原则

### ❌ 不要做的事

**永远不要在用户侧页面容器上使用 `max-w-*` 限制宽度！**

错误示例：
```html
<!-- ❌ 错误：移动端没问题，但思维方式错误；桌面端会显示在中间一小块 -->
<div class="max-w-5xl mx-auto">
  ...
</div>

<!-- ❌ 错误：整个页面内容被挤在中间 -->
<div class="max-w-md mx-auto px-4">
  ...
</div>
```

### ✅ 正确做法

**用户侧页面全屏显示，利用所有可用空间：**

```html
<!-- ✅ 正确：全屏 + padding -->
<div class="min-h-screen bg-surface">
  <div class="px-4 py-6">
    ...
  </div>
</div>
```

### `max-w-*` 的合法使用场景

| 场景 | 示例 | 说明 |
|------|------|------|
| 文本可读性 | `<p class="max-w-prose">` | 长段落限制行宽，提升阅读体验 |
| 登录/注册卡片 | `<div class="card max-w-md">` | 表单居中显示是合理的 |
| Admin 后台 | `<div class="lg:max-w-7xl lg:mx-auto">` | 后台可以用，加断点前缀 |
| Modal 弹窗 | `<div class="max-w-lg mx-auto">` | 弹窗本来就不该全屏 |

### 响应式布局（如果需要在大屏上限制）

如果确实需要在大屏幕限制宽度（比如 iPad 横屏），使用断点前缀：

```html
<!-- 移动端全屏，大屏幕才限制 -->
<div class="w-full lg:max-w-5xl lg:mx-auto">
  ...
</div>
```

## 容器规范

### 用户侧页面

```html
<div class="min-h-screen bg-surface">
  <!-- 顶部导航 -->
  <header class="sticky top-0 z-40 bg-surface-elevated px-4 py-3">
    ...
  </header>

  <!-- 主内容 -->
  <main class="px-4 py-6">
    ...
  </main>

  <!-- 底部导航（如果有） -->
  <nav class="fixed bottom-0 left-0 right-0 z-50 bg-surface-elevated">
    ...
  </nav>
</div>
```

### Admin 后台

```html
<!-- Admin 可以使用 max-w -->
<div class="w-full lg:max-w-7xl lg:mx-auto px-4">
  ...
</div>
```

## 内边距规范

- 页面主容器：`px-4`（16px，移动端标准）
- 卡片内容：`p-4` 或 `p-6`
- 列表项：`px-4 py-3`
- Section 间距：`py-8` 或 `py-12`

## 固定元素定位

- 顶部导航：`sticky top-0 z-40`
- 底部导航：`fixed bottom-0 left-0 right-0 z-50`
- 悬浮按钮：`fixed bottom-20 right-4 z-50`（避开底部导航）

## 颜色使用

**永远使用设计系统语义化 token，不要硬编码颜色！**

- `bg-surface` — 主背景
- `bg-surface-elevated` — 卡片/导航背景
- `text-primary` — 主文本
- `text-secondary` — 次要文本
- `text-muted` — 提示文本

## 字体大小

- 页面标题：`text-xl` 或 `text-2xl`
- 区块标题：`text-lg`
- 正文：`text-base`
- 副文本：`text-sm`
- 标签/时间戳：`text-xs`
