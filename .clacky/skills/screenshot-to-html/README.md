# Screenshot to HTML - 技能说明

## 概述

`screenshot-to-html` 是一个将截图转换为完整 HTML 页面的 Clacky 技能。使用 Tailwind CSS 进行样式设计，支持单张或多张截图拼接。

## 功能特性

✅ 分析截图的布局、颜色、间距、组件
✅ 生成使用 Tailwind CSS 的响应式 HTML
✅ 图标和图片用 SVG 占位图代替
✅ 支持多截图垂直拼接（模拟滚动页面）
✅ 自动提取截图中的文字内容
✅ 输出符合 HTML5 标准的完整代码

## 触发方式

在对话中使用以下任一方式触发技能：

- "截图转 HTML"
- "screenshot to html"
- "图片生成网页"
- "把这个 UI 设计变成代码"
- "convert screenshot to html"
- 手动调用：`/screenshot-to-html`

## 使用示例

**示例 1：单张登录页面**
```
我有一个登录页面的截图在桌面上叫做 login_page.png，
能帮我把它转成 HTML 吗？要用 Tailwind CSS，图标用 SVG 就行。
```

**示例 2：多截图拼接**
```
screenshot to html - I took 3 screenshots of the same product page 
as I scrolled down. They're in ~/Downloads: product_top.jpg, 
product_middle.jpg, product_bottom.jpg. 
Can you stitch them together into one HTML page?
```

**示例 3：仪表板界面**
```
把这个 UI 设计变成代码，图在 ~/Desktop/dashboard_design.png，
是一个数据仪表板的界面，有图表、卡片、侧边栏那些。
用 Tailwind 做，图表的地方先用占位图代替就好。
```

## 输出

生成的 HTML 文件会保存到桌面，文件名格式：`screenshot_YYYYMMDD_HHMMSS.html`

你会收到一个可点击的文件链接，直接在浏览器中打开即可预览。

## 评估结果

根据初始测试（3 个测试用例，15 个断言）：

- **使用技能**：100% 通过率（15/15）
- **不使用技能**：40% 通过率（6/15）
- **提升**：+60 百分点

### 关键优势

1. **Tailwind CSS 使用**：100% 正确使用 vs 0%
2. **HTML 结构质量**：完整的 DOCTYPE、meta 标签、语义化标签
3. **SVG 图标**：所有图标和占位图都使用 SVG
4. **响应式设计**：所有页面包含响应式类
5. **多截图理解**：正确处理拼接需求，避免重复元素

## 技能文件位置

- 技能定义：`~/.clacky/skills/screenshot-to-html/SKILL.md`
- 测试用例：`~/.clacky/skills/screenshot-to-html/evals/evals.json`
- 测试结果：`~/.clacky/skills/screenshot-to-html-workspace/iteration-1/`

## 下一步

1. 在实际项目中测试技能
2. 根据反馈优化指令
3. 添加更多边缘用例测试
4. 考虑支持深色模式检测
5. 添加对特定 UI 框架的识别（Bootstrap、Material UI 等）

---

**创建时间**：2026-04-14
**版本**：1.0
**状态**：已完成测试，可供使用
