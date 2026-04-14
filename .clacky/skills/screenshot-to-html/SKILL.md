---
name: screenshot-to-html
description: 'Convert screenshots to HTML pages with Tailwind CSS. Use this skill whenever the user wants to convert a screenshot to HTML, generate a webpage from an image, turn a UI design into code, recreate a page from a screenshot, or mentions phrases like 截图转HTML, screenshot to html, 图片生成网页, 截图变网页, convert screenshot to html, or ui to html. Also trigger when the user provides image files (png, jpg, jpeg) and mentions HTML, webpage, or code generation.'
disable-model-invocation: false
user-invocable: true
---

# Screenshot to HTML Converter

Convert screenshots into fully functional HTML pages using Tailwind CSS.

## What This Skill Does

Analyze one or more screenshots and generate a complete, responsive HTML file that recreates the visual design. The output uses Tailwind CSS CDN for styling, includes proper semantic HTML, and replaces images/icons with SVG placeholders.

## When to Use This Skill

Trigger this skill when the user:
- Uploads a screenshot and wants it converted to HTML
- Describes a UI design from an image and wants the code
- Provides multiple screenshots from the same page (scrolled views)
- Asks to "recreate this page", "turn this into a webpage", "code this UI"
- Uses phrases like: 截图转HTML, screenshot to html, 图片生成网页, 截图变网页

## Core Workflow

### Step 1: Gather Input

Ask the user to provide:
1. **Screenshot file(s)**: Path to one or more images (PNG, JPG, JPEG, WEBP)
2. **Context** (optional): What kind of page is this? Any special requirements?

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

Use Claude's vision capabilities to read text content from the screenshot when possible. Preserve actual text rather than using lorem ipsum.

### Step 3: Plan the HTML Structure

Before writing code, outline the semantic structure:

```
<!DOCTYPE html>
<html>
  <head>
    - Tailwind CDN
    - Meta tags
    - Title
  </head>
  <body>
    <header> ... </header>
    <nav> ... </nav>
    <main>
      <section> ... </section>
      <section> ... </section>
    </main>
    <footer> ... </footer>
  </body>
</html>
```

Use appropriate semantic tags: `<header>`, `<nav>`, `<main>`, `<section>`, `<article>`, `<aside>`, `<footer>`.

### Step 4: Generate HTML with Tailwind CSS

Write clean, well-formatted HTML:

**Required elements:**
- `<!DOCTYPE html>` declaration
- `<meta charset="UTF-8">` and `<meta name="viewport" content="width=device-width, initial-scale=1.0">`
- Tailwind CSS CDN: `<script src="https://cdn.tailwindcss.com"></script>`
- Descriptive `<title>` based on the page content

**Styling approach:**
- Use Tailwind utility classes exclusively (no custom CSS unless absolutely necessary)
- Match colors as closely as possible using Tailwind's color palette
- Use responsive classes (`sm:`, `md:`, `lg:`, `xl:`) for layout breakpoints
- Apply hover/focus states where appropriate (`hover:bg-blue-600`, `focus:ring-2`)

**Text content:**
- Extract real text from screenshots when legible
- If text is unreadable, use contextually appropriate placeholder text (not generic lorem ipsum)
- Preserve heading hierarchy (`<h1>`, `<h2>`, `<h3>`)

**Icons:**
- Use inline SVG icons with appropriate Tailwind sizing (`w-6 h-6`, `stroke-current`)
- For common icons (hamburger menu, search, user, chevron, etc.), include standard SVG paths
- Example hamburger menu:
```html
<svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"></path>
</svg>
```

**Images:**
- Replace with colored SVG rectangles that maintain the aspect ratio
- Use colors from the Tailwind palette that match the dominant color in the original image
- Example:
```html
<svg class="w-full h-64" viewBox="0 0 400 300" xmlns="http://www.w3.org/2000/svg">
  <rect width="400" height="300" fill="#3B82F6"/>
  <text x="50%" y="50%" font-size="20" fill="white" text-anchor="middle" dominant-baseline="middle">Image Placeholder</text>
</svg>
```

**For avatars/profile pictures:**
```html
<div class="w-12 h-12 rounded-full bg-gradient-to-br from-purple-400 to-pink-500 flex items-center justify-center text-white font-semibold">
  AB
</div>
```

### Step 5: Handle Multiple Screenshots

If multiple screenshots represent different sections of the same page:

1. Identify overlapping elements (e.g., sticky headers appearing in multiple shots)
2. Stitch sections vertically in the correct order
3. Remove duplicate elements (don't render the header twice)
4. Ensure smooth visual continuity between sections

Ask the user to confirm the order if unclear.

### Step 6: Save and Preview

Save the HTML file to the user's Desktop with a descriptive name:

```ruby
timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
filename = "screenshot_#{timestamp}.html"
filepath = File.expand_path("~/Desktop/#{filename}")
File.write(filepath, html_content)
```

Then inform the user:
```
✅ HTML 文件已生成：[screenshot_20260414_103045.html](file://~/Desktop/screenshot_20260414_103045.html)

你可以直接在浏览器中打开预览。
```

## Quality Standards

Your HTML output should:
- ✅ Be valid HTML5 (proper DOCTYPE, closing tags, semantic structure)
- ✅ Use Tailwind CSS exclusively (no inline styles or `<style>` tags unless unavoidable)
- ✅ Be responsive (works on mobile, tablet, desktop)
- ✅ Match the visual design closely (colors, spacing, typography within 90%+ accuracy)
- ✅ Use appropriate semantic tags
- ✅ Include hover states for interactive elements
- ✅ Be well-formatted and readable (proper indentation)

## Common Patterns

### Navigation Bar
```html
<nav class="bg-white shadow-lg">
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
    <div class="flex justify-between h-16">
      <div class="flex items-center">
        <span class="text-2xl font-bold text-blue-600">Logo</span>
      </div>
      <div class="hidden md:flex items-center space-x-8">
        <a href="#" class="text-gray-700 hover:text-blue-600">Home</a>
        <a href="#" class="text-gray-700 hover:text-blue-600">About</a>
        <a href="#" class="text-gray-700 hover:text-blue-600">Contact</a>
      </div>
    </div>
  </div>
</nav>
```

### Card Component
```html
<div class="bg-white rounded-lg shadow-md p-6 hover:shadow-xl transition-shadow">
  <h3 class="text-xl font-semibold text-gray-800 mb-2">Card Title</h3>
  <p class="text-gray-600">Card description goes here.</p>
</div>
```

### Button
```html
<button class="bg-blue-600 hover:bg-blue-700 text-white font-semibold py-2 px-6 rounded-lg transition-colors">
  Click Me
</button>
```

### Hero Section
```html
<section class="bg-gradient-to-r from-blue-500 to-purple-600 text-white py-20">
  <div class="max-w-7xl mx-auto px-4 text-center">
    <h1 class="text-5xl font-bold mb-4">Welcome to Our Site</h1>
    <p class="text-xl mb-8">Build amazing things with us</p>
    <button class="bg-white text-blue-600 font-semibold py-3 px-8 rounded-lg hover:bg-gray-100">
      Get Started
    </button>
  </div>
</section>
```

## Edge Cases and Notes

- **Low-resolution screenshots**: Do your best to infer layout; use common web design patterns as reference
- **Screenshots with text overlays** (like tutorials): Preserve or remove based on context
- **Dark mode designs**: Use Tailwind's dark color palette (`bg-gray-900`, `text-gray-100`)
- **Complex animations/transitions**: Note them in comments but implement static versions
- **Custom fonts**: Use Tailwind's font families; suggest Google Fonts CDN if specific fonts are critical
- **Accessibility**: Include appropriate ARIA labels and alt text where semantically meaningful

## Example Interaction

**User**: "请把这个截图转成 HTML"
*[provides screenshot of a landing page]*

**You**:
1. Analyze the screenshot (header with logo, hero section, 3-column feature grid, footer)
2. Note colors (blue primary, white background, gray text)
3. Extract visible text
4. Generate HTML with Tailwind classes
5. Save to `~/Desktop/screenshot_20260414_103500.html`
6. Reply: "✅ HTML 文件已生成：[screenshot_20260414_103500.html](file://~/Desktop/screenshot_20260414_103500.html)"

## Tools and Commands

Use these Ruby snippets in your workflow:

**Save HTML file:**
```ruby
require 'fileutils'
timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
filepath = File.expand_path("~/Desktop/screenshot_#{timestamp}.html")
File.write(filepath, html_content)
puts "Saved to #{filepath}"
```

**Open in browser (macOS):**
```bash
open ~/Desktop/screenshot_20260414_103500.html
```

## Final Checklist

Before delivering the HTML file, verify:
- [ ] Valid HTML5 structure
- [ ] Tailwind CDN included
- [ ] Responsive meta tag present
- [ ] Colors match the screenshot
- [ ] Spacing/layout closely resembles the original
- [ ] Text content extracted or appropriately replaced
- [ ] Icons and images replaced with SVG placeholders
- [ ] File saved to Desktop
- [ ] User provided with file link

---

**Remember**: Your goal is to create a pixel-close recreation of the screenshot that works as a real webpage. Attention to detail matters — match colors, spacing, and typography as precisely as possible.
