# Chat Continuity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 普通回复在离开页面、后台和关闭 App 后持续执行，列表显示 Bot 工作状态，对话恢复并标记真实未读。

**Architecture:** 独立私聊 Worker 执行持久回复任务，API 提交和观察；保留原私聊运行语义。统一会话摘要与逐消息阅读版本，iOS 在账号级同步列表状态，聊天页恢复同一个任务与气泡。群与 owned task 保留执行器，通过发布适配接入。

**Tech Stack:** Python/FastAPI/SQLite，Swift 6/SwiftUI，现有 VeraBotKit，不增加基础设施依赖。

**Spec:** ../specs/2026-10-14-chat-continuity-design.md

## Global Constraints

- 全部实现位于隔离 worktree，基线 5a91461；不合并、不推送、不迁移原数据库、不替换用户验收 App。
- 普通发送无需主 Bot 或主动任务开关；保留记忆、附件、工具、委派及批准边界。
- 单会话最多一个运行中普通回复；等待项释放槽，独立输入排队；服务器和账号并发有有限上限。
- 请求 ID 与控制 ID 稳定，同 ID 不同载荷冲突；任务版本、会话代次和租约阻断迟到结果。
- 账号和服务器隔离。新客户端提交失败不降级旧 /chat 重发。
- 同一回复固定消息身份；逐消息及 publication_revision 已读，不使用最高消息 ID 消除阅读空洞。
- 正文／卡片可见至少 0.5 秒且聊天页前台可见后上报；本次标签保留至离开。
- 后端部分文本最长 1 秒或累计 256 字符批量保存；可读发布不按 delta 累加。
- 旧历史升级不全部标未读；收件箱未读独立。群状态不混进成员私聊。
- 朗读和麦克风生命周期不随后台执行改变；APNs 单独交付。
- 每任务先看到行为测试失败再实现，专项通过后记录独立测试证据；测试仅隔离临时数据、假模型，无真实凭据和调用。

## Review Focus

- 接收成功回执丢失：重进或同 ID 重试不能重建任务、附件或再次调用工具（Task 1/2）。
- 部分回复已读后离开才完成：完成版本仍未读；先读后面的消息不误读前面（Task 1/2）。
- 等待批准时用户发新消息：新的独立工作能运行，回答精确关联原等待版本（Task 1/2）。
- 清空／停止／账号切换后的迟到结果：既不恢复删除正文，也不串账号（Task 1/2/3）。
- 后端重启时外部调用结果未知：不盲目重复；已完成检查点保留（Task 1/3）。

## Task 1: 后端持久回复与会话阅读协议

**Files:** Create `backend/verabot/db/migrations/v030_chat_continuity.py`, `db/chat_reply_store.py`, `db/conversation_activity_store.py`, `services/chat_tasks/{service,worker,__main__,README}.py`, `api/routers/chat_tasks.py`, `api/routers/conversation_activity.py`, `api/chat_task_schemas.py`, `scripts/test/chat_continuity_test.py`及必要专项；Modify `db/migrations/__init__.py`, `agents/runtime.py`, `api/routers/chat.py`, `main.py`,消息／群／owned task投递及actions相关文件。

**Interfaces:**
- `POST /api/bots/{id}/chat/inputs`: client_request_id/message/attachment_ids/expected_generation；首次202，重放200。回执至少包含task、user_message_id、assistant_message_id、generation、cursor。
- `GET /api/bots/{id}/chat/inputs/{request_id}`: 同一接收回执或404。
- `GET /api/bots/{id}/chat/execution`: generation、cursor、tasks（含id/state/phase/version/input/output身份与部分正文）。
- `GET /api/bots/{id}/chat/events?after_id=`: 持久ID的SSE，断开仅停止观察。
- `POST /api/bots/{id}/chat/tasks/{tid}/stop`: expected_version/control_request_id。
- `POST /api/bots/{id}/chat/tasks/{tid}/inputs`: client_request_id/expected_version/wait_id/message；回答或安全继续。
- `GET /api/conversations/activity`: cursor、conversations，条目含kind/conversation_id/generation/state/phase/unread_count/pending_count/unread_messages；未读引用含message_id/publication_revision。
- `GET /api/conversations/events?after_id=`: 账号级会话摘要变化SSE，明确事件身份及代次。
- `POST /api/conversations/{kind}/{id}/read`: generation、messages:[{message_id,publication_revision}]。
- 新协议历史／执行快照需要提供stable id/content/traces/status/publication_revision；最终字段与示例写入 backend README/API contract供Task2使用。

- [ ] 写失败行为测试：接收/重放/冲突、隔离、部分正文与完成版本、稀疏阅读、排队/等待、停止清空迟到、恢复与审批关联。运行确认是缺功能导致失败。
- [ ] 迁移在临时库执行两遍；私聊回复身份和消息位置提交原子；旧历史read基线、会话代次、事件和工具检查点落库。
- [ ] 提取现有run_chat执行核心的可持久消费路径，保留旧协议；任务路径不创建重复输入/最终消息，不将排队后序消息放入本轮上下文。
- [ ] 实现独立Worker与`--once`，租约续期／取消／检查点／恢复，审批回接并保留所有原私聊工具策略；所有恢复避免未知写入重放。
- [ ] 实现API、摘要、逐消息read、群/owned发布及停止删除拦截，快照与cursor一致；旧客户端兼容且新版任务期间旧chat不能双执行。
- [ ] 运行 `backend/.venv/bin/python scripts/test/chat_continuity_test.py`（可使用main已安装runtime绝对路径），相关群、owned、消息和MCP回归；保存命令/数量/RED→GREEN证据和最终JSON例子至报告。
- [ ] 仅提交本任务backend文件；任务审查通过后进入Task2。

## Task 2: iOS数据、聊天恢复、列表与阅读

**Files:** Create `VeraBotCore/ChatReplyTask.swift`, `ConversationActivity.swift`, `VeraBotNetworking/APIClient+ChatTasks.swift`, `VeraBotData/ConversationActivityRepository.swift`, `Tests/VeraBotKitTests/ChatContinuityTests.swift`；Modify `VeraBotAPI.swift`, `ConversationRepository.swift`, persistence store/schema、`AppState.swift`, `VeraBotApp.swift`, `ChatViewModel.swift`, `ChatView.swift`, `BotListView.swift`, `GroupChatView.swift`及必要气泡/头像。

**Interfaces:** 消费Task1最终API示例。通过现有VeraBotAPI扩展默认实现保持其他Fake可编译；`ConversationActivityRepository`账号作用域管理activity、snapshot、事件游标及read outbox。`ChatReplyTask`与`ConversationActivity`字段严格映射后端；未完成正文由稳定assistant_message_id合并，不重建气泡。

- [ ] 写失败Swift测试：固定pending载荷/请求ID、重进恢复、完成revision未读、稀疏read、本次标签集合、账号回调失效及未读上限；运行确认失败。
- [ ] 实现Core/Networking与本地pending/快照/read outbox存储，服务端/账号隔离；前台账号一条连接，详情一条观察，后台只断观察。
- [ ] ChatViewModel从直连生成改为提交/查回执/快照/观察；排队输入、显式停止和等待回答可操作，页面离开不stop。
- [ ] 列表接入Bot及群工作状态、未读数和照片提示，动作复用且遵守reduce motion，身份徽章不冲突。
- [ ] 对话新标签、首条未读定位、通知目标优先、滚旧历史不抢滚动；实际可见0.5秒后逐消息read，本次标签不即时移除。群消息同样接入。
- [ ] 运行 `swift test --package-path frontend/ios/Packages/VeraBotKit --scratch-path /tmp/verabot-chat-continuity-spm`；构建独立DerivedData的iOS Simulator Debug但不安装验收App。
- [ ] 报告测试证据和用户未验收边界，仅提交本任务frontend文件；审查通过进入Task3。

## Task 3: 全链路故障验证、部署说明与交付

**Files:** Create `backend/scripts/test/chat_continuity_http_test.py`, `docs/testing/2026-10-14-chat-continuity.md`；Modify相关部署说明、STATUS/CHANGELOG/FEATURES/README，范围仅本功能状态。

- [ ] 为真实localhost socket断开、独立Worker完成、同ID回执恢复、重启/停止迟到及未知工具结果写缺失的失败回归，再补必要缺口。
- [ ] 临时库/假模型完成完整API→Worker→消息发布→read链路。运行专项、受影响后端回归和Swift完整测试；确认最新模拟器构建成功。
- [ ] 记录API与独立Worker启动/监督/数据目录边界；不安装系统服务、不访问真实模型、不接APNs。
- [ ] 同步功能与交付文档，区分源码完成、假模型测试、构建和用户/部署验收；整理待用户手动验收场景。
- [ ] 独立最终审查，修复阻塞项并复核对应测试。留下可审查分支和worktree，不自行合入main或推送。

## 执行方式与记录

用户已直接要求开始实施；采用本会话subagent-driven-development逐任务实施与审查，不再重复询问同一授权。仅一名实现代理同时修改文件；审查代理只读。每任务在计划专属ledger记录base/head、报告、验证与判定，跨上下文继续依据ledger而非重新实现。
