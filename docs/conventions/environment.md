---
topic: environment
updated_at: 2026-05-04
status: current
related:
  - new-branch.md
  - adding-models.md
supersedes: ../archive/project.md
---

# 环境与平台约定（Environment）

This project follows Rails 7.2 standard architecture with specific conventions optimized for stable AI-assisted code generation.

**Design Philosophy**: Built for non-coders - prioritizing simplicity and maintainability over powerful features.

## Environment

**Runtime Environment**: Runs by default in a Cloud-native environment (Clacky CDE), accessible via public URLs

## Environment Variables

### Out-of-the-Box Configuration
The following services are **pre-configured** and ready to use:

| Service | Variables | Status |
|---------|-----------|--------|
| **Email** | SMTP_ADDRESS, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD, SMTP_DOMAIN | ✅ Ready |
| **LLM** | LLM_BASE_URL, LLM_API_KEY, LLM_MODEL | ✅ Ready (DeepSeek-V3) |
| **Stripe** | STRIPE_PUBLISHABLE_KEY, STRIPE_SECRET_KEY | ✅ Ready (Test mode) |

### CLACKY_* Variables
`CLACKY_*` variables are **platform-injected** and should **NEVER** be used directly in code.

## Deployment

**Status**: ✅ Production-ready with zero configuration

- **Database**: PostgreSQL pre-configured
- **Storage**: Cloud storage (S3/GCS) would be used, already handled
- **Deployment**: One-click via `Dockerfile` - push to trigger automatic builds

## Port Detection

Auto-detects port in priority order:
1. `ENV['APP_PORT']` (from shell or injected)
2. `ENV['PORT']`
3. `.env` file at project root (loaded by `bin/dev`, see [ADR-011](../decisions/ADR-011-bin-dev-loads-dotenv.md))
4. `config/application.yml` APP_PORT
5. Auto: 3001 (submodule) / 3000 (standalone)

Use `EnvChecker.get_app_port` in code - never hardcode ports.

### 多派生项目本地并跑：`.env` + 端口分配表

同机并跑多个 rlbox 派生品牌时，各项目用 `.env`（gitignored）锁定一个私有端口：

```bash
# 首次 fork 后
cp .env.example .env
# 编辑 .env，改成本项目分配的端口
```

当前分配表维护在 rlbox 模板的 `.env.example`（唯一真相源）：

| 项目 | 端口 |
|---|---|
| Goomart | 11601 |
| IdleSwap | 11602 |
| Kangoo | 11603 |
| planet | 11604 |
| duvy | 11605 |

`bin/dev` 启动时会**先**解析 `.env`（纯 Ruby 12 行，无 dotenv gem 依赖），再走 `EnvChecker`。详见 [ADR-011](../decisions/ADR-011-bin-dev-loads-dotenv.md)。

**`bin/db_init` 同样会读 `.env`**（2026-05-04 扩展）：worktree 场景下 `.env` 可以写 `WORKTREE_DEV_DB=xxx` / `WORKTREE_TEST_DB=xxx`，`bin/db_init` 会读到并初始化到正确的库，与 `bin/dev` 启动的 puma 看到同一个 DB。以前 `bin/db_init` 不读 `.env`，裸跑会 fallback 到默认库名（`<app>_development`），导致 baseline 被灌到错误的库，puma 报 `NoDatabaseError`。

## Generator Auto-Configuration

Running these generators **automatically** updates `config/application.yml`:
- `rails g authentication` - OAuth providers
- `rails g stripe_pay` - Payment configuration
- `rails g llm` - LLM service setup

Check the generated config - if defaults exist, no manual setup needed.
