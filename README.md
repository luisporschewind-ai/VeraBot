# VeraBot — 私人 AI 助理团队 (Personal AI Agent Team)

> **v0.1.0 · 原型验证完成 (Prototype validated, feasible)** — 2026-09-30
> 91 条用例：通过 90 / 失败 0 / 跳过 1。之后的未发布改动 (设置页重排、头像 / 昵称、Liquid Glass 视觉、富文本等) 与当前进度见 [docs/STATUS.md](docs/STATUS.md)。

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
| [docs/design/MCP_CAPABILITY.md](docs/design/MCP_CAPABILITY.md)、[GMAIL_CAPABILITY.md](docs/design/GMAIL_CAPABILITY.md) | 设计稿 (未实现，待 Boss 评审)：MCP 能力与 Gmail 接入 |
| [docs/testing/TEST_CASES_v0.1.md](docs/testing/TEST_CASES_v0.1.md) | 测试用例与结果 |

## 安全 (Security)

密钥只放在 `backend/.env` (已 gitignore) 或环境变量里，不写日志、不返回客户端。已知的安全限制见 [docs/STATUS.md](docs/STATUS.md#2-已知限制-known-limits)。

## 许可证 (License)

本项目以 [MIT License](LICENSE) 开源，Copyright (c) 2026 Luis Porsche。
