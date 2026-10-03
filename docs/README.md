# 文档索引 (Docs index)

所有文档使用中文，技术术语附英文。代码与文档在同一个 commit 更新 (见 [CONTRIBUTING.md](../CONTRIBUTING.md))。

| 目录 | 文档 | 内容 |
|---|---|---|
| — | [STATUS.md](STATUS.md) | **项目状态**：v0.1.0 原型验证完成、当前进度 (已完成待 Boss 验收的项、暂停 / 延期项、已知遗留)、设计评审 (待 Boss 评审 MCP / Gmail / Memory 设计稿)、功能状态、已知限制、未测项、下一步 |
| — | [CHANGELOG.md](CHANGELOG.md) | 更新日志 (Keep a Changelog + SemVer) |
| — | [ROADMAP_NEXT.md](ROADMAP_NEXT.md) | 提醒、附件、多模态、TTS、安全、部署、CI 与 Web 的后续规划草案；未授权开工 |
| product/ | [FEATURES.md](product/FEATURES.md) | 功能清单、API 摘要、SSE 事件格式 |
| design/ | [ARCHITECTURE.md](design/ARCHITECTURE.md) | 两个项目的架构、模块、依赖规则、依赖管理 (SPM / uv)、数据模型 |
| design/ | [MULTI_AGENT_DESIGN.md](design/MULTI_AGENT_DESIGN.md) | 多 Agent 权限模型、上下文隔离、护栏、审计、迁移、设置页 / TTS 扩展 |
| design/ | [MCP_CAPABILITY.md](design/MCP_CAPABILITY.md) | **设计 v1.0 已批准；M1 与 M2 已实现**（schema v8：免授权 Learn / AWS、按服务同意、会话复用、审计、后台同步、熔断。字段对照见 §18）。其上的插件 P1 见下一行。M3 起（OAuth、HITL、Gmail、自定义 URL）仍是设计，未实现。`frontend/web` 冻结，没有 MCP 界面 |
| design/ | [PLUGIN_DESIGN.md](design/PLUGIN_DESIGN.md) | **v1.0 已定稿并实现（schema v10）**：插件是用户看到的产品层，MCP 是能力。新账号不预装；内置天气 / 提醒与外部 Learn / AWS。字段对照见 MCP §18.4。`frontend/web` 冻结，插件 P1 没有 Web 对应 |
| design/ | [REMINDER_PUSH_DESIGN.md](design/REMINDER_PUSH_DESIGN.md) | **v1.0 已定稿，R1 已实现（schema v11）**：提醒状态机、本地通知、收件箱与偏好。字段对照见 §8。SQL 在 `db/reminder_store.py`。APNs 未做。`frontend/web` 冻结 |
| design/ | [ATTACHMENTS_DESIGN.md](design/ATTACHMENTS_DESIGN.md) | **v1.0 定稿 (P1 未实现)**：聊天图片附件 — DeepSeek 视觉核查、P0 模型迁移 (已完成)、iOS PhotosPicker (每条 1 张、GIF 动画)、两步上传、按需召回 (图片描述 + 回指时重发原图)、委派转发图片、带图轮次写操作确认、schema v12、字段对照、ATT-xx 测试；Q1–Q12 Boss 已全部决定 |
| design/ | [ATTACHMENT_STORAGE_RESEARCH.md](design/ATTACHMENT_STORAGE_RESEARCH.md) | **调研 (已采纳)**：附件存储 — 本地磁盘 + SQLite 元数据 + 薄存储接口、鉴权代理 + `no-store`、原子写入、孤儿对账、备份、FileVault + 0700、上云迁移路径 (Sonic) |
| design/ | [GMAIL_CAPABILITY.md](design/GMAIL_CAPABILITY.md) | **设计稿 (未实现)**：Gmail 能力 — 主路径经 Google 官方 Gmail MCP、候选服务器评估、直连 Gmail API 备用路径、Scope、发送人工确认 (HITL)、权限 / 委派集成、提示注入、里程碑与开放问题 |
| design/ | [EXECUTION_STATE.md](design/EXECUTION_STATE.md) | **已实现 (iOS Core)**：执行状态机的状态、转移表、SSE 事件映射，以及以后对接头像实验室的状态映射 |
| design/ | [MEMORY_GROWTH.md](design/MEMORY_GROWTH.md) | **实施方案 v1.0 (Boss 已批准；M1 已实现，schema v4，M2~M5 未开始)**：以记忆为核心的 Bot 成长体系 — 显式记忆与确认卡片、隐式候选、分层作用域 (全局 / Bot / 摘要)、风格校准、主动建议、快捷提问、了解程度与月度回顾；`memories` 表 / schema v4、API、prompt 注入与 Token 预算、权限与委派隔离、隐私与防注入、iOS 界面、MEM-xx 测试、M1~M5 里程碑与估算、开放问题 |
| testing/ | [TEST_CASES_v0.1.md](testing/TEST_CASES_v0.1.md) | 全部测试用例与结果 (迭代 1、迭代 2、重构回归)、缺陷列表 |
| ops/ | [RUN_LOCAL.md](ops/RUN_LOCAL.md) | 本地运行后端 / iOS / 测试 |
| ops/ | [DELIVERY.md](ops/DELIVERY.md) | 打包与交付、Docker、交付检查清单 |

项目 README：[根目录](../README.md) · [backend](../backend/README.md) · [frontend](../frontend/README.md)
截图：[assets/screenshots/](../assets/screenshots/) (`web/` Web SPA，`ios/test/` 迭代 1 T*，`ios/regress/` 迭代 2 R*；均早于 2026-10-01 的界面改动)
