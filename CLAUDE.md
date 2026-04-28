# 🤖 Agent Entry Point — READ THIS FIRST

> **This file is the schema (routing table) for the project wiki.** It is intentionally dense.
> When you need details, **follow the links below** — do NOT guess, do NOT rely on prior memory.

## 📍 Project One-liner
**rlbox** — Agent Benchmark 评测沙盒模板，所有派生项目（Goomart / IdleSwap / Kangoo…）均从此 fork。
本质是一个 **可复用的 Rails 框架底座**：data_version 软隔离 + Validator 系统 + 移动优先 UI + LLM wiki 文档体系。

## 🗺️ Documentation Map — 按问题类型查

| 我想做 / 我想知道 | 必读文档 | 优先级 |
|---|---|---|
| **首次上手项目** | [docs/INDEX.md](docs/INDEX.md) → [docs/architecture/agent-sandbox.md](docs/architecture/agent-sandbox.md) | P0 |
| **data_version / 会话隔离 / rollback** | [docs/architecture/data-version.md](docs/architecture/data-version.md) | P0 |
| **baseline 数据怎么加 / 为什么不用 seeds** | [docs/architecture/data-packs.md](docs/architecture/data-packs.md) | P0 |
| **新建业务表 / 三件套能不能用** | [docs/decisions/ADR-001-all-business-tables-have-data-version.md](docs/decisions/ADR-001-all-business-tables-have-data-version.md) + [docs/conventions/adding-models.md](docs/conventions/adding-models.md) | P0 |
| **某个模型的字段/关联/约束** | [docs/models/](docs/models/)`<model>.md` | P1 |
| **写 validator 规范** | [docs/conventions/validator-writing.md](docs/conventions/validator-writing.md) | P1 |
| **验证器系统设计（生命周期/数据隔离）** | [docs/architecture/validator-system.md](docs/architecture/validator-system.md) | P1 |
| **Validator linter（`rake validator:lint`）** | [docs/architecture/validator-linter.md](docs/architecture/validator-linter.md) | P1 |
| **前端（Stimulus/Turbo/Icons/ActionCable）** | [docs/conventions/frontend.md](docs/conventions/frontend.md) | P1 |
| **测试 / rake test / rspec / lint** | [docs/conventions/testing.md](docs/conventions/testing.md) | P1 |
| **多会话并发 / 多 tab 训练** | [docs/architecture/multi-session.md](docs/architecture/multi-session.md) | P2 |
| **新分支初始化/部署** | [docs/conventions/new-branch.md](docs/conventions/new-branch.md) | P2 |
| **环境变量 / 平台约定** | [docs/conventions/environment.md](docs/conventions/environment.md) | P2 |
| **为什么当初这样决定** | [docs/decisions/](docs/decisions/) (ADR) | 按需 |
| **历史修复记录**（只读，勿模仿） | [docs/archive/](docs/archive/) | 仅排查 |

## 🚨 硬规则（违反 = 犯错 = 重做）

1. **修 data_version / 模型定义 / 数据加载流程之前** → 必读 [data-version.md](docs/architecture/data-version.md) + 相关 ADR。
2. **创建业务表** → 用 `rails g model` / `rails g models`（自动加 `data_version`）。❌ 禁止手写 `rails g migration CreateXxx`。
3. **加 baseline 数据** → 只走 `app/validators/support/data_packs/v1/`。❌ `db/seeds.rb` 不是入口。
4. **三件套**（`data_version_excluded!` + `unscope default_scope` + `skip_callback :set_data_version`）**仅限系统表**：Administrator / Session / AdminOplog / ValidatorExecution / ActiveStorage\*。❌ 业务表绝不用。
5. **会话结束前** → 按本文末 [📝 Session-End Checklist](#-session-end-checklist) 更新 wiki。

### 📛 反例代码（直接贴这里，别去猜）

> 以下代码**曾造成实际事故**，`rake docs:lint` 会静态扫描复现。见到这类 pattern 立刻停手。

```ruby
# ❌ 反例 1：业务表用三件套（污染 baseline，违反 ADR-001/003）
class Category < ApplicationRecord          # Category 是业务表！
  data_version_excluded!                     # ← 只允许系统表
  default_scope { unscope(where: :data_version) }
  skip_callback :create, :before, :set_data_version
end
# ✅ 正确：确保 migration 含 data_version 列，删掉三件套。流程见 adding-models.md 场景 E
```

```ruby
# ❌ 反例 2：simulate 里创建 data_version='0' 记录（永久污染 baseline）
def simulate
  CartItem.create!(user: @user, product: @product, data_version: '0')
end
# ✅ 正确：simulate 必须用 @data_version
def simulate
  CartItem.create!(user: @user, product: @product, data_version: @data_version)
end
```

```ruby
# ❌ 反例 3：data pack 用 find_or_create_by!（语义混淆、慢、绕不过 callback）
Product.find_or_create_by!(name: '苹果') { |p| p.price = 12 }
# ✅ 正确：insert_all（base.rb 已清理干净，直接插）
Product.insert_all([{ name: '苹果', price: 12, data_version: '0', ... }])
```

## 🔎 如何在文档里查东西
- **Agent**：先看上面路由表 → `grep -rn "keyword" docs/` → `file_reader` 精读
- **人类开发者**：VSCode + Foam 扩展（Obsidian 替代，支持 `[[WikiLink]]` + 图谱）。安装提示见 `.vscode/extensions.json`
- **浏览指南**：[docs/HOW_TO_BROWSE.md](docs/HOW_TO_BROWSE.md)

---

## Rails 平台样板（初次上手必读）

### Startup Command
`bin/dev` — **不要**直接用 `rails s`（js/css 加载问题）。

### Tech Stack（不增不减、不升不降）
Ruby on Rails 7.2 · Tailwind v3 · Figaro · PostgreSQL · Active Storage · Kaminari · Puma · RSpec · Stimulus + Turbo（Stream 响应，**不**用 Frame / `stream_from`）· ActionCable（solid_queue，**不**用 Redis）· FriendlyId。

### 什么时候需要重启
Rails 默认热加载。**需要重启**的情况：
- `config/` 下的文件（除 `config/routes.rb`）
- `Gemfile`、`config/application.yml`、`config/appname.txt`
- **跑完** `rails g authentication` / `rails g stripe_pay` / `rails g llm` 后必须 `touch tmp/restart.txt`

### MANDATORY PROJECT WORKFLOW（初次上手，严格按顺序）

**Step 1**：`echo "YourAppName" > config/appname.txt`，再改 `application.css` + `tailwind.config.js` 的设计系统变量（HSL 颜色 + 语义 token）。`npm run build:css` 固化。**未完成 Step 1 不准建 model/controller**。

**Step 2**：建静态 demo → `app/views/shared/demo.html.erb`（纯 HTML + Tailwind，无 JS/无模型/无数据；占位文本 + Unsplash 图片；**只写 body**，layout 已存在；无 `home/index.html.erb` 时自动路由为首页）。

**Step 3**：启动项目 + `curl http://localhost:<PORT>/` 确保无错。

**Step 4**：现在可以建 model / controller / feature 了。认证/支付/LLM 用下面的 generator，**不要手写 User/Order/Payment**。

**Step 5**（交付前）：`rake test` 全绿——**绝不妥协**。计划任务时必须把"跑 rake test"列为一项。

### 常用 Generator
| 目标 | 命令 | 备注 |
|---|---|---|
| 业务模型（批量） | `rails g models product name:string + category name:string` | 自动加 data_version |
| 认证系统 | `rails g authentication [--navbar-style=STYLE]` | 事前确保无 User |
| 假支付 | `rails g stripe_pay [--auth]` | 生成 Payment（不是 Order）；用 polymorphic `:payable` |
| LLM | `rails g llm` | 配 `LLM_BASE_URL/KEY/MODEL`；优先 `LlmStreamJob` 流式 |
| Service | `rails g service xxx` | 不要手写 |
| Admin CRUD | `rails g admin_crud xxx` | 模型先建好 |
| Controller | `rails g controller xxx [--auth] [--single]` | — |
| Channel | `rails g channel xxx [--auth]` | 同时生成 `.ts`，WS + UI 合一 |
| Stimulus controller | `rails g stimulus_controller xxx` | 不要手写 |
| PWA | `rails g pwa` | 自动读 appname + 主题色 |

Admin 功能不要在 User model 里重造；`Administrator` 系统已存在。

### 代码质量

**FAIL FAST**：`nil` / 抛错 优于默认值掩盖缺失数据；早验证、显式验证；不要"安静失败"。

**注释**：最少；英文；解释 WHY，不复读 WHAT；不写废话。

### 永不修改的文件
`application.html.erb`、`admin/base_controller.rb`、`clipboard_controller.ts`、`dropdown_controller.ts`、`theme_controller.ts`。

---

## 📝 Session-End Checklist (Agent 必读)

> **灵感来自 [Karpathy's LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)**：
> LLM 不只写代码，也必须维护 wiki。**代码改完不代表任务结束**——wiki 没更新就等于知识流失了。

### 每次会话结束前 (before commit)

- [ ] **代码变更 → wiki 同步**：对照 [Documentation Map](#-documentation-map--按问题类型查)，凡涉及的文档都要更新 `updated_at`，并修改相关段落
- [ ] **新引入约定 → 新开 ADR**：在 `docs/decisions/ADR-NNN-*.md` 记录 Context/Decision/Consequences
- [ ] **推翻旧约定** → 旧 ADR 改 `status: Superseded by ADR-NNN`，新 ADR 写 `supersedes: ADR-XXX`
- [ ] **新增模型** → `docs/models/<name>.md` 至少占位，加到 `docs/models/INDEX.md` 表格
- [ ] **一次性修复** → 不要加到 wiki 主页；写在 commit message 里或 `docs/archive/`
- [ ] **验证**：`bin/rake docs:lint` 通过（broken link / 旅行残留 / 反例代码复现）

### 何时开 ADR vs 更新现有文档

| 情况 | 去哪里 |
|---|---|
| 小改字段/修 bug/加单元测试 | 只更新对应 entity page |
| 引入**可能重复出现**的新模式（命名、流程、API 形态） | 更新 conventions/ |
| **改变基本假设**（数据流、隔离策略、架构层级） | 必开 ADR |
| 一次性历史修复 | `docs/archive/`，wiki 不提 |

### wiki 维护的三个反模式（别犯）

1. ❌ **修完代码就 commit，不管文档** → 下次 Agent 仍会犯同样错
2. ❌ **新开 `XXX_FIX.md`** → 流水账污染仓库。结论合并到 wiki，过程放 archive
3. ❌ **同一主题多份文档并存矛盾** → wiki 原则是"compiled once, kept current"，旧文档要么更新要么标 `status: superseded`
