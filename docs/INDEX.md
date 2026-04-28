---
topic: wiki-index
updated_at: 2026-04-28
description: rlbox 项目文档总索引（wiki 首页）
---

# 📚 rlbox Wiki

> **这是 LLM 可维护的持久化知识库**（灵感来自 [Karpathy's LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)）。
> 代码 = raw source（不可变）| `docs/` = wiki（LLM 维护）| [`CLAUDE.md`](../CLAUDE.md) = schema（路由规则）

## 🎯 项目一句话
**rlbox** 是所有 Agent Benchmark 派生项目（Goomart / IdleSwap / Kangoo…）的**模板底座**：
- 表面：一个可 fork 的 Rails 7.2 项目脚手架
- 本质：内置 data_version 软隔离 + Validator 系统 + 移动优先 UI，让每个派生项目开箱即用
- 机制：baseline 数据 `data_version='0'`，Agent 产生的数据 `data_version≠'0'`，一键回滚

## 🗂️ 目录结构

```
docs/
├── INDEX.md                 ← 你在这里
├── HOW_TO_BROWSE.md         ← 人类开发者浏览指南
├── architecture/            ← 核心架构（必读）
│   ├── agent-sandbox.md         沙盒模型：baseline / session / rollback
│   ├── data-version.md          data_version 设计、RLS、隔离保证
│   ├── data-packs.md            唯一的数据加载入口
│   ├── validator-system.md      验证器系统总览（prepare/verify/rollback 生命周期）
│   ├── validator-linter.md      Linter：静态检查 data_version 遗漏
│   └── multi-session.md         多会话并发（独立 cookie + URL 参数）
├── models/                  ← 业务模型 entity pages（各派生项目自行填充）
│   └── INDEX.md
├── conventions/             ← 开发规范
│   ├── validator-writing.md     验证器编写标准
│   ├── adding-models.md         加新表/新字段的完整流程
│   ├── frontend.md              前端规范（Stimulus/Turbo/Icons/ActionCable）
│   ├── testing.md               测试与静态检查（rake test/rspec/lint）
│   ├── new-branch.md            新分支初始化
│   └── environment.md           部署 / 环境变量 / 平台约定
├── decisions/               ← ADR：架构决策记录（不可变历史）
│   ├── ADR-001-all-business-tables-have-data-version.md
│   ├── ADR-002-data-packs-not-seeds.md
│   ├── ADR-003-business-vs-system-tables.md
│   ├── ADR-004-rls-requires-bin-db-init.md
│   └── INDEX.md
└── archive/                 ← 历史/被取代的文档（只读，勿模仿）
    ├── *_FIX.md                 一次性修复笔记（根目录迁入）
    ├── VALIDATOR_DESIGN.md      → 被 architecture/validator-system.md 取代
    ├── VALIDATOR_WRITING_STANDARDS.md  → 被 conventions/validator-writing.md 取代
    ├── MULTI_TURN_*.md          → 多轮对话骨架历史归档
    ├── MULTI_SESSION_IMPLEMENTATION.md → 被 architecture/multi-session.md 取代
    ├── DATA_VERSION_LINT_GUARANTEE.md  → 被 architecture/validator-linter.md 取代
    ├── NEW_BRANCH_GUIDE.md      → 被 conventions/new-branch.md 取代
    ├── frontend-guidelines.md   → 被 conventions/frontend.md 取代
    └── project.md               → 被 conventions/environment.md 取代
```

## 🔗 快速链接（全文档索引）

| 类别 | 文件 |
|---|---|
| 浏览指南 | [HOW_TO_BROWSE.md](HOW_TO_BROWSE.md) |
| 架构 | [architecture/agent-sandbox.md](architecture/agent-sandbox.md) · [architecture/data-version.md](architecture/data-version.md) · [architecture/data-packs.md](architecture/data-packs.md) · [architecture/validator-system.md](architecture/validator-system.md) · [architecture/validator-linter.md](architecture/validator-linter.md) · [architecture/multi-session.md](architecture/multi-session.md) |
| 规范 | [conventions/validator-writing.md](conventions/validator-writing.md) · [conventions/adding-models.md](conventions/adding-models.md) · [conventions/frontend.md](conventions/frontend.md) · [conventions/testing.md](conventions/testing.md) · [conventions/new-branch.md](conventions/new-branch.md) · [conventions/environment.md](conventions/environment.md) |
| 决策 | [decisions/INDEX.md](decisions/INDEX.md) · [decisions/ADR-001-all-business-tables-have-data-version.md](decisions/ADR-001-all-business-tables-have-data-version.md) · [decisions/ADR-002-data-packs-not-seeds.md](decisions/ADR-002-data-packs-not-seeds.md) · [decisions/ADR-003-business-vs-system-tables.md](decisions/ADR-003-business-vs-system-tables.md) · [decisions/ADR-004-rls-requires-bin-db-init.md](decisions/ADR-004-rls-requires-bin-db-init.md) |
| 模型 | [models/INDEX.md](models/INDEX.md) |

## 🚦 按角色导读

### 🤖 Agent（LLM）首次接手
1. 读 [`CLAUDE.md`](../CLAUDE.md) 顶部 Documentation Map
2. 读 [`architecture/agent-sandbox.md`](architecture/agent-sandbox.md) — 理解项目本质
3. 读 [`architecture/data-version.md`](architecture/data-version.md) — 理解隔离机制
4. **遇到具体任务时**：按 Documentation Map 路由到对应文档

### 👨‍💻 人类开发者首次接手
1. 安装 VSCode 扩展：打开仓库会提示安装 `foam.foam-vscode`（Obsidian 替代）
2. 读本文件 → [`architecture/agent-sandbox.md`](architecture/agent-sandbox.md)
3. 用 Foam 的图谱视图（`Cmd+Shift+P` → "Foam: Show Graph"）浏览文档关系
4. 跑 `bin/db_init` 初始化数据库 + baseline

## 🛠️ 文档工具链

| 工具 | 用途 | 配置 |
|---|---|---|
| **VSCode + Foam** | 日常浏览、反向链接、图谱视图 | `.vscode/extensions.json` |
| **`rake docs:lint`** | 自动检测文档过期、broken links、反例代码 | `lib/tasks/docs.rake` |
| **GitHub Search** | 跨版本搜索 | `repo:rlbox path:docs/ <kw>` |
| **`grep -rn "kw" docs/`** | 命令行快速定位 | — |

## 🔄 文档维护流程（LLM 遵守）
参见 [`CLAUDE.md` → Session-End Checklist](../CLAUDE.md#-session-end-checklist)。

简要：
1. **ingest**：改代码时，同步更新相关 wiki 页（通常触达 3-5 个页面）
2. **link**：新页必须被至少一个现有页引用（避免孤儿）
3. **ADR**：任何架构决策/推翻旧做法 → 新开一个 ADR 文件
4. **archive**：一次性修复笔记写完就放 `archive/`，wiki 只保留最终结论
5. **lint**：大改后跑 `rake docs:lint`

## ⚠️ 已知技术债 / 可选增强

### 可选增强（不是债，是扩展点）
- [ ] `config/validator_lint_rules.yml` — `ValidatorLinter` 支持可选配置（没有此文件时走零配置模式）。如需收紧检查，创建此文件即可。详见 `architecture/validator-linter.md`。
- [ ] `docs/models/` — 模板库本身无业务模型，派生项目 fork 后在此填充各自的 entity pages。

## 📊 wiki 统计
运行 `rake docs:stats` 查看：页面数、引用图、过期页（>30 天未更新）。
