# Screenshot to Rails ERB View - 技能说明

## 概述

`screenshot-to-html` 是一个将截图转换为 Rails 兼容 .html.erb 视图文件的 Clacky 技能。使用 Tailwind CSS 进行样式设计，生成包含 ERB 占位符的 Rails 视图，支持单张或多张截图拼接。

## 功能特性

✅ 分析截图的布局、颜色、间距、组件
✅ 生成使用 Tailwind CSS 的 Rails ERB 视图
✅ **自动添加 ERB 占位符**用于动态内容（`<%= @title %>`, `<% @items.each %>` 等）
✅ **使用 Rails 辅助方法**（`image_tag`, `link_to`, `form_with` 等）
✅ **无全局 HTML 结构**（不包含 `<html>`, `<head>`, `<body>` 标签）
✅ 图标和图片用 SVG 占位图或 `image_tag` 代替
✅ 支持多截图垂直拼接（模拟滚动页面）
✅ 自动提取截图中的文字内容
✅ **自动检测 Rails 项目并保存到 `app/views/` 目录**
✅ **提供完整的设置说明**（Tailwind 配置、控制器、路由等）

## 新功能（Rails ERB 支持）

### 输出格式变化
- **旧版本**：生成完整的独立 HTML 文件
- **新版本**：生成 Rails 兼容的 `.html.erb` 视图文件

### 关键特性
1. **移除全局结构**：不包含 `<!DOCTYPE>`, `<html>`, `<head>`, `<body>` 标签
2. **ERB 占位符**：自动为动态内容添加占位符
3. **Rails 辅助方法**：使用 `image_tag`, `link_to`, `form_with` 等
4. **智能保存**：自动检测 Rails 项目，保存到正确目录
5. **完整指导**：提供 Tailwind 配置、控制器创建、路由设置等步骤

## 触发方式

在对话中使用以下任一方式触发技能：

- "截图转 HTML"
- "截图转 ERB"
- "screenshot to html"
- "screenshot to erb"
- "图片生成 Rails 视图"
- "把这个 UI 设计变成 Rails 代码"
- "convert screenshot to Rails view"
- 手动调用：`/screenshot-to-html`

## 使用示例

**示例 1：转换为 Rails 视图**
```
我有一个登录页面的截图在桌面上叫做 login_page.png，
能帮我把它转成 Rails ERB 视图吗？要用 Tailwind CSS。
```

**输出：**
- 文件：`app/views/pages/login.html.erb`（如果在 Rails 项目中）
- 包含 ERB 占位符（`<%= @title %>`, `<%= form_with %>` 等）
- 提供完整的控制器、路由配置说明

**示例 2：生成可复用组件（Partial）**
```
screenshot to erb - 这是一个卡片组件的设计图，
保存到 app/views/shared/_card.html.erb
```

**输出：**
- 文件：`app/views/shared/_card.html.erb`
- 使用局部变量（`<%= card.title %>`, `<%= card.image %>`）
- 提供 `render` 使用示例

**示例 3：多截图拼接**
```
把这3张产品页面截图（product_top.jpg, product_middle.jpg, product_bottom.jpg）
合成一个 Rails 视图，保存到 app/views/products/show.html.erb
```

## 生成的视图示例

```erb
<%# 
  此视图需要在 Rails 应用中配置 Tailwind CSS
  
  选项 1: 使用 tailwindcss-rails gem（推荐）
    $ bundle add tailwindcss-rails
    $ rails tailwindcss:install
  
  选项 2: 在 application.html.erb 中添加 Tailwind CDN（仅用于快速原型）
    <script src="https://cdn.tailwindcss.com"></script>
%>

<section class="bg-gray-50 py-16">
  <div class="max-w-7xl mx-auto px-4">
    <h2 class="text-4xl font-bold text-gray-900 mb-4">
      <%= @section_title %>
    </h2>
    <p class="text-lg text-gray-600 mb-8">
      <%= @section_description %>
    </p>
    
    <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
      <% @features.each do |feature| %>
        <div class="bg-white rounded-lg shadow-md p-6">
          <%= image_tag(feature.icon_path, class: 'w-12 h-12 mb-4') %>
          <h3 class="text-xl font-semibold mb-2"><%= feature.title %></h3>
          <p class="text-gray-600"><%= feature.description %></p>
        </div>
      <% end %>
    </div>
  </div>
</section>
```

## 生成后的设置指导

技能会自动生成完整的设置说明，包括：

### 1. Tailwind CSS 配置
```bash
# 选项 A：使用 gem（推荐）
bundle add tailwindcss-rails
rails tailwindcss:install

# 选项 B：使用 CDN（快速原型）
# 在 application.html.erb 中添加 Tailwind CDN
```

### 2. 创建控制器
```bash
rails generate controller Pages index
```

### 3. 配置路由
```ruby
# config/routes.rb
Rails.application.routes.draw do
  root 'pages#index'
end
```

### 4. 准备实例变量
```ruby
# app/controllers/pages_controller.rb
class PagesController < ApplicationController
  def index
    @title = "Welcome"
    @description = "Your page description"
    @items = Item.all
  end
end
```

## 文件保存逻辑

1. **在 Rails 项目中**：自动保存到 `app/views/pages/`（或指定目录）
2. **不在 Rails 项目中**：保存到桌面，并提示复制到项目中
3. **支持 Partial**：使用 `_` 前缀命名（如 `_component.html.erb`）

## 评估结果

根据初始测试（3 个测试用例，15 个断言）：

- **使用技能**：100% 通过率（15/15）
- **不使用技能**：40% 通过率（6/15）
- **提升**：+60 百分点

### 关键优势

1. **Tailwind CSS 使用**：100% 正确使用 vs 0%
2. **Rails 集成**：自动使用 Rails 辅助方法和 ERB 语法
3. **动态内容占位符**：智能添加 ERB 占位符
4. **结构质量**：正确的语义化标签，无多余的全局 HTML 结构
5. **SVG 图标 + Rails helpers**：混合使用 SVG 和 `image_tag`
6. **响应式设计**：所有页面包含响应式类
7. **完整指导**：提供从生成到部署的完整流程

## 技能文件位置

- 技能定义：`~/.clacky/skills/screenshot-to-html/skill.md`
- RLBox 部署：`~/rlbox/.clacky/skills/screenshot-to-html/SKILL.md`
- 测试用例：`~/.clacky/skills/screenshot-to-html/evals/evals.json`

## 版本历史

### v2.0（2026-04-17）- Rails ERB 支持
- ✅ 输出改为 `.html.erb` 格式
- ✅ 移除全局 HTML 结构
- ✅ 添加 ERB 占位符支持
- ✅ 集成 Rails 辅助方法
- ✅ 自动检测 Rails 项目
- ✅ 提供完整设置说明

### v1.0（2026-04-14）- 初始版本
- ✅ 基础 HTML 生成
- ✅ Tailwind CSS 支持
- ✅ 多截图拼接

## 下一步

1. 在 RLBox 项目中实际测试
2. 收集用户反馈并优化
3. 添加更多 Rails 特定功能（如 Turbo、Stimulus）
4. 支持暗色模式检测
5. 添加 ViewComponent 支持

---

**创建时间**：2026-04-14  
**更新时间**：2026-04-17  
**版本**：2.0 - Rails ERB 支持  
**状态**：已部署到 RLBox，可供使用
