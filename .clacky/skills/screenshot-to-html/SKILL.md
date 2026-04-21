---
name: screenshot-to-html
description: 'Convert screenshots to Rails HTML.ERB view files with Tailwind CSS. Use this skill whenever the user wants to convert a screenshot to HTML/ERB, generate a Rails view from an image, turn a UI design into Rails code, recreate a page from a screenshot, or mentions phrases like 截图转HTML, screenshot to html, 截图转ERB, screenshot to erb, 图片生成网页, 截图变网页, convert screenshot to html, or ui to html. Also trigger when the user provides image files (png, jpg, jpeg) and mentions HTML, webpage, Rails view, or code generation.'
disable-model-invocation: false
user-invocable: true
---

# Screenshot to Rails ERB View Converter

Convert screenshots into Rails-compatible .html.erb view files using Tailwind CSS.

## What This Skill Does

Analyze one or more screenshots and generate Rails-compatible .html.erb view files that recreate the visual design. The output uses Tailwind CSS utility classes, includes proper semantic HTML, uses ERB placeholders for dynamic content, and replaces images/icons with SVG placeholders or Rails helpers.

## When to Use This Skill

Trigger this skill when the user:
- Uploads a screenshot and wants it converted to Rails view
- Describes a UI design from an image and wants the ERB code
- Provides multiple screenshots from the same page (scrolled views)
- Asks to "recreate this page", "turn this into a Rails view", "code this UI as ERB"
- Uses phrases like: 截图转HTML, screenshot to html, 截图转ERB, 图片生成网页, 截图变网页, Rails view from screenshot

## Core Workflow

### Step 1: Gather Input

Ask the user to provide:
1. **Screenshot file(s)**: Path to one or more images (PNG, JPG, JPEG, WEBP)
2. **Context** (optional): What kind of page is this? Any special requirements?
3. **Target directory** (optional): Where to save the view file (e.g., `app/views/home/`, `app/views/pages/`)
4. **File name** (optional): Custom name for the view file (e.g., `index.html.erb`, `_hero_section.html.erb`)

**Defaults:**
- If no directory specified: `app/views/pages/`
- If no filename specified: `_component.html.erb` (for partials) or `index.html.erb` (for full pages)
- If the view looks like a reusable component: generate as a partial with `_` prefix

If multiple screenshots are provided, clarify if they are:
- Different sections of the same page (vertically scrolled)
- Different pages entirely
- Different states of the same page (e.g., mobile vs desktop)

**Default assumption**: Multiple screenshots = different Y-positions of the same page, to be stitched vertically.

### Step 2: Analyze Screenshots

For each screenshot, carefully examine:

1. **Layout structure**: Header, navigation, main content, sidebar, footer
2. **Typography**: Font sizes, weights, colors, line heights, letter spacing
3. **Colors**: Exact hex values or closest Tailwind color (e.g., `bg-blue-500`, `text-gray-700`)
4. **Spacing**: Margins, paddings, gaps between elements (use Tailwind spacing scale: 1 = 0.25rem)
5. **Components**: Buttons, cards, forms, modals, dropdowns, tabs
6. **Icons**: Identify icon types (arrows, hamburger menu, search, user avatar, etc.)
7. **Images**: Note image positions, sizes, aspect ratios
8. **Responsive behavior**: Guess at grid breakpoints if visible
9. **Dynamic content**: Identify text/images that might be database-driven (titles, descriptions, user data, etc.)

Use Claude's vision capabilities to read text content from the screenshot when possible. For dynamic content, replace with ERB placeholders.

### Step 3: Plan the ERB Structure

Before writing code, outline the semantic structure **without global HTML tags**:

```erb
<%# Rails view partial - no <html>, <head>, or <body> tags %>
<%# Tailwind CSS should be configured in application.html.erb or via importmap %>

<header class="..."> 
  <%# Header content with ERB placeholders %>
</header>

<nav class="...">
  <%# Navigation with potential links %>
</nav>

<main class="...">
  <section class="...">
    <h1><%= @title %></h1>
    <%# Dynamic content here %>
  </section>
  
  <section class="...">
    <%# Another section %>
  </section>
</main>

<footer class="...">
  <%# Footer content %>
</footer>
```

**Critical Rules:**
1. **DO NOT include** `<!DOCTYPE html>`, `<html>`, `<head>`, or `<body>` tags
2. **DO NOT include** Tailwind CDN script tag (Rails handles CSS via asset pipeline or importmap)
3. **Start directly with semantic content tags** (`<header>`, `<nav>`, `<main>`, etc.)
4. **Use ERB placeholders** for dynamic content (e.g., `<%= @variable %>`, `<%= link_to %>`, `<%= image_tag %>`)

Use appropriate semantic tags: `<header>`, `<nav>`, `<main>`, `<section>`, `<article>`, `<aside>`, `<footer>`.

### Step 4: Generate ERB with Tailwind CSS

Write clean, Rails-compatible ERB code:

**Required elements:**
- **NO** `<!DOCTYPE html>`, `<html>`, `<head>`, or `<body>` tags
- **NO** Tailwind CDN script tag
- Start with a comment block explaining Tailwind setup:
```erb
<%# 
  This view requires Tailwind CSS to be configured in your Rails app.
  
  Option 1: Use tailwindcss-rails gem
    $ bundle add tailwindcss-rails
    $ rails tailwindcss:install
  
  Option 2: Add Tailwind CDN to application.html.erb (for quick prototyping):
    <script src="https://cdn.tailwindcss.com"></script>
%>
```

**ERB Placeholder Strategy:**
1. **Page titles/headings**: Use `<%= @title %>` or `<%= @heading %>`
2. **Body text**: Use `<%= @description %>` or hardcode with comment `<%# TODO: Replace with dynamic content %>`
3. **Images**: Use `<%= image_tag('placeholder.png', alt: 'Description', class: 'w-full h-64 object-cover') %>`
4. **Links**: Use `<%= link_to 'Text', path, class: 'text-blue-600 hover:underline' %>`
5. **Loops** (for lists/grids): Use `<% @items.each do |item| %>` if the design suggests repeated elements
6. **Conditionals**: Use `<% if @user.present? %>` for elements that depend on state

**Example with placeholders:**
```erb
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

**Styling approach:**
- Use Tailwind utility classes exclusively
- Match colors as closely as possible using Tailwind's color palette
- Use responsive classes (`sm:`, `md:`, `lg:`, `xl:`) for layout breakpoints
- Apply hover/focus states where appropriate (`hover:bg-blue-600`, `focus:ring-2`)

**Text content:**
- For clearly dynamic content (user names, post titles, etc.): Use ERB placeholders
- For static labels/UI text: Keep as hardcoded strings
- For ambiguous cases: Hardcode with a comment suggesting where to make dynamic

**Icons:**
- Use inline SVG icons with appropriate Tailwind sizing (`w-6 h-6`, `stroke-current`)
- For common icons (hamburger menu, search, user, chevron, etc.), include standard SVG paths
- Example hamburger menu:
```erb
<button class="md:hidden">
  <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"></path>
  </svg>
</button>
```

**Images:**
- Use `image_tag` helper for all images:
```erb
<%= image_tag('placeholder.png', alt: 'Hero image', class: 'w-full h-96 object-cover') %>
```
- For background images that might be dynamic:
```erb
<div class="bg-cover bg-center h-96" style="background-image: url(<%= asset_path(@hero_image) %>)">
  <%# Content %>
</div>
```
- For placeholder decorative images, use SVG rectangles:
```erb
<svg class="w-full h-64" viewBox="0 0 400 300" xmlns="http://www.w3.org/2000/svg">
  <rect width="400" height="300" fill="#3B82F6"/>
  <text x="50%" y="50%" font-size="20" fill="white" text-anchor="middle" dominant-baseline="middle">Image Placeholder</text>
</svg>
```

**For avatars/profile pictures:**
```erb
<% if @user.avatar.present? %>
  <%= image_tag(@user.avatar, class: 'w-12 h-12 rounded-full') %>
<% else %>
  <div class="w-12 h-12 rounded-full bg-gradient-to-br from-purple-400 to-pink-500 flex items-center justify-center text-white font-semibold">
    <%= @user.initials %>
  </div>
<% end %>
```

### Step 5: Handle Multiple Screenshots

If multiple screenshots represent different sections of the same page:

1. Identify overlapping elements (e.g., sticky headers appearing in multiple shots)
2. Stitch sections vertically in the correct order
3. Remove duplicate elements (don't render the header twice)
4. Ensure smooth visual continuity between sections

Ask the user to confirm the order if unclear.

### Step 6: Save and Setup Instructions

**Determine file path:**
```ruby
require 'fileutils'

# Check if user is in a Rails project
rails_root = nil
current_dir = Dir.pwd

# Walk up to find Rails root
while current_dir != '/'
  if File.exist?(File.join(current_dir, 'config', 'routes.rb'))
    rails_root = current_dir
    break
  end
  current_dir = File.dirname(current_dir)
end

# Determine save path
if rails_root
  # User is in a Rails project
  target_dir = File.join(rails_root, 'app', 'views', directory || 'pages')
  FileUtils.mkdir_p(target_dir)
  filepath = File.join(target_dir, filename || '_component.html.erb')
else
  # Not in Rails project - save to Desktop
  target_dir = File.expand_path('~/Desktop')
  filepath = File.join(target_dir, filename || 'view_component.html.erb')
end

File.write(filepath, erb_content)
```

**Generate setup instructions:**

After saving, provide detailed setup guidance:

```
✅ Rails 视图文件已生成：[app/views/pages/_component.html.erb](file://~/path/to/app/views/pages/_component.html.erb)

## 接下来的步骤：

### 1. 配置 Tailwind CSS（如果尚未配置）

**选项 A：使用 tailwindcss-rails gem（推荐）**
```bash
bundle add tailwindcss-rails
rails tailwindcss:install
```

**选项 B：使用 Tailwind CDN（仅用于快速原型）**
在 `app/views/layouts/application.html.erb` 的 `<head>` 中添加：
```erb
<script src="https://cdn.tailwindcss.com"></script>
```

### 2. 创建控制器和路由

假设这是 `pages` 控制器的 `index` 视图：

**生成控制器：**
```bash
rails generate controller Pages index
```

**或手动创建 `app/controllers/pages_controller.rb`：**
```ruby
class PagesController < ApplicationController
  def index
    # TODO: 设置视图所需的实例变量
    @title = "Welcome"
    @description = "Your page description"
    # @items = Item.all  # 示例
  end
end
```

**配置路由 `config/routes.rb`：**
```ruby
Rails.application.routes.draw do
  root 'pages#index'  # 或者
  get 'pages/index'
end
```

### 3. 准备动态数据

视图中使用的 ERB 占位符需要在控制器中赋值：

- `@title` - 页面标题
- `@description` - 描述文本
- `@items` / `@features` - 列表数据（如果有循环）
- `@user` - 用户数据（如果有用户相关内容）

查看视图文件中的 ERB 占位符并在控制器中设置对应变量。

### 4. 替换图片占位符

将视图中的 `image_tag('placeholder.png')` 替换为实际图片路径：
- 将图片放到 `app/assets/images/`
- 或使用 Active Storage 动态图片
- 或使用外部 CDN URL

### 5. 访问页面

启动 Rails 服务器：
```bash
rails server
```

访问：http://localhost:3000/pages/index（或配置的路由）
```

If user is NOT in a Rails project, also include:
```
⚠️  注意：你当前不在 Rails 项目目录中。

文件已保存到桌面。要在 Rails 项目中使用：
1. 将文件复制到 Rails 项目的 `app/views/` 目录
2. 按照上述步骤配置控制器和路由
```

## Quality Standards

Your ERB output should:
- ✅ Be valid ERB/HTML (no global `<html>/<head>/<body>` tags, proper closing tags, semantic structure)
- ✅ Use Tailwind CSS exclusively (no inline styles or `<style>` tags unless unavoidable)
- ✅ Use Rails helpers appropriately (`image_tag`, `link_to`, `content_for`, etc.)
- ✅ Include ERB placeholders for dynamic content with sensible variable names
- ✅ Be responsive (works on mobile, tablet, desktop)
- ✅ Match the visual design closely (colors, spacing, typography within 90%+ accuracy)
- ✅ Use appropriate semantic tags
- ✅ Include hover states for interactive elements
- ✅ Be well-formatted and readable (proper indentation)
- ✅ Include comments explaining setup requirements and placeholder variables

## Common Patterns

### Navigation Bar
```erb
<nav class="bg-white shadow-lg">
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
    <div class="flex justify-between h-16">
      <div class="flex items-center">
        <%= link_to root_path, class: "text-2xl font-bold text-blue-600" do %>
          Logo
        <% end %>
      </div>
      <div class="hidden md:flex items-center space-x-8">
        <%= link_to "Home", root_path, class: "text-gray-700 hover:text-blue-600" %>
        <%= link_to "About", about_path, class: "text-gray-700 hover:text-blue-600" %>
        <%= link_to "Contact", contact_path, class: "text-gray-700 hover:text-blue-600" %>
      </div>
    </div>
  </div>
</nav>
```

### Card Component (with loop)
```erb
<div class="grid grid-cols-1 md:grid-cols-3 gap-6">
  <% @items.each do |item| %>
    <div class="bg-white rounded-lg shadow-md p-6 hover:shadow-xl transition-shadow">
      <h3 class="text-xl font-semibold text-gray-800 mb-2"><%= item.title %></h3>
      <p class="text-gray-600"><%= item.description %></p>
      <%= link_to "Learn more", item_path(item), class: "text-blue-600 hover:underline mt-4 inline-block" %>
    </div>
  <% end %>
</div>
```

### Button with Link
```erb
<%= link_to root_path, class: "bg-blue-600 hover:bg-blue-700 text-white font-semibold py-2 px-6 rounded-lg transition-colors inline-block" do %>
  Get Started
<% end %>
```

### Hero Section with Dynamic Content
```erb
<section class="bg-gradient-to-r from-blue-500 to-purple-600 text-white py-20">
  <div class="max-w-7xl mx-auto px-4 text-center">
    <h1 class="text-5xl font-bold mb-4"><%= @hero_title %></h1>
    <p class="text-xl mb-8"><%= @hero_subtitle %></p>
    <%= link_to "Get Started", signup_path, class: "bg-white text-blue-600 font-semibold py-3 px-8 rounded-lg hover:bg-gray-100 inline-block" %>
  </div>
</section>
```

### Form Example
```erb
<%= form_with model: @user, class: "space-y-6" do |f| %>
  <div>
    <%= f.label :email, class: "block text-sm font-medium text-gray-700" %>
    <%= f.email_field :email, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500" %>
  </div>
  
  <div>
    <%= f.label :password, class: "block text-sm font-medium text-gray-700" %>
    <%= f.password_field :password, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500" %>
  </div>
  
  <%= f.submit "Sign In", class: "w-full bg-blue-600 text-white py-2 px-4 rounded-md hover:bg-blue-700 transition-colors" %>
<% end %>
```

## Edge Cases and Notes

- **Low-resolution screenshots**: Do your best to infer layout; use common web design patterns as reference
- **Screenshots with text overlays** (like tutorials): Preserve or remove based on context
- **Dark mode designs**: Use Tailwind's dark color palette (`bg-gray-900`, `text-gray-100`)
- **Complex animations/transitions**: Note them in comments but implement static versions
- **Custom fonts**: Use Tailwind's font families; suggest adding Google Fonts to `application.html.erb` if specific fonts are critical
- **Accessibility**: Include appropriate ARIA labels and alt text where semantically meaningful
- **Partials vs Full Views**: If the design is a reusable component, save as `_component_name.html.erb` and include instructions on rendering with `<%= render 'component_name' %>`
- **Rails URL helpers**: Use `root_path`, `about_path`, etc. instead of hardcoded URLs where possible

## Example Interaction

**User**: "请把这个截图转成 Rails 视图"
*[provides screenshot of a landing page]*

**You**:
1. Analyze the screenshot (header with logo, hero section, 3-column feature grid, footer)
2. Note colors (blue primary, white background, gray text)
3. Extract visible text and identify dynamic vs static content
4. Determine it's a full page → save as `index.html.erb` in `app/views/pages/`
5. Generate ERB with appropriate placeholders (`@hero_title`, `@features.each`, etc.)
6. Save to Rails project path or Desktop
7. Reply with file link and complete setup instructions

**User**: "把这个卡片组件转成 ERB partial"
*[provides screenshot of a card component]*

**You**:
1. Analyze the card component design
2. Recognize it's a reusable component → save as `_card.html.erb`
3. Generate with local variables: `<%= card.title %>`, `<%= card.image %>`
4. Include usage instructions: `<%= render 'card', card: @card %>`
5. Save and provide setup guidance

## Tools and Commands

Use these Ruby snippets in your workflow:

**Detect Rails project and save ERB file:**
```ruby
require 'fileutils'

# Detect Rails root
rails_root = nil
current_dir = Dir.pwd
while current_dir != '/'
  if File.exist?(File.join(current_dir, 'config', 'routes.rb'))
    rails_root = current_dir
    break
  end
  current_dir = File.dirname(current_dir)
end

# Determine target path
if rails_root
  target_dir = File.join(rails_root, 'app', 'views', 'pages')
  FileUtils.mkdir_p(target_dir)
  filepath = File.join(target_dir, 'index.html.erb')
else
  filepath = File.expand_path('~/Desktop/view_component.html.erb')
end

File.write(filepath, erb_content)
puts "Saved to #{filepath}"
```

**Generate controller (if needed):**
```bash
rails generate controller Pages index
```

**Check Tailwind setup:**
```bash
bundle list | grep tailwindcss
```

## Final Checklist

Before delivering the ERB file, verify:
- [ ] **NO** `<!DOCTYPE html>`, `<html>`, `<head>`, or `<body>` tags
- [ ] **NO** Tailwind CDN script tag (added comment about setup instead)
- [ ] Valid ERB/HTML structure (starts with semantic content tags)
- [ ] ERB placeholders used for dynamic content with clear variable names
- [ ] Rails helpers used where appropriate (`image_tag`, `link_to`)
- [ ] Colors match the screenshot
- [ ] Spacing/layout closely resembles the original
- [ ] Text content extracted or replaced with ERB placeholders
- [ ] Icons and images replaced with SVG or Rails helpers
- [ ] Comments explain required setup and variables
- [ ] File saved to appropriate location (Rails views dir or Desktop)
- [ ] User provided with complete setup instructions
- [ ] Controller/route suggestions included
- [ ] Tailwind configuration instructions provided

---

**Remember**: Your goal is to create a Rails-ready ERB view that integrates seamlessly into the application. The view should be production-ready with proper placeholders, follow Rails conventions, and include clear setup instructions for the user.
