# 记忆成长 M3 实施计划

> **执行要求：**使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，按任务逐项实施。每一步用复选框跟踪。

**目标：**完成隐式候选记忆、主动建议和快捷提问，候选记忆在用户确认前不生效。

**架构：**复用 v14 `memory_jobs` worker、`memories` 候选状态和现有记忆确认流程；v16 新增建议存储（主线 v15 已用于 Bot 外观）。FastAPI 提供候选提示、建议和快捷提问数据，iOS 负责确认交互和输入框展示。

**技术栈：**Python 3.12、FastAPI、SQLite、DeepSeek JSON Output、SwiftUI、VeraBotKit。

**规格：**[M3 / M4 设计规格](../specs/2026-10-07-memory-m3-m4-design.md) §M3

## 全局约束

- 只提取用户角色消息；工具、MCP、附件正文和委派输出不得进入抽取输入。
- 记忆候选须用户确认后才生效，14 天过期；禁止自动更新已有记忆。
- 预算达到每日额度 90% 时跳过模型抽取，所有模型用量记入 `kind=memory`。
- 所有 SQL 与 API 都校验 `user_id`；日志不得记录用户正文或模型输出正文。
- 不改 Web，不实现推送、不自动改权限、不实现 M5 向量检索。
- 数据库 schema 从 v15 升至 v16；迁移幂等，文档与行为在同一提交中更新。

## 文件职责

- `backend/verabot/db/migrations/v015_memory_suggestions.py`：建议表与索引。
- `backend/verabot/db/suggestion_store.py`：建议 CRUD、幂等状态转换和查询。
- `backend/verabot/services/memory/extract.py`：抽取输入、JSON 校验、候选去重和保存；`db/message_store.py` 提供证据消息时间与归属校验。
- `backend/verabot/services/memory/suggestions.py`：规律 / 委派建议创建、冷却、接受和拒绝。
- `backend/verabot/services/memory/quick_prompts.py`：基于用户自身消息生成安全快捷提问。
- `backend/verabot/services/memory/jobs.py`、`memory_job_store.py`、`agents/runtime.py`：任务分发、触发和消息轮次收尾。
- `backend/verabot/api/routers/{memories,bots,suggestions}.py`、`main.py`：候选提示、快捷提问和建议 API；`services/memory/service.py` 只为合规的待确认候选公开安全 evidence 元数据。
- `backend/scripts/test/memory_m3_test.py`：M3 后端契约与业务回归。
- `frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/Memory.swift`、`SettingsKeys.swift`、`VeraBotNetworking/{VeraBotAPI,APIClient}.swift`：模型、设置键和 API 客户端。
- `frontend/ios/VeraBot/Features/{Memory/MemoryListView,Chat/ChatView,Chat/ChatViewModel,Settings/GeneralSettingsSection}.swift`：候选、建议卡片和快捷提问 UI。
- `frontend/ios/Packages/VeraBotKit/Tests/VeraBotKitTests/MemoryTests.swift`：模型与规则单测。
- `docs/design/MEMORY_GROWTH.md`、`docs/testing/TEST_CASES_v0.1.md`、`docs/CHANGELOG.md`、`docs/STATUS.md`：实现说明、验收用例与状态。

## 任务

### 任务 1：v16 建议存储与幂等 API 基础

**文件：**新增 `backend/verabot/db/migrations/v016_memory_suggestions.py`、`backend/verabot/db/suggestion_store.py`；修改迁移注册文件、`backend/verabot/db/schema.py`；测试 `backend/scripts/test/memory_m3_test.py`。

**接口：**提供 `create_or_get_active(user_id, bot_id, kind, dedupe_key, payload, expires_at)`、`list_pending(user_id, bot_id)`、`decide(user_id, suggestion_id, decision)`。接受 / 拒绝重复请求返回当前状态，不重复执行副作用；他人 ID 返回 not found。

- [ ] 编写迁移、唯一约束、租户隔离、过期和状态转换用例：`test_suggestion_schema_v16_is_idempotent`、`test_suggestion_state_changes_are_idempotent`、`test_suggestion_queries_are_user_scoped`、`test_suggestion_dismissal_cooldown`。
- [ ] 运行 `cd backend && uv run python scripts/test/memory_m3_test.py`，确认新增用例因缺少实现而失败。
- [ ] 实现 v16 迁移与存储层；payload 只含有界字段，去重键按用户 / Bot / 类别隔离。
- [ ] 重跑同一用例，确认迁移幂等、跨用户不可见、决定操作可安全重放。
- [ ] 提交 `backend` 和测试变更。

### 任务 2：隐式抽取、任务触发和候选审核

**文件：**新增 `backend/verabot/services/memory/extract.py`；修改 `services/memory/jobs.py`、`db/memory_job_store.py`、`agents/runtime.py`、必要时 `api/routers/chat.py`；扩展 `memory_m3_test.py`。

**接口：**`async extract.run(job: dict) -> tuple[str, str | None]`；`extract.enqueue_if_due(user_id: int, bot_id: int, after_message_id: int) -> bool`。抽取输出只保存为 `candidate`，更新使用既有 `action=update` / `target_id`。

- [ ] 先为六条用户消息触发、空闲 10 分钟后下次请求触发、输入仅含允许角色、JSON 和证据校验、敏感 / 注入 / 重复丢弃、预算跳过及候选不注入编写用例。
- [ ] 运行该测试文件，确认触发和抽取用例失败在预期行为上。
- [ ] 实现任务分发、每新增 6 条用户消息及空闲 10 分钟后下一次请求的触发、最近 12 条用户消息 + 每条最多 200 字助手上下文、已知且按权限可见的记忆输入。调用模型时固定 `temperature=0`、`max_tokens=600`，严格校验类型 / scope / 1–200 字正文 / 0.6–1.0 置信度 / 本次输入证据 ID；每次最多 3 条，bigram Jaccard ≥0.8 的近似重复、敏感和注入内容均丢弃。更新 `meta` 保存证据 ID / 简短理由，`source_message_id` 保存最新有效证据。
- [ ] 只在用户记忆开关开启且 Bot `memory_access != none` 时入队；失败使用短错误代码，沿用现有重试策略。
- [ ] 重跑抽取用例并提交本任务变更。

### 任务 3：规律 / 委派建议与快捷提问 API

**文件：**新增 `backend/verabot/services/memory/suggestions.py`、`quick_prompts.py`、`api/routers/suggestions.py`；修改 `api/routers/bots.py`、`main.py`；扩展 `memory_m3_test.py`。

**接口：**`GET /api/bots/{id}/suggestions`；`POST /api/suggestions/{id}/accept`；`POST /api/suggestions/{id}/dismiss`；`GET /api/bots/{id}/quick-prompts`。

- [ ] 编写同一提醒跨三周匹配、routine 记忆建议、委派请求阈值、权限不自动变化、接受副作用幂等、拒绝冷却、快捷提问来源 / 频次 / 敏感排除及跨用户隔离用例。
- [ ] 运行后端 M3 测试，确认建议和快捷提问用例按预期失败。
- [ ] 实现建议查询与决定 API。重复提醒接受以稳定幂等键在同一事务中完成提醒创建和建议状态变更；先检查提醒服务能否接收外层连接，必要时提取事务内创建方法，确保并发重放不会产生重复提醒。委派建议接受只返回来源 Bot 设置跳转信息。
- [ ] 实现快捷提问规范化：最近 30 天，至少 3 次的用户原句最多 4 条，工具模板补足至 6 条；过滤超过 80 字、敏感内容和重复项。仅在对应工具已启用时提供天气 / 提醒模板。
- [ ] 重跑 M3 测试并提交本任务变更。

### 任务 4：iOS 候选提示与主动建议交互

**文件：**修改 Kit 的 `Memory.swift`、`VeraBotAPI.swift`、`APIClient.swift`；App 的 `MemoryListView.swift`、`ChatViewModel.swift`、`MessageRow.swift`；扩展 `MemoryTests.swift`。

- [ ] 添加建议 / 候选提示响应模型与 API 方法；为解码兼容添加模型测试。
- [ ] 在 `service.public()` 中，仅当状态为 `candidate` 且来源为隐式抽取时，校验 `meta` 后暴露有界 reason 和 evidence 的消息 ID、日期、角色；不暴露消息正文。记忆页候选组展示证据日期 / 来源；确认、拒绝继续使用现有按钮和 API。过期清理同步清除 evidence 元数据。
- [ ] 在对话中最多每天显示一次非阻断候选提示，点按进入当前 Bot 的记忆页；建议卡片提供接受 / 拒绝，并显示安全失败状态。
- [ ] 用 `vb_memory_candidates_nudge.<userID>` 保存本地上次提示日期，确保同一用户跨 Bot 每天最多提示一次；候选数为零时不显示。
- [ ] 编写并运行 Kit 模型测试，验证旧响应缺字段时兼容及新模型字段映射。
- [ ] 更新 M3 验收文档与状态，并提交本任务变更。

### 任务 5：iOS 快捷提问与 M3 收尾

**文件：**修改 `SettingsKeys.swift`、`GeneralSettingsSection.swift`、`ChatView.swift`、`ChatViewModel.swift`、`VeraBotAPI.swift`、`APIClient.swift`、`docs/testing/TEST_CASES_v0.1.md`、`docs/design/MEMORY_GROWTH.md`、`docs/CHANGELOG.md`、`docs/STATUS.md`。

- [ ] 新增默认开启的 `vb_quick_prompts_enabled` 设置项，并编写默认值 / 持久化测试。
- [ ] 对话打开时获取快捷提问，用户轮次完成后刷新；只在输入框为空且未聚焦时显示系统玻璃胶囊。点按只填值，不调用发送方法；失败隐藏该行。
- [ ] 编写 Kit 对响应上限、空结果和缺字段兼容测试；运行 Kit 与 M3 后端回归。
- [ ] 更新 §20 M3 实现说明、MEM-50~60 验收记录、CHANGELOG / STATUS；未实际运行的人工验收明确标为待验收。
- [ ] 执行 iOS 构建和需覆盖的手工验收；提交完整 M3 变更。

## 重点复核输入

- 伪造、过期或属于另一用户的 evidence message ID 不得成为候选；由任务 2 的证据校验用例覆盖。
- 抽取文本中嵌入“忽略规则”或工具结果指令不得影响系统行为；由任务 2 的注入过滤用例覆盖。
- 两个并发接受请求不得创建两条重复提醒；由任务 3 的幂等用例覆盖。
- 跨午夜 / 夏令时附近的重复提醒建议需保留用户所见的本地星期和时间；由任务 3 的时区用例覆盖。
- 用户关闭记忆后不得继续抽取；用户关闭快捷提问后，iOS 不请求也不展示该行。由任务 2 / 5 的开关用例覆盖。

## 验收命令

- 后端：`cd backend && uv run python scripts/test/memory_m3_test.py`，随后运行记忆、提醒、委派和完整后端确定性回归。
- Kit：`cd frontend/ios/Packages/VeraBotKit && swift test`。
- iOS：使用 iPhone 17 Simulator scheme `VeraBot` 执行 `xcodebuild`；不使用 UI 自动化。系统界面由负责人手工验收。
