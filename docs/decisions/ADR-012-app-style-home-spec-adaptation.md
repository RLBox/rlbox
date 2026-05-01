---
topic: adr-012
updated_at: 2026-05-01
status: accepted
decision_date: 2026-05-01
supersedes: none
related:
  - conventions/testing.md
  - conventions/frontend.md
---

# ADR-012 Native-app 风格首页的 spec 适配策略

## Status
✅ **Accepted** — 2026-05-01

## Context

rlbox 模板附带两条首页"健康检查"spec（出自新手保护，避免误复制 navbar / 忘记 pt-24 让位 floating navbar）：

1. `spec/requests/home_spec.rb`
   断言 `nav_count + nav_headers ≤ 1`——**只允许 1 个 `<nav>`**，防止 view 里手抄 navbar 导致和 layout 的 `shared/_navbar` 重复渲染。

2. `spec/requests/authenticated_access_spec.rb:95` "validates home page has proper padding for floating navbar"
   断言首页存在 `div > [data-testid="home-first-section"]` 且带 `pt-(20|24|28|32)`，保证首屏内容不被顶部 fixed navbar 盖住。

**两条 spec 都基于一个隐含假设**：首页是"shared navbar（顶部 fixed）+ 普通内容区"的标准形态。

### 冲突点（触发来源：派生项目 duvy）

派生项目 duvy 为复刻得物 / 小红书 / 抖音等 **native-app 风格**首页，做了如下**有意的定制**：

- `HomeController#index` 设 `@full_render = true`，使 layout 的 `shared/_navbar` **跳过渲染**（见 `app/views/layouts/application.html.erb` 里 `unless @full_render`）。
- 自己写了一个 **sticky 顶部搜索栏**（`<header class="sticky top-0 ...">`）代替 navbar。
- 页面里有 **Tab 分类导航 `<nav>`**（第二个 nav）。
- 页面底部有 **bottom tab bar `<nav class="fixed bottom-0 ...">`**（得物/小红书 app 标配，4 个 tab）。

结果：
- `nav_count = 2`，与"≤1"冲突。
- 最外层 `<div data-testid="home-first-section">` 本身是最外元素，没有父 `<div>`，选择器 `div > [...]` 选不中；而且无 floating navbar 也无需 `pt-24`。

这是模板 spec 的预设与定制形态的**正面冲突**，不是代码 bug。后续其他派生项目（Goomart / IdleSwap / planet…）如果采用同类 native-app 风格，也会踩同一颗雷。

## Decision

**模板层面放开这个口子**——不迎合 spec 去破坏定制设计（塞 wrapper / 加 pt-24 / 删 bottom_nav），而是**让 spec 能识别 native-app 形态并适度放宽/跳过**。

关键设计：**默认行为不变**。只有当检测到 native-app 信号时才放宽；普通项目仍然享受严格约束（防新手误复制 navbar）。

### 1. 放宽 `home_spec.rb` 的 nav 数量约束

引入一个信号：**app-style home = 存在 `nav.fixed.bottom-0` 且不存在 `shared/_navbar` 的痕迹**。

```ruby
has_bottom_nav = doc.css('nav').any? do |n|
  cls = n['class'].to_s
  cls.include?('fixed') && cls.include?('bottom-0')
end
has_shared_navbar = doc.css('nav, header').any? do |n|
  n['data-clacky-source-loc'].to_s.include?('shared/_navbar')
end
app_style_home = has_bottom_nav && !has_shared_navbar

max_nav = app_style_home ? 2 : 1
expect(total_navigation).to be <= max_nav
```

- 非 app-style：沿用 `≤1`（保持模板原有严格约束，防误复制 navbar）。
- app-style：允许 `≤2`（顶部 tab nav + 底部 tab bar）。
- 并加正向断言：app-style home 必须保留 `nav.fixed.bottom-0`（守护定制意图不被误删）。

### 2. app-style home 跳过 floating-navbar padding 检查

在 `authenticated_access_spec.rb` 的 floating-navbar padding test 顶端，检测到任一信号即 `skip`：

```ruby
app_style_signals = [
  content.include?('@full_render'),
  content.match?(/render\s+['"]home\/bottom_nav['"]/),
  content.match?(/nav[^>]*class=["'][^"']*fixed[^"']*bottom-0/)
]
skip "..." if app_style_signals.any?
```

**理由**：app-style home 根本没有 floating navbar 需要让位，`pt-24` 无意义；也不需要额外的 wrapper `<div>` 包裹 first_section。

### 3. 派生项目的附带责任（非模板变更，但已在 duvy 里执行）

派生项目在采用 app-style home 时，注意模板的另一条规则**仍然有效**：**禁止 placeholder 链接（`a[href="#"]`）**。
所有 bottom_nav 的 tab 入口必须是**真实路由**或 `<button type="button">`（未实现功能的诚实占位），不能是假 anchor。

这条不需要模板层额外做什么——原 spec 已经在查，只是在 nav_count 修复前被 failure 掩盖，修复后会暴露。

## Consequences

### Positive
- ✅ 任何派生项目（duvy / 未来的 Goomart / IdleSwap / planet / Kangoo）做 native-app 风格首页时，模板 spec 开箱即过，不用逐项目复制粘贴 spec 补丁。
- ✅ 模板 spec 在**非定制项目**上仍保持原有严格约束（≤1 nav、必须有 pt-24），新手保护不丢。
- ✅ 引入正向断言（"app-style home 必须保留 bottom_nav"）——定制意图被测试守护，未来若有人误删 bottom_nav 会立即红灯。
- ✅ 模板成为"两种首页形态都官方支持"的状态，写在同一套 spec 里。

### Negative
- ⚠️ spec 代码复杂度略升——多了 `app_style_home` 分支判定逻辑（但集中在 spec 层，不污染应用代码）。
- ⚠️ "app-style home"信号判定基于启发式（class 关键词 + 源码字符串）——如果未来出现第三种首页形态（如 web-only 全屏 canvas），可能需要再扩展信号。

### Neutral
- 本 ADR 只谈首页 spec。其他页面（profile、admin 等）仍走 rlbox 默认 navbar 检查，不受影响。

## Implementation

**修改文件**：
- `spec/requests/home_spec.rb` — 引入 `app_style_home` 信号，放宽 `max_nav` 并加正向断言。
- `spec/requests/authenticated_access_spec.rb` — floating-navbar padding test 增加 `skip` 条件。

**验证**：
```bash
bundle exec rake test
# => 0 failures（非 app-style 场景 spec 行为不变）
```

**派生项目侧的配合（模板不负责）**：
- 把 bottom_nav 的所有 `<a href="#">` 占位改成真实路由或 `<button type="button">`。
- 首页最外层保留 `data-testid="home-first-section"` 对未来 E2E 仍有用，保留无害。

## History

- 2026-05-01 — 由 duvy 项目先落地（duvy commit `be8fafc`），随后通过 `fork-to-template-sync` 技能回流到 rlbox 模板，让所有派生项目受益。

## Notes

- 本 ADR 与 `conventions/testing.md` 相关：后者描述"首页 spec 的默认严格形态"，本 ADR 是其补充分支。
- `data-testid="home-first-section"` 不再强制 `div > [...]` 的 DOM 结构（app-style home 不需要 wrapper），但 testid 本身保留。
