# 📖 如何浏览 rlbox Wiki

> 仓库根的 [`CLAUDE.md`](../CLAUDE.md) 是 **Agent 入口**。
> 本文是**人类开发者**的浏览指南。

## 方案一：VSCode + Foam（推荐）
Foam 是 Obsidian 的开源 VSCode 替代，支持 `[[WikiLink]]`、反向链接、图谱视图。

1. VSCode 打开本仓库
2. 右下角会提示安装推荐扩展（`.vscode/extensions.json` 配置） → 点 Install All
3. `Cmd+Shift+P` → "Foam: Show Graph" 查看文档关系图
4. `Cmd+P` → 输入 `docs/` 快速跳转任一页

**为什么不用 Obsidian？**
- 需要单独打开第二个 App
- `[[WikiLink]]` 在 GitHub 渲染器看不到
- 协作要付费 Sync

Foam 用标准 Markdown，在 VSCode、GitHub、命令行 grep 都能工作，同时在 VSCode 里拥有 Obsidian 的所有交互。

## 方案二：GitHub 网页
- `[text](path.md)` 相对链接直接可点
- Search：`repo:rlbox path:docs/ <keyword>`

## 方案三：命令行
```bash
# 全文搜
grep -rn "data_version" docs/

# 更快（如果装了 ripgrep）
rg "data_version" docs/

# 跳过 archive
rg "data_version" docs/ --glob '!archive/**'
```

## 方案四：`rake docs:*` 任务
```bash
bin/rake docs:lint      # 健康检查（broken links / 旅行残留 / 缺 frontmatter）
bin/rake docs:stats     # 页面统计
bin/rake docs:orphans   # 找无反向链接的孤儿页
bin/rake docs:stale     # 找 30+ 天未更新的页
```

## 方案五：AI 语义查询（可选）
- **Cursor IDE**：`@Docs` 把 `docs/` 加进索引，用自然语言问
- **Claude Projects**：把 `docs/` 打包上传，做 RAG
- **Continue.dev**（开源）：本地索引

这些是 Layer 4，当文档到 50+ 页后再考虑。目前页面较少，`grep` 足够。
