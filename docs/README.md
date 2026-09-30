# 文档索引 (Docs index)

所有文档使用中文，技术术语附英文。代码与文档在同一个 commit 更新 (见 [CONTRIBUTING.md](../CONTRIBUTING.md))。

| 目录 | 文档 | 内容 |
|---|---|---|
| — | [STATUS.md](STATUS.md) | **项目状态**：v0.1.0 原型验证完成、功能状态、已知限制、未测项、下一步 |
| — | [CHANGELOG.md](CHANGELOG.md) | 更新日志 (Keep a Changelog + SemVer) |
| product/ | [FEATURES.md](product/FEATURES.md) | 功能清单、API 摘要、SSE 事件格式 |
| design/ | [ARCHITECTURE.md](design/ARCHITECTURE.md) | 两个项目的架构、模块、依赖规则、依赖管理 (SPM / uv)、数据模型 |
| design/ | [MULTI_AGENT_DESIGN.md](design/MULTI_AGENT_DESIGN.md) | 多 Agent 权限模型、上下文隔离、护栏、审计、迁移、设置页 / TTS 扩展 |
| testing/ | [TEST_CASES_v0.1.md](testing/TEST_CASES_v0.1.md) | 全部测试用例与结果 (迭代 1、迭代 2、重构回归)、缺陷列表 |
| ops/ | [RUN_LOCAL.md](ops/RUN_LOCAL.md) | 本地运行后端 / iOS / 测试 |
| ops/ | [DELIVERY.md](ops/DELIVERY.md) | 打包与交付、Docker、交付检查清单 |

项目 README：[根目录](../README.md) · [backend](../backend/README.md) · [frontend](../frontend/README.md)
截图：[assets/screenshots/](../assets/screenshots/) (`web/` Web SPA，`ios/test/` 迭代 1 T*，`ios/regress/` 迭代 2 R*)
