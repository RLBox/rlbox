---
topic: adr-011
updated_at: 2026-05-04
status: accepted
decision_date: 2026-05-01
related:
  - conventions/environment.md
---

# ADR-011: bin/dev 加载 .env 实现本地端口隔离（多派生项目并跑）

## Status
Accepted (2026-05-01)

## Context

rlbox 模板衍生出多个独立品牌项目（Goomart、IdleSwap、Kangoo、planet、duvy…），它们都要在**同一台开发机**上**同时**运行以便横向对比、调试、演示。

### 问题现状

1. **默认都抢 3000**：Rails 默认 `PORT=3000`，多个项目同启会端口冲突。
2. **项目间分配约定不落地**：曾靠口头约定"Goomart 11601 / IdleSwap 11602 ..."，但运行时没有机制读取——各项目 `bin/dev` 启动时 `EnvChecker.get_app_port` 走兜底逻辑返回 3000。
3. **`.env` 文件被误以为"自动生效"**：多个项目 `.env` 里写了 `APP_PORT=xxx`，但因为 Gemfile 用 `figaro`（只读 `config/application.yml`）而非 `dotenv`，`.env` 实际未被任何代码加载，纯装饰。
4. **进化版本未回植**：IdleSwap / Kangoo 的 `bin/dev` 已私下加了手写 .env 解析，但 rlbox 模板和其他派生项目没同步，新 fork 出去的项目继续沿用坏行为。

### 备选方案

| 方案 | 优点 | 缺点 |
|---|---|---|
| 引入 `dotenv-rails` gem | 社区标准 | 增加依赖；与项目既有 `figaro` 职责重叠 |
| 让 `figaro` 读 `.env` | 统一入口 | figaro 不支持；要写 monkey patch |
| **bin/dev 里手写 12 行 parser** | 零依赖；精准只影响本地开发启动时机 | 重复造轮子（但轮子极小） |
| 依赖 shell `source .env` | 不动代码 | 容易忘；CI/新机器翻车 |

## Decision

在 `bin/dev` 的 **foreman 启动前、EnvChecker 加载前**插入 12 行纯 Ruby 的 `.env` 解析代码：

```ruby
# Load .env if present (gives .env highest priority before EnvChecker reads ENV)
env_file = File.expand_path('../.env', __dir__)
if File.exist?(env_file)
  File.readlines(env_file).each do |line|
    line = line.strip
    next if line.empty? || line.start_with?('#')
    key, value = line.split('=', 2)
    ENV[key.strip] ||= value.strip if key && value
  end
end
```

**优先级链**：`ENV['APP_PORT']` > `.env` > `config/application.yml` > EnvChecker 自动检测（submodule 3001 / 独立 3000）。

### 端口分配表（本地约定）

| 项目 | 端口 |
|---|---|
| Goomart | 11601 |
| IdleSwap | 11602 |
| Kangoo | 11603 |
| planet | 11604 |
| duvy | 11605 |
| 下一个派生项目 | 11606... |

### 配套规则

1. `.env` 继续 `.gitignore`（不入库，每台机各自决定）
2. rlbox 模板提供 `.env.example`，新项目 fork 后 `cp .env.example .env` 并改端口
3. 派生项目文档中**不需重复端口表**，统一在 rlbox 模板的 `.env.example` 里维护

## Consequences

### Positive
- 多项目并跑不再踩坑，`bin/dev` 启动时 `.env` 即生效
- 不引入新 gem，零迁移成本
- `.env` 文件从"装饰"变成"事实生效的配置源"
- 新派生项目从模板 fork 即天生支持

### Negative
- 12 行代码在 6 个项目 × 每项目 2 个脚本（`bin/dev` + `bin/db_init`）各存一份。未来若要扩展 .env 解析能力（多行值、变量展开、引号处理），需要同步 ~12 份
- 不支持 `.env.production` / `.env.test` 这种分环境文件（当前需求不需要，production 走 figaro/ENV）

### Migration / Rollout (2026-05-01)
- ✅ 同步 `bin/dev` 至 Goomart / planet / duvy / rlbox（IdleSwap / Kangoo 已是新版）
- ✅ 实测：Goomart@11601 / planet@11604 / duvy@11605 三连 HTTP 200
- ✅ rlbox 新增 `.env.example` 保存端口分配表

### Extension: bin/db_init also loads .env (2026-05-04)

**触发事故**：duvy 上用 `box-worktree-rails-setup` skill 开 worktree 后，`.env` 里写了 `WORKTREE_DEV_DB=duvy_db_checkin`。`bin/dev` 正确读入并让 puma 连这个库；但独立跑 `bin/db_init` 时脚本**不读 .env**，fallback 到 `duvy_development`，把 baseline 灌进了错误的库。puma 报 `NoDatabaseError: duvy_db_checkin`，首页 500。

**修复**：把 `bin/dev` 的 14 行 `.env` parser 同款复制到 `bin/db_init` 开头（`APP_ROOT` 定义之后、`system!` 定义之前）。让两个脚本看到同一套 ENV。

**影响范围**：任何读 `ENV['WORKTREE_DEV_DB']` / `ENV['WORKTREE_TEST_DB']` 的独立 ruby 脚本都有这个风险。目前 `bin/db_init` 是唯一一个，已全部修复。

**同步 Rollout**：
- ✅ rlbox 模板
- ✅ Goomart / IdleSwap / Kangoo / planet / duvy 五个 fork

**与原决策的关系**：不是撤销 ADR-011，是对其"只影响 `bin/dev` 启动"的边界做局部扩展。原则不变：零 gem、纯 Ruby、12~14 行可读的 parser，每个需要读 `.env` 的脚本自带。如果未来第 3 个脚本也需要，就该认真考虑 Future Options 里的 dotenv-rails 方案了。

## Future Options (暂不做)

如果后期出现以下情况，可以考虑升级：
- 需要多环境 .env（`.env.development` / `.env.test`）→ 引入 `dotenv-rails`
- .env 要支持更复杂语法（变量展开、多行、引号）→ 引入 `dotenv-rails`
- 其他进程（非 bin/dev 启动的 rake、rspec）也要 .env → 引入 `dotenv-rails`
