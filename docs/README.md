# 文档索引 (Docs index)

- [Bot 个性化 Feed](tasks/2026-10-17-personal-feed.md)：统一信息流、底部「发现」Tab、后台采集与当前实施状态。
- [Feed 验证记录](testing/2026-10-17-personal-feed.md)：四类真实来源、HTTP/回归证据、原生与用户验收边界。

- [2026-10-16 Main 集成与 schema v35](tasks/2026-10-16-main-integration.md)

主 Bot第一版已实现并集成本地main，当前自动验证与手动入口见[交付记录](testing/2026-10-13-primary-bot.md)，运行说明见[后台模块](../backend/verabot/services/owned_tasks/README.md)。代码已合入本地main，常驻后台尚未部署。


当前整合状态见 [2026-10-12 Main 集成交付](testing/2026-10-12-main-integration.md)。下方设计文档与旧验证记录保留其历史范围；当前功能与验收以 STATUS 和本轮交付为准。

当前功能与并行开发状态见 [2026-10-13 功能盘点](testing/2026-10-13-project-inventory.md)，上轮整合/设备证据见 [2026-10-12 Main 集成交付](testing/2026-10-12-main-integration.md)。下方设计文档与旧验证记录保留其历史范围；当前功能与验收以 STATUS 和最新盘点为准。

本日稍后群v2已由`a01b2d7`合入main，源码schema v25，真实验收仍待用户判定；主Bot方案已获确认，具体[实施计划](superpowers/plans/2026-10-13-primary-bot.md)待审阅和选择执行方式。

所有文档使用中文，技术术语附英文。代码与文档在同一个 commit 更新 (见 [CONTRIBUTING.md](../CONTRIBUTING.md))。

| 目录 | 文档 | 内容 |
|---|---|---|
| — | [STATUS.md](STATUS.md) | **项目状态**：v0.1.0 原型验证完成、当前进度 (已完成待 Boss 验收的项、暂停 / 延期项、已知遗留)、设计评审 (待 Boss 评审 MCP / Gmail / Memory 设计稿)、功能状态、已知限制、未测项、下一步 |
| — | [CHANGELOG.md](CHANGELOG.md) | 更新日志 (Keep a Changelog + SemVer) |
| specs/ | [long-reply-collapse.md](specs/long-reply-collapse.md) | **私聊长回复折叠**（iOS）：超过 1500 字或 40 行的 Bot 回复默认只渲染截断预览 + 底部渐隐，「展开 / 收起」切换；阈值与截断规则在 `VeraBotCore.LongReplyCollapse` |
| specs/ | [bot-opening-message.md](specs/bot-opening-message.md) | **Bot 动态开场词 Phase 1**：时段/日子/人设/轻量称呼/关系阶段；混合生成；天气为 Phase 2；Web 冻结 |
| — | [ROADMAP_NEXT.md](ROADMAP_NEXT.md) | 提醒、附件、多模态、TTS、安全、部署、CI 与 Web 的后续规划草案；未授权开工 |
| product/ | [FEATURES.md](product/FEATURES.md) | 功能清单、API 摘要、SSE 事件格式 |
| product/ | [2026-10-08-playful-world-discussion.md](product/2026-10-08-playful-world-discussion.md) | Vera Bot 私人小世界、游乐场玩法、底部 Tab 与阶段性产品讨论；含 3D 魔方候选方案（未实现，小岛 Tab 当前隐藏） |
| superpowers/specs/ | [2026-10-09-bot-travel-design.md](superpowers/specs/2026-10-09-bot-travel-design.md) | Bot 旅行第一版：真实地点轻探索、分阶段揭晓、旅行相册与五分钟 iOS 原型范围 |
| superpowers/specs/ | [2026-10-11-bot-group-chat-design.md](superpowers/specs/2026-10-11-bot-group-chat-design.md) | Bot 群聊第一版设计：伙伴讨论、点名、群历史与执行边界 |
| superpowers/specs/ | [2026-10-12-group-intent-and-handoff-design.md](superpowers/specs/2026-10-12-group-intent-and-handoff-design.md) | 群聊后续设计：移除默认回应者、按意图分配、动态澄清与任务交接；全文已确认，隔离工作树已实施/修复并待用户验收，尚未合入 main |
| superpowers/plans/ | [2026-10-12-group-intent-and-handoff.md](superpowers/plans/2026-10-12-group-intent-and-handoff.md) | 群聊意图与接力实施计划：迁移、澄清、结构化协作、服务端执行、v2 API 与 iOS；本地副本保留原计划，实际工作树进度见最新盘点 |
| superpowers/specs/ | [2026-10-13-primary-bot-design.md](superpowers/specs/2026-10-13-primary-bot-design.md) | 主 Bot 接入讨论稿：身份/默认任务入口、持续步骤、阻塞求助、确认续跑、群边界及修改难度；待评审，未实施 |
| testing/ | [2026-10-13-project-inventory.md](testing/2026-10-13-project-inventory.md) | 主线 v23、独立群 v2 开发、执行/权限边界与本轮 36+2 离线验证 |
| superpowers/plans/ | [2026-10-11-bot-group-chat.md](superpowers/plans/2026-10-11-bot-group-chat.md) | 群聊 G0–G3 任务；当前完成 G0/G1/G2，G3 待验收 |
| testing/ | [2026-10-11-bot-group-chat-g2.md](testing/2026-10-11-bot-group-chat-g2.md) | 顺序执行、停止/恢复/重试、iOS 正式接线与验证 |
| testing/ | [2026-10-11-bot-group-chat-g1.md](testing/2026-10-11-bot-group-chat-g1.md) | 群管理 API、轮次存储、Swift 协议与验证边界 |
| testing/ | [2026-10-11-bot-group-chat-preview.md](testing/2026-10-11-bot-group-chat-preview.md) | Debug 群聊预览入口、范围、构建结果和用户验收边界 |
| superpowers/plans/ | [2026-10-09-bot-travel.md](superpowers/plans/2026-10-09-bot-travel.md) | Bot 旅行第一版实现步骤与核对清单 |
| design/ | [CHAT_SPEECH_PLAYBACK.md](design/CHAT_SPEECH_PLAYBACK.md) | **已确认并修复，待设备验收**：对话朗读退出规则、临时弹层例外、音频会话释放、旧回调隔离与回归证据 |
| design/ | [2026-10-13-ui-consistency-follow-up.md](design/2026-10-13-ui-consistency-follow-up.md) | UI 一致性后续方案：弹出页高度与结构、列表行密度和跨页面核对范围；本轮未实施 |
| design/ | [ARCHITECTURE.md](design/ARCHITECTURE.md) | 两个项目的架构、模块、依赖规则、依赖管理 (SPM / uv)、数据模型 |
| design/ | [MULTI_AGENT_DESIGN.md](design/MULTI_AGENT_DESIGN.md) | 多 Agent 权限模型、上下文隔离、护栏、审计、迁移、设置页 / TTS 扩展 |
| design/ | [MCP_CAPABILITY.md](design/MCP_CAPABILITY.md) | **设计 v1.0 已批准；M1–M4 已实现，真实 OAuth 待验收**（schema v8：免授权 Learn / AWS、按服务同意、会话复用、审计、后台同步、熔断。字段对照见 §18）。其上的插件 P1 见下一行。M3 确认卡片已按用户指定模拟器标准验收；M4 OAuth 实现与真实授权验收分开跟踪。`frontend/web` 冻结，没有 MCP 界面 |
| design/ | [PLUGIN_DESIGN.md](design/PLUGIN_DESIGN.md) | **v1.0 已定稿并实现（schema v10）**：插件是用户看到的产品层，MCP 是能力。新账号不预装；内置天气 / 提醒与外部 Learn / AWS。字段对照见 MCP §18.4。`frontend/web` 冻结，插件 P1 没有 Web 对应 |
| design/ | [MCP_AUTH_CONNECTORS_PLAN.md](design/MCP_AUTH_CONNECTORS_PLAN.md) | **连接器与 OAuth 已实现，真实授权待验收**：需授权 MCP 连接器 — 静态令牌（GitHub fine-grained PAT 只读）与 OAuth 2.1（PKCE + PRM + DCR）统一抽象、iOS Keychain → 后端加密存储、`needs_auth` 流程、主流服务对照（Vercel / Linear / Notion / Sentry / Slack / Figma / Atlassian / Stripe）、CONN-xx 测试、P1–P3 分期与待决定事项 |
| design/ | [REMINDER_PUSH_DESIGN.md](design/REMINDER_PUSH_DESIGN.md) | **v1.0 已定稿，R1 已实现（schema v11）**：提醒状态机、本地通知、收件箱与偏好。字段对照见 §8。SQL 在 `db/reminder_store.py`。APNs 未做。`frontend/web` 冻结 |
| design/ | [ATTACHMENTS_DESIGN.md](design/ATTACHMENTS_DESIGN.md) | **v1.0 定稿；图片与文件附件已实现，设备完整验收待完成**：聊天图片附件 — DeepSeek 视觉核查、P0 模型迁移 (已完成)、iOS PhotosPicker (每条 1 张、GIF 动画)、两步上传、按需召回 (图片描述 + 回指时重发原图)、委派转发图片、带图轮次写操作确认、schema v12、字段对照、ATT-xx 测试；Q1–Q12 Boss 已全部决定 |
| design/ | [ATTACHMENT_STORAGE_RESEARCH.md](design/ATTACHMENT_STORAGE_RESEARCH.md) | **调研 (已采纳)**：附件存储 — 本地磁盘 + SQLite 元数据 + 薄存储接口、鉴权代理 + `no-store`、原子写入、孤儿对账、备份、FileVault + 0700、上云迁移路径 (Sonic) |
| design/ | [GMAIL_CAPABILITY.md](design/GMAIL_CAPABILITY.md) | **设计稿 (未实现)**：Gmail 能力 — 主路径经 Google 官方 Gmail MCP、候选服务器评估、直连 Gmail API 备用路径、Scope、发送人工确认 (HITL)、权限 / 委派集成、提示注入、里程碑与开放问题 |
| design/ | [EXECUTION_STATE.md](design/EXECUTION_STATE.md) | **已实现 (iOS Core)**：执行状态机的状态、转移表、SSE 事件映射，以及以后对接头像实验室的状态映射 |
| design/ | [MEMORY_GROWTH.md](design/MEMORY_GROWTH.md) | **实施方案 v1.0 (Boss 已批准；M1–M5 已实现，M3/M4 与主要 M5 已验收，真实本地向量召回待单独验收)**：以记忆为核心的 Bot 成长体系 — 显式记忆与确认卡片、隐式候选、分层作用域 (全局 / Bot / 摘要)、风格校准、主动建议、快捷提问、了解程度与月度回顾；`memories` 表 / schema v4、API、prompt 注入与 Token 预算、权限与委派隔离、隐私与防注入、iOS 界面、MEM-xx 测试、M1~M5 里程碑与估算、开放问题 |
| testing/ | [TEST_CASES_v0.1.md](testing/TEST_CASES_v0.1.md) | 全部测试用例与结果 (迭代 1、迭代 2、重构回归)、缺陷列表 |
| ops/ | [RUN_LOCAL.md](ops/RUN_LOCAL.md) | 本地运行后端 / iOS / 测试 |
| ops/ | [DELIVERY.md](ops/DELIVERY.md) | 打包与交付、Docker、交付检查清单 |

项目 README：[根目录](../README.md) · [backend](../backend/README.md) · [frontend](../frontend/README.md)
截图：[assets/screenshots/](../assets/screenshots/) (`web/` Web SPA，`ios/test/` 迭代 1 T*，`ios/regress/` 迭代 2 R*；均早于 2026-10-01 的界面改动)

- [群聊 @ 输入与键盘回归](testing/2026-10-12-group-mention-keyboard.md)：25 项编辑器回归通过，2026-10-12 用户确认本轮交互修复验收通过。
- [Bot 群聊 G3 验证与验收交付](testing/2026-10-11-bot-group-chat.md)：自动回归、真实 HTTP 模拟提供者联调、GC-01～12 分项状态及隔离模拟器步骤。
- [群聊意图分配与任务交接](testing/2026-10-12-group-intent-and-handoff.md)：协议 v2、schema v24、离线/HTTP/Swift/模拟器构建证据及部署与人工验收边界。

- [移动端 SQLite 持久化](testing/2026-10-12-mobile-persistence.md)：列表、完整分页历史、草稿、修订快照与验收范围。
- [服务端定时任务](testing/2026-10-11-scheduled-tasks.md)：API、Scheduler/Worker、租约、预算与结果投递；main 集成使用 v23。
