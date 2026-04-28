---
topic: testing
updated_at: 2026-04-28
allow_legacy_models_for_contrast: true
related:
  - architecture/validator-linter.md
  - conventions/validator-writing.md
  - conventions/frontend.md
source_files:
  - spec/
  - lib/tasks/validator_lint.rake
  - lib/tasks/docs.rake
---

# 🧪 测试与静态检查

## 1. 测试金字塔

| 层 | 命令 | 何时跑 |
|---|---|---|
| **单个 request spec** | `bundle exec rspec spec/requests/xxx_spec.rb --format documentation` | 改 controller / view 后 |
| **全量** | `rake test` | 改大东西、交付前 |
| **前端架构校验** | 包含在 `rake test` | 自动跑 |
| **Validator 静态检查** | `rake validator:lint` | 写/改 validator 后 |
| **文档静态检查** | `rake docs:lint` | Session-end checklist |

`rake test` 一次只显示 5 条失败，需要反复跑（最多 10 轮）直到全绿。

## 2. 只用 rspec，不用 -v

```bash
# ✅
bundle exec rspec spec/requests/xxx_spec.rb --format documentation

# ❌
bundle exec rspec -v ...     # -v 被占做版本
```

## 3. 前端架构校验（强制）

`rake test` 自动跑：

| 校验器 | 作用 |
|---|---|
| `spec/javascript/stimulus_validation_spec.rb` | Stimulus controller ↔ view 一致 |
| `spec/javascript/turbo_architecture_validation_spec.rb` | Turbo Stream 模式 |
| `spec/javascript/project_conventions_validation_spec.rb` | 命名 / 路径 / 入口 |

**所有错误都是真实违规**——必须修，不许 dismiss。

## 4. Validator Lint

`rake validator:lint` 检测：

| 级别 | 检查 |
|---|---|
| HIGH | 用了废弃字段 |
| HIGH | verify 的 where 没加 `data_version: @data_version` |
| MEDIUM | 潜在 N+1（缺 `.includes`） |
| MEDIUM | View 里用了 validator 声明但模型里不存在的字段 |

配置（**可选**）：`config/validator_lint_rules.yml`。没这个文件 lint 依然工作。

**单个 validator**：`rake validator:lint_single[v001]`

## 5. 文档 Lint

`rake docs:lint` 检测：

| 规则 | 说明 |
|---|---|
| Broken links | `docs/` 中 markdown 链接指向不存在的文件 |
| Frontmatter | `docs/architecture/` `conventions/` `decisions/` `models/` 每个页需要有 topic |
| 旅行残留词 | 历史旧业务词（`allow_legacy_models_for_contrast: true` 可豁免） |
| archive 引用上下文 | `archive/*.md` 的链接必须在 "References / 历史参考" 段下 |
| **反面代码** | 扫 `app/**/*.rb` 是否引入三件套到业务表 / simulate 里 `data_version: '0'` / data_pack 里 `find_or_create_by!` |

配套：
- `rake docs:stats` — 页数、单词数
- `rake docs:orphans` — 无反向链接的页

## 6. 认证 curl

```bash
rails dev:token[test@example.com]   # 输出 token + curl 样例（无 user 自动创建）
curl -H 'Authorization: Bearer <token>' http://localhost:<PORT>/path
```

## 7. 数据库操作只用 rails runner

```bash
# ✅
rails runner "p Product.count"

# ❌ 不要用 rails console
```

## 8. 临时文件

一律写到 `tmp/`（git ignore 内）。**不要** 散到 `/tmp` 或根目录。

## 9. View 缺失错误

> 看到 `"Views for xxx are not yet developed"`，**立即创建对应 view 文件，再跑 test**。

## 10. 交付前 checklist

- [ ] `rake test` 全绿
- [ ] `rake validator:lint` 全绿（如改过 validator）
- [ ] `rake docs:lint` 全绿（会话结束前）
- [ ] `rake validator:validate_packs` 全绿（如改过 data pack）
- [ ] `rake validator:reset_baseline` 幂等（跑两次不报错）

## 11. 延伸阅读

- [validator-linter.md](../architecture/validator-linter.md) — Linter 实现
- [data-packs.md](../architecture/data-packs.md) — `validate_packs` 规则
- CLAUDE.md → Session-End Checklist
