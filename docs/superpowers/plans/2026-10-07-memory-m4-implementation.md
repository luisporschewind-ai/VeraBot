# 记忆成长 M4 实施计划

> **执行要求：**使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，按任务逐项实施。每一步用复选框跟踪。

**目标：**交付可信的记忆成长统计、月度回顾、记忆搜索 / 筛选 / 引用和用户主动导出。

**架构：**schema v17 增加按用户 / 月份唯一的回顾缓存，复用 v14 `memory_jobs` worker 生成回顾；FastAPI 按用户与 Bot 权限返回统计、回顾、导出和回答引用。iOS 在现有记忆页与 Bot 详情中提供访问入口。

**技术栈：**Python 3.12、FastAPI、SQLite、DeepSeek JSON Output、SwiftUI、VeraBotKit。

**规格：**[M3 / M4 设计规格](../specs/2026-10-07-memory-m3-m4-design.md) §M4；依赖 [M3 实施计划](2026-10-07-memory-m3-implementation.md) 的候选与建议 API。

## 全局约束

- 月度回顾不得读取原始对话、历史摘要、工具参数 / 结果或候选正文；只提供允许的统计聚合与本月新确认的非敏感记忆。
- 所有统计和接口都限定当前用户；记忆引用另按回答所属 Bot 的 `memory_access` 再过滤。
- 当日记忆用量达到额度 90% 时跳过回顾模型调用，只返回安全聚合结果；用量记入 `kind=memory`。
- 导出由用户主动触发；敏感正文只经现有 Fernet 服务解密，不导出对话、审计或其他用户数据。
- 不加等级、积分、徽章、推送或 Web UI；不实现 M5 向量检索。
- 数据库 schema 从 v16 升至 v17；迁移幂等，行为与文档在同一提交中更新。

## 文件职责

- `backend/verabot/db/migrations/v016_memory_reviews.py`、`db/review_store.py`：月度回顾表和唯一 / 查询约束；把 `memory_jobs.bot_id` 调整为可空，仅用户级 `review` job 使用 `NULL`，保持其他 job 必须关联 Bot。
- `backend/verabot/services/memory/growth.py`：成长统计、回顾输入聚合、回顾生成 / 降级和导出数据。
- `backend/verabot/services/memory/jobs.py`：执行 `review` job 并按短错误代码重试。
- `backend/verabot/db/{memory_store,message_store,delegation_store,usage_store}.py`：为统计和引用查询提供按用户过滤的读取方法。
- `backend/verabot/api/routers/{memories,bots}.py`：growth、monthly review、export、memory reference API。
- `backend/scripts/test/memory_m4_test.py`：M4 后端 API / 聚合 / 隔离回归。
- `frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/{Memory,Models}.swift`、`VeraBotNetworking/{VeraBotAPI,APIClient}.swift`：M4 响应模型与 API。
- `frontend/ios/VeraBot/Features/Memory/{MemoryListView,MemoryEditView,MemoryMonthlyReviewView,MemoryReferencesView}.swift`、`Features/BotInfo/BotEditView.swift`、`Features/Chat/{ChatViewModel,MessageRow}.swift`：统计、回顾、搜索、引用和导出交互。
- `frontend/ios/Packages/VeraBotKit/Tests/VeraBotKitTests/MemoryTests.swift`：模型与本地筛选规则测试。
- `docs/design/MEMORY_GROWTH.md`、`docs/testing/TEST_CASES_v0.1.md`、`docs/CHANGELOG.md`、`docs/STATUS.md`：实现说明、验收用例与状态。

## 任务

### 任务 1：v17 回顾缓存、成长统计与导出 API

**文件：**新增 `backend/verabot/db/migrations/v017_memory_reviews.py`、`backend/verabot/db/review_store.py`、`backend/verabot/services/memory/growth.py`；修改迁移注册、`db/schema.py`、`api/routers/bots.py`、`api/routers/memories.py`；测试 `backend/scripts/test/memory_m4_test.py`。

**接口：**`growth.for_bot(user_id: int, bot_id: int) -> dict`、`growth.request_monthly_review(user_id: int, month: str) -> dict`、`growth.export_memories(user_id: int) -> dict`；路由为 `GET /api/bots/{id}/growth`、`GET /api/review/monthly?month=YYYY-MM`、`GET /api/memories/export`。月度回顾 API 立即返回聚合数据和 `review_status`（`pending` / `ready` / `unavailable`）；worker 异步完成后由后续 GET 返回缓存内容。

- [ ] 编写迁移幂等、可空 Bot 的用户级 review job、月度唯一缓存、并发获取、统计隔离 / 计数、预算降级、无敏感 / 原始对话模型输入、模型失败重试和导出隔离 / 解密用例。
- [ ] 运行 `cd backend && uv run python scripts/test/memory_m4_test.py`，确认新增断言先失败在缺少目标行为上。
- [ ] 实现 v17 迁移和存储；重建 `memory_jobs` 时保留全部既有行与索引，仅允许 `kind=review` 的 job 使用 `bot_id=NULL`。月度回顾仅用聚合统计、启用能力统计、本月确认的非敏感记忆和候选数量生成，候选正文不进入模型。
- [ ] 实现成长计数：assistant 完成消息数 + 成功委派回答数；首次日期从该 Bot 最早消息计算；最近记忆只返回最多 3 条。
- [ ] 实现立即返回聚合字段和 `pending` 状态；worker 写入唯一月度缓存，预算跳过 / 模型失败返回安全聚合与 `unavailable`，允许后续请求重试。审核模型返回的记忆 ID 必须重新校验用户归属。
- [ ] 实现用户主动 JSON 导出；敏感正文调用现有解密服务，密钥不可用时导出安全占位文字。
- [ ] 重跑 M4 后端用例并提交本任务变更。

### 任务 2：单条回答所引用记忆 API

**文件：**修改 `backend/verabot/db/message_store.py`、`services/memory/growth.py`、`api/routers/memories.py`；扩展 `memory_m4_test.py`。

**接口：**新增 `GET /api/messages/{message_id}/memories`；服务方法 `growth.message_memories(user_id: int, message_id: int) -> list[dict]`。响应只包含当前回答的记忆 ID、正文、类型和必要展示元数据。

- [ ] 编写跨用户 message ID、Bot 无记忆权限、global / bot scope、记忆删除或不可见、空 `memory_ids` 用例。
- [ ] 运行后端 M4 测试，确认引用路由用例先失败。
- [ ] 实现消息所属用户 / Bot 校验；从 `messages.memory_ids` 解析 ID 后，按该 Bot 的 `memory_access` 过滤，逐条排除已删除或不可见记录。
- [ ] 重跑引用测试并提交本任务变更。

### 任务 3：Kit 模型、API 客户端和纯逻辑筛选

**文件：**修改 `Memory.swift`、`Models.swift`、`VeraBotAPI.swift`、`APIClient.swift`、`MemoryTests.swift`。

**接口：**新增 `BotGrowth`、`MonthlyMemoryReview`、`MemoryReferencesResponse` 和 `MemoryExportResponse` 解码模型；新增 `botGrowth(botID:)`、`monthlyMemoryReview(month:)`、`memoryReferences(messageID:)`、`memoryExport()`。

- [ ] 编写 JSON 解码测试，覆盖缺少可选字段、空回顾、未识别记忆类型和引用为空。
- [ ] 为本地搜索 / 类型筛选新增 `MemoryFilter.matches(_:query:type:)` 测试：大小写无关、空查询、type 匹配及候选分组。
- [ ] 运行 Kit 测试确认新增模型 / 过滤方法用例失败在缺失实现上。
- [ ] 实现 Codable 模型、客户端调用和无副作用过滤逻辑；保留现有后端旧字段兼容。
- [ ] 重跑 Kit 测试并提交本任务变更。

### 任务 4：成长、月度回顾、搜索 / 筛选与导出界面

**文件：**修改 `MemoryListView.swift`、`BotEditView.swift`；新增 `MemoryMonthlyReviewView.swift`；必要时新增共享的分享面板文档类型；扩展 Kit/UI 可测试逻辑。

- [ ] 在 Bot 详情记忆分组加载 growth，显示记忆分类、已协助次数、相识日期和最多 3 条最近记忆；加载失败不阻断 Bot 详情。
- [ ] 在全局记忆页和 Bot 记忆页增加 `.searchable`、类型筛选和使用次数 / 最近使用信息；候选维持单独分组。
- [ ] 在记忆详情编辑页显示 `use_count` 与 `last_used_at`；月度回顾中的新记忆链接到对应记忆详情，可逐条删除。
- [ ] 首次打开记忆页时请求当月回顾；有缓存则显示普通列表页，无缓存且生成中时显示加载态，失败时显示聚合结果与重试入口。
- [ ] 新增回顾列表页，展示协助次数、能力类别、新记忆、待确认候选数和最多一条建议；敏感信息不显示。
- [ ] 增加用户主动导出按钮，经系统分享面板导出服务返回的 JSON 文件；不在加载记忆页时自动触发导出。
- [ ] 运行 Kit 测试及后端 M4 回归，执行 iOS 构建；提交本任务变更。

### 任务 5：回答记忆引用入口与 M4 收尾

**文件：**修改 `ChatViewModel.swift`、`MessageRow.swift`、`APIClient.swift`、`VeraBotAPI.swift`；新增 `MemoryReferencesView.swift`；更新 `docs/design/MEMORY_GROWTH.md`、`docs/testing/TEST_CASES_v0.1.md`、`docs/CHANGELOG.md`、`docs/STATUS.md`。

- [ ] 对有服务器 message ID 的 Bot 回复增加上下文菜单项「这条回答参考了哪些记忆」。
- [ ] 打开后请求该 message 的引用记忆，并在普通列表页展示；空 / 删除 / 不再可见时显示安全空状态，不显示无权限记录。
- [ ] 编写 Kit 解码 / 过滤测试，运行 M4 后端和 Kit 回归及 iOS 构建。
- [ ] 更新 §20 M4 实现说明、MEM-61~64 验收记录、CHANGELOG / STATUS；未运行的真机与手工验收明确标为待验收。
- [ ] 提交完整 M4 变更。

## 重点复核输入

- 被删除的 Bot、其消息或记忆不得通过 growth、review、export、references 泄漏；由任务 1 / 2 的隔离用例覆盖。
- `memory_ids` 损坏、重复或引用其他用户记录时必须安全忽略；由任务 2 覆盖。
- 同一用户并发打开月度回顾时只能有一个缓存结果和一个有效 review job；由任务 1 覆盖。
- 模型返回格式错误、伪造记忆 ID 或敏感内容时只能返回聚合降级结果；由任务 1 覆盖。
- 导出时加密密钥不可用必须输出安全占位，不可返回密文、异常文本或其他用户内容；由任务 1 覆盖。

## 验收命令

- 后端：`cd backend && uv run python scripts/test/memory_m4_test.py`，随后运行 M3、记忆、委派和完整后端确定性回归。
- Kit：`cd frontend/ios/Packages/VeraBotKit && swift test`。
- iOS：使用 iPhone 17 Simulator scheme `VeraBot` 执行 `xcodebuild`；不使用 UI 自动化。系统界面由负责人手工验收。
