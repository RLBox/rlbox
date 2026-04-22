---
name: screenshot-to-html
description: 'Convert screenshots to Rails HTML.ERB view files with Tailwind CSS. Use this skill whenever the user wants to convert a screenshot to HTML/ERB, generate a Rails view from an image, turn a UI design into Rails code, recreate a page from a screenshot, or mentions phrases like 截图转HTML, screenshot to html, 截图转ERB, screenshot to erb, 图片生成网页, 截图变网页, convert screenshot to html, ui to html, ui to code, design to code, 图片转代码, 设计稿转代码, 还原设计稿, 把图片做成网页, 网页还原, recreate this page, code this UI. Also trigger when the user provides image files (png, jpg, jpeg, webp) and mentions HTML, webpage, Rails view, ERB, or code generation.'
disable-model-invocation: false
user-invocable: true
---

# Screenshot to Rails ERB View Converter

Analyze screenshots and generate Rails .html.erb view files using Tailwind CSS utility classes.

## Workflow

### 1. Gather Input

Ask user for:
- **Screenshot file(s)**: path to image(s)
- **Context** (optional): page type, special requirements
- **Target directory** (optional): default `app/views/pages/`
- **File name** (optional): default `index.html.erb` (full page) or `_component.html.erb` (partial)

Multiple screenshots default to vertically-stitched sections of the same page. Clarify if ambiguous.

### 2. Project Discovery (Rails-aware)

Before generating code, detect if you are inside a Rails project by looking for `config/routes.rb` in the working directory or its parents. If found, scan the project for reusable patterns — this produces higher-quality output that feels native to the codebase.

**Icon helper scan**: Check for an SVG icon helper (e.g. `app/helpers/svg_icon_helper.rb` or similar). If one exists:
- Read it to get the list of registered icon names
- Use the project's icon helper (e.g. `<%= svg_icon("name", class: "...") %>`) instead of writing raw inline SVGs
- If a needed icon is not registered, note it for later — you'll add it after checking for duplicates (see step 6.3)

**Existing page scan**: Skim 1–2 existing view files in the same directory (e.g. `app/views/home/`) to learn the project's established patterns:
- Layout wrapper conventions (e.g. `fixed inset-0 overflow-y-auto`, `max-w-lg mx-auto`)
- Navigation bar style (sticky, gradient, back-button pattern)
- Card/list component patterns (shop cards, product grids, coupon cards)
- Spacing and color conventions
- Partial naming conventions (e.g. `_section_name.html.erb`)
- Link placeholder convention (e.g. `javascript:void(0)` vs `href="#"`)

**Controller/route scan**: Check the controller file and `config/routes.rb` to understand existing actions — this informs what action name and route to suggest.

This discovery step takes 30 seconds but saves significant rework by ensuring the generated code integrates seamlessly.

### 3. Analyze Screenshots

Examine each screenshot for:
- Layout structure (header, nav, main, sidebar, footer)
- Typography (sizes, weights, colors)
- Colors (map to Tailwind palette, e.g. `bg-blue-500`, `text-gray-700`)
- Spacing (map to Tailwind scale: 1 = 0.25rem)
- Components (buttons, cards, forms, modals, tabs)
- Icons (identify type — match to project icon helper if available)
- Images (positions, sizes, aspect ratios)
- Dynamic vs static content

Use vision to read text content directly from screenshots.

### 4. Generate ERB

**Critical Rules:**
- **NO** `<!DOCTYPE html>`, `<html>`, `<head>`, `<body>` tags — start with semantic content tags directly
- **NO** Tailwind CDN `<script>` tag
- Use Tailwind utility classes exclusively (minimize inline styles — only use `style=` for gradients or values Tailwind cannot express)
- Use semantic HTML: `<header>`, `<nav>`, `<main>`, `<section>`, `<article>`, `<aside>`, `<footer>`
- Use responsive classes (`sm:`, `md:`, `lg:`, `xl:`) for breakpoints
- Include hover/focus states for interactive elements

**ERB Conventions:**
- Dynamic content → ERB placeholders: `<%= @title %>`, `<%= @description %>`
- Images → `<%= image_tag('placeholder.png', alt: '...', class: '...') %>`
- Links → `<%= link_to 'Text', path, class: '...' %>`
- Repeated elements → `<% @items.each do |item| %> ... <% end %>`
- Conditional display → `<% if @user.present? %> ... <% end %>`
- Static UI labels → hardcode as strings

**Icons (project-aware):** If the project has an icon helper, use it (e.g. `<%= svg_icon("cart", class: "w-6 h-6 text-white") %>`). Only fall back to raw inline SVG if no helper exists. When the helper exists but is missing a needed icon, register the new icon in the helper file — do not inline SVGs in the view.

**Images:** Use `image_tag` helper. For decorative placeholders, use colored gradient divs with SVG icons (matching the project's existing style).

**Partials:** For large pages, split into logical partials (e.g. `_shangou_lijia.html.erb` for a product section, `_shangou_shops.html.erb` for a shop list). This matches how Rails projects naturally organize complex views. Each partial gets a descriptive `<%# comment %>` at the top.

**Placeholder links:** Match the project convention. Many projects use `javascript:void(0)` instead of `href="#"` to avoid scroll-to-top behavior — check existing views and follow the same pattern.

### 5. Handle Multiple Screenshots

- Identify overlapping elements (e.g. sticky headers)
- Stitch sections in correct order, remove duplicates
- Ensure visual continuity

### 6. Save Files and Wire Up

**Save the view file(s):**
- **In Rails project** → save to `app/views/<directory>/<filename>` (and any partials)
- **Not in Rails project** → save to `~/Desktop/<filename>`

Create directories with `mkdir_p` as needed.

**Wire up controller + routes (Rails projects only):**
After saving view files, also:
1. **Add the controller action** — append a new action to the appropriate controller (e.g. `def shangou; @full_render = true; end`), matching the pattern of existing actions
2. **Add the route** — append `get '<page>', to: '<controller>#<action>'` to `config/routes.rb`, placed near similar routes
3. **Register new icons** — if any new SVG icons were needed:
   - **CRITICAL: Check for duplicates first** — use `grep` to search the icon helper file for each icon name you plan to add (e.g. `grep '"icon_name"' app/helpers/svg_icon_helper.rb`)
   - If an icon name already exists, **reuse it** instead of adding a duplicate (duplicate keys cause Ruby syntax errors and the helper will fail to load)
   - If genuinely new, add to the appropriate section in the helper file
   - Choose descriptive, unique names (e.g. `lightning_bolt` instead of `lightning` if `lightning` exists)
4. **Wire navigation links** — if the new page is accessible from an existing page (e.g. a category icon), update that page's link `href` to point to the new route

This ensures the page is immediately accessible after generation — no manual wiring needed.

### 7. Provide Summary

After saving, reply with:

1. **Files created/modified** — table listing each file and what it contains
2. **New icons registered** (if any)
3. **Route added** — the new URL path
4. **Navigation wired** — which existing page now links to the new one
5. **How to access** — e.g. "从外卖页点击超市便利图标即可访问"

If not in a Rails project, note that the file was saved to Desktop and suggest copying to a Rails `app/views/` directory, along with controller/route setup instructions.

## Quality Checklist

- Valid ERB structure, no global HTML wrapper tags
- Colors, spacing, typography match screenshot closely (90%+ accuracy)
- Uses project icon helper (not raw inline SVGs) when available
- Matches project's existing layout/component patterns
- No duplicate icon registrations in helper
- Controller action and route are wired up and functional
- Proper ERB placeholders with clear variable names
- Well-formatted, readable code with proper indentation
- Placeholder links use project convention (e.g. `javascript:void(0)`)
