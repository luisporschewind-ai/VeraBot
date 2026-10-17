# VeraBot — 私人 AI 助理团队 (Personal AI Agent Team)

## Bot 个性化 Feed（2026-10-17，独立开发工作区）

新增底部「发现」入口与公开新闻/短帖/视频/音频信息流。根据获准使用的记忆和显式主题建议关注计划，支持来源管理、收藏、负反馈及带引用的问 Bot 草稿。后端 schema v36、独立采集 worker 和原生页面已实现，完整 Swift Kit 368 项通过。按用户要求减少验证，保留已有真实采集与原生预览证据；最终构建状态见[验证记录](docs/testing/2026-10-17-personal-feed.md)。本任务未合入 main、未升级正式库或替换正式服务。见[任务记录](docs/tasks/2026-10-17-personal-feed.md)。

## 独立资料库（2026-10-15）

全局资料库汇总 Bot 私聊与群聊的文件和图片；Bot 主页分别展示文件、图片。清空对话后资料保留，已下载原件支持本地复用。后端 schema v34 已部署，模拟器与 iPhone 11 已安装 0.1.0 (2026101501)，待用户交互验收。见 [交付记录](docs/testing/2026-10-15-independent-library.md)。

## 本地对话阅读（2026-10-15）

iOS 私聊与群聊进入时先恢复 SQLite 历史和草稿、完成消息定位，再同步后端；断网时仍可翻阅已保存的消息。验证见 [离线进入记录](docs/testing/2026-10-15-offline-chat-entry.md)。

## 主 Bot 第一版

`codex/primary-bot`基于本地main `b81caed`实现日常负责人、明确交办/周期任务、持久求助与MCP确认续跑；schema v29。2026-10-14已提交并合入本地main（b68dfc4）；真实UI/模型与后台部署仍需验收。见[交付记录](docs/testing/2026-10-13-primary-bot.md)及[后台运行说明](backend/verabot/services/owned_tasks/README.md)。


> **v0.1.0 · 原型验证完成 (Prototype validated, feasible)** — 2026-09-30
> 91 条用例：通过 90 / 失败 0 / 跳过 1（发布时快照）。当前开发主线为 schema v23，已增加记忆成长、附件、群聊、联网搜索、本地持久化与服务端定时任务；功能和验收边界见 [2026-10-13 盘点](docs/testing/2026-10-13-project-inventory.md)及 [docs/STATUS.md](docs/STATUS.md)。

VeraBot 是一个**个人 AI 助理 (Personal AI Agent)** 平台，不是编程助手 (Coding Agent)。用户创建多个 Bot，每个 Bot 有自己的头像、昵称、人设 (Persona) 和自定义指令 (Instructions)，与用户 1:1 私聊。Bot 之间可以通过 `ask_bot` 做**多 Agent 协作 (Multi-Agent Collaboration)**，并受权限、上下文隔离和护栏 (Guardrails) 约束。
用户不需要填写 API Key：服务端统一用 `DEEPSEEK_API_KEY` 调用 DeepSeek (OpenAI 兼容接口)。

## 仓库结构 (Monorepo，两个可独立交付的项目)

```
VeraBot-v0.1/
├── backend/            # 后端项目 (FastAPI + SQLite, uv 管理依赖) → backend/README.md
├── frontend/           # 前端项目 → frontend/README.md
│   ├── ios/            #   SwiftUI App + 本地 Swift Package VeraBotKit (SPM)
│   └── web/            #   Web SPA (验收用，由后端托管)
├── docs/               # 文档 (中文 + 英文术语) → docs/README.md
├── assets/screenshots/ # 文档引用的截图 (web / ios)
├── scripts/            # 仓库级脚本：package_backend.sh (打包后端交付件)
├── CONTRIBUTING.md     # 提交规范、文档清单、SemVer
├── LICENSE             # MIT
└── README.md
```

| 项目 | 技术栈 | 依赖管理 | 一键运行 |
|---|---|---|---|
| [backend/](backend/README.md) | Python 3.12 · FastAPI · uvicorn · SQLite | **uv** (`pyproject.toml` + `uv.lock`，另导出 `requirements.txt`) | 双击 `backend/start.command` 或 `backend/start.sh` |
| [frontend/ios](frontend/README.md) | SwiftUI · iOS 17+ · Swift 6 严格并发 | **SPM** (本地包 `Packages/VeraBotKit`，暂无第三方依赖) | Xcode 打开 `VeraBot.xcodeproj` ⌘R，或 `frontend/scripts/run_ios.sh` |
| [frontend/web](frontend/README.md) | 原生 HTML / JS / CSS | 无 | 后端启动后访问 <http://127.0.0.1:8000/> |

## 快速开始 (Quick start)

```bash
cd backend && ./start.sh            # 首次：安装 uv → 同步依赖 → 创建 .env (提示输入 DeepSeek Key) → 初始化数据库 → 启动 :8000
open frontend/ios/VeraBot.xcodeproj # Xcode 里选 iPhone 模拟器 ⌘R；演示账号 demo / verabot2026
```

完整步骤见 [docs/ops/RUN_LOCAL.md](docs/ops/RUN_LOCAL.md)；交付 / 打包见 [docs/ops/DELIVERY.md](docs/ops/DELIVERY.md)。

## 文档 (Docs)

| 文档 | 内容 |
|---|---|
| [docs/README.md](docs/README.md) | 文档索引 |
| [docs/STATUS.md](docs/STATUS.md) | 项目状态、已知限制、下一步 |
| [docs/CHANGELOG.md](docs/CHANGELOG.md) | 更新日志 |
| [docs/product/FEATURES.md](docs/product/FEATURES.md) | 功能清单与 API 摘要 |
| [docs/design/ARCHITECTURE.md](docs/design/ARCHITECTURE.md) | 架构、模块划分、依赖规则、依赖管理 (SPM / uv) |
| [docs/design/MULTI_AGENT_DESIGN.md](docs/design/MULTI_AGENT_DESIGN.md) | 多 Agent 权限 / 上下文隔离 / 护栏 / 审计 |
| [docs/design/MCP_CAPABILITY.md](docs/design/MCP_CAPABILITY.md)、[GMAIL_CAPABILITY.md](docs/design/GMAIL_CAPABILITY.md) | MCP M1–M4 已实现，真实 OAuth 待验收；Gmail 邮件工具仍是未实现设计 |
| [docs/design/MEMORY_GROWTH.md](docs/design/MEMORY_GROWTH.md) | 记忆 M1–M5 已实现；M3/M4、主要 M5 已验收，真实本地向量效果单独跟踪 |
| [主 Bot 接入讨论稿](docs/superpowers/specs/2026-10-13-primary-bot-design.md) | 基于现有定时任务和群接力开发进度的方案、范围与难度；待评审，未实施 |
| [docs/testing/TEST_CASES_v0.1.md](docs/testing/TEST_CASES_v0.1.md) | 测试用例与结果 |

## 安全 (Security)

密钥只放在 `backend/.env` (已 gitignore) 或环境变量里，不写日志、不返回客户端。已知的安全限制见 [docs/STATUS.md](docs/STATUS.md#2-已知限制-known-limits)。

## 许可证 (License)

本项目以 [MIT License](LICENSE) 开源，Copyright (c) 2026 Luis Porsche。

## 2026-10-12 当前开发主线

全部工作区整合与最新模拟器/备机版本见 [Main 集成交付](docs/testing/2026-10-12-main-integration.md)。后端当前 schema v23；iOS 增加账号/服务器隔离的 SQLite 持久化，构建号 2026101201。定时任务 API 与独立后台源码均纳入主线，后台服务安装与真实模型验收单独跟踪。功能状态以 [STATUS](docs/STATUS.md) 为准。
