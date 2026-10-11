# Bot 群聊第一版实施计划草案

> **For agentic workers:** 用户在规划后回复「OK，继续」推进 G0，随后回复「OK，继续下一阶段」授权 G1。使用 `superpowers:executing-plans` 按阶段推进；不派发子代理。当前完成 G0/G1/G2；G3 自动验证和用户授权代验收已执行，Task 4/5 主要交互及后台/重启在模拟器通过；保存 C 仍由 B 回应的反馈本轮未复现、原因未确认，其余页面与真实模型验收待完成。步骤用复选框记录，只有实际完成才能勾选。

**Goal:** 在 iOS 交付同一用户与 2–4 个现有 Bot 的持久文字群聊，支持点名、顺序讨论、停止与失败重试。

**Architecture:** 独立群表与群 API，服务端按成员顺序执行；复用现有模型客户端、账号鉴权和头像/Markdown 组件。群历史不写入私聊，不触发长期记忆，不增加工具执行路径。

**Tech Stack:** FastAPI、SQLite、Python asyncio、httpx、Swift 6、SwiftUI、VeraBotKit；不引入第三方依赖。

**Spec:** [群聊设计草案](../specs/2026-10-11-bot-group-chat-design.md)。两份文件均为可评审提案，产品决定确认后同步修订再执行。

**已确认产品方向：** 伙伴讨论，多个 Bot 平等参与，支持点名或轮流回应。其余首版范围待评审。

## Global Constraints

- 同一账号；创建 2–4 个不同 Bot；每账号最多 10 个群；群名 1–64 字符；消息 1–2000 字符。
- `single` 调用一个 Bot，`round` 所有可用成员按创建顺序各一次；同群最多一个活动轮次。
- 最近 24 条群历史，最多 12000 字符；输出 768 tokens；单成员 60 秒、单轮 240 秒；空回复最多重试一次。
- 首版文字聊天，不接群附件/工具/长期记忆/语音/APNs/Web/跨账号成员。
- 首版单进程后端，请求断开/离开页面/后台停止，启动恢复只标为中断，不自动再调用模型。
- 工作树基线 schema v19，G1 已加入 v20 迁移，设备交付时已备份并升级现有后端库；执行前检查实际版本和 Git 工作区，保留用户全部无关改动。
- 规划不自动提交；实施后的 commit/merge/push 范围遵循用户后续指令。自动化成功不能代替用户 UI 与真实模型验收。

## Review Focus

- 401 刷新、双击发送和 SSE 断线不得重复调用或把旧账号结果追加到新账号。
- 删除成员 Bot 或停止任务与生成同时发生时，已有消息、历史身份与用量保持正确。
- 下一位 Bot 必须读到前一位实际完成的回复，不能只共享原始用户问题。
- 清空/删除活动群、后端崩溃、用户退出页面应形成可恢复终态，不遗留忙碌锁。
- 他人群/成员/消息/轮次 ID 与超限输入均拒绝，用户文字不能伪装成员身份或触发未开放操作。

---

## 接口约定

后端文件内使用 TypedDict/dataclass 定义以下输入输出，公开序列化按 Spec §6；成员采用稳定 member_id，Bot 删除不删除 member 行。

- `Group`、`GroupMember`、`GroupMessage`、`GroupTurn`：Spec §6.1 对应公开类型；公开消息不带 user_id、内部日志或数据库路径。
- `GroupChatInput`：client_request_id、message、mode、target_bot_id。
- `GroupEvent`：event: str、data: dict；严格对应 Spec §6.3。
- `group_store.claim_turn(user_id: int, group_id: int, request: GroupChatInput, *, retry_of_message_id: int | None = None) -> GroupTurn`。
- `group_store.save_reply(user_id: int, message_id: int, content: str, status: str, usage: dict | None, *, finalize: bool) -> GroupMessage`。
- `groups.require_group(user_id: int, group_id: int) -> Group`。
- `groups.speakers(user_id: int, group: Group, request: GroupChatInput) -> list[GroupMember]`。
- `groups.request_stop(user_id: int, group_id: int, turn_id: int) -> GroupTurn`。
- `group_context.build(user_id: int, group: Group, member: GroupMember, turn: GroupTurn) -> list[dict]`。
- `group_runtime.run(user_id: int, group: Group, turn: GroupTurn) -> AsyncIterator[GroupEvent]`。
- `llm.stream_chat(messages: list, tools: list | None, *, tool_choice=None, max_tokens: int | None = None)`：只加可选参数，不改旧调用签名兼容性。
- Swift 类型：`ChatGroup`、`ChatGroupMember`、`GroupMessage`、`GroupTurn`、`GroupCreateRequest`、`GroupUpdateRequest`、`GroupChatRequest`、`GroupListResponse`、`GroupMessagesResponse`、`GroupChatState`、`GroupChatEvent`，均定义在 Core `GroupChat.swift`；后端 `Group` 对应 Swift `ChatGroup`，`GroupMember` 对应 `ChatGroupMember`。
- Swift `GroupChatAPI: Sendable`，普通方法均 `async throws`：`groups() -> GroupListResponse`、`createGroup(_ request: GroupCreateRequest) -> ChatGroup`、`group(id: Int) -> ChatGroup`、`updateGroup(id: Int, request: GroupUpdateRequest) -> ChatGroup`、`deleteGroup(id: Int) -> OKResponse`、`groupMessages(groupID: Int, beforeID: Int?) -> GroupMessagesResponse`、`clearGroupMessages(groupID: Int) -> OKResponse`、`groupTurn(groupID: Int, turnID: Int) -> GroupTurn`、`stopGroupTurn(groupID: Int, turnID: Int) -> GroupTurn`；`groupChatStream(groupID: Int, request: GroupChatRequest)`、`retryGroupMessage(groupID: Int, messageID: Int, requestID: UUID)` 同步返回 `AsyncThrowingStream<GroupChatEvent, Error>`。

## Task 1 / G0：可操作界面预览

**Files:**
- Create: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/GroupChat.swift`
- Create: `frontend/ios/VeraBot/Features/GroupChat/GroupListView.swift`
- Create: `frontend/ios/VeraBot/Features/GroupChat/CreateGroupSheet.swift`
- Create: `frontend/ios/VeraBot/Features/GroupChat/GroupChatView.swift`
- Create: `frontend/ios/VeraBot/Features/GroupChat/GroupChatPreviewData.swift`
- Modify: `frontend/ios/VeraBot/Features/BotList/BotListView.swift`

**Interfaces:** Core 类型来自 Spec §6；预览输入来自 GroupChatPreviewData，仅 Debug 预览使用，页面明确标识模拟数据；正式接入前不展示假回复为真实聊天。

- [x] 建立 Core 模型和预览数据，展示创建、空列表、普通回答、讨论中、部分失败及停止状态。
- [x] 复用已有 Bot 头像/Markdown/样式；助理页增加群入口；创建 Bot 按钮数量限制不阻止群创建。
- [x] 展示结构化点名标签、默认回应者、大家讨论与停止；本地创建校验不清空草稿，服务端失败保留草稿由 G1/G2 接入验证。
- [ ] 编译模拟器，用户检查入口与布局；记录为预览，用户修订后同步 Spec。

交付：可看可点的 UI 预览。此阶段不需要模型 Key、不写正式群数据；用户确认后才推进 G1/G2。

## Task 2 / G1：群存储、迁移、所有权和管理 API

**Files:**
- Create: `backend/verabot/db/migrations/v020_group_chat.py`
- Create: `backend/verabot/db/group_store.py`
- Create: `backend/verabot/db/group_types.py`
- Create: `backend/verabot/services/groups.py`
- Create: `backend/verabot/api/group_schemas.py`
- Create: `backend/verabot/api/routers/groups.py`
- Create: `backend/scripts/test/group_store_test.py`
- Modify: `backend/verabot/db/migrations/__init__.py`
- Modify: `backend/verabot/main.py`

**Interfaces:** 产出 Group/GroupMember/GroupMessage/GroupTurn、claim_turn/save_reply/require_group/speakers/request_stop；管理 REST 按 Spec §6.2。消息创建/用量插入的 SQL 都留在 db 层。

- [x] 先写临时 SQLite 测试 GC-01/04/05/09：v19 迁移两次不改旧记录、跨账号 404、2/4 成员成功与 1/5/重复/他人拒绝、第 11 群拒绝。
- [x] 验证新增文件缺失或接口未实现时测试失败；禁止把初始化/依赖错误当作预期业务失败。
- [x] 实现四张表、级联关系、member 快照、UUID 唯一索引、running 部分唯一索引及短 `BEGIN IMMEDIATE` 事务。
- [x] 测试两个独立连接同时领取轮次：恰好一方成功；相同 UUID 指向原轮次，不新增消息；不同内容同 UUID 返回冲突。
- [x] 实现 CRUD/历史分页/清空/重命名/default 更新，活动群修改限制及 Bot 删除后的只读/默认回退行为。
- [x] 验证最多 100 条分页、无遗漏或重复；失败事务回滚全部成员，跨账号停止/轮次读取也不能取到对象；重试路由权限验收留在 G2。
- [x] Run（backend）：`scripts/test/group_store_test.py`：13/13 PASS、退出码 0（使用主目录现有 .venv Python，临时数据库；PATH 无 uv）。

交付：独立数据与管理 API；没有触碰私聊消息、附件或记忆。

## Task 3 / G1：群消息协议与 iOS 网络契约

**Files:**
- Create: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotNetworking/GroupChatAPI.swift`
- Create: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotNetworking/GroupChatEventParser.swift`
- Create: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/GroupChatReducer.swift`
- Create: `frontend/ios/Packages/VeraBotKit/Tests/VeraBotKitTests/GroupChatContractTests.swift`
- Create: `frontend/ios/Packages/VeraBotKit/Tests/VeraBotKitTests/GroupChatReducerTests.swift`
- Create: `frontend/ios/Packages/VeraBotKit/Tests/VeraBotKitTests/GroupChatNetworkTests.swift`
- Modify: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotNetworking/APIClient.swift`
- Modify: Task 1 的 `GroupChat.swift`

**Interfaces:** APIClient 额外符合 GroupChatAPI，保持 VeraBotAPI 不变；`GroupChatEventParser.parse(event: String, data: Data) -> GroupChatEvent?`；`GroupChatReducer.apply(_ event: GroupChatEvent, to state: inout GroupChatState)`。

- [x] 先写 Spec §6.3 的全事件 JSON fixtures 解码测试，消息/成员/轮次标识缺失不得追加到错误气泡；未知事件忽略。
- [x] 先写 reducer 测试：A/B 两条消息分开、重复 start 不重复气泡、done 替换全量、旧 turn/终态后 delta 忽略、status 不进入正文。
- [x] 运行 `swift test --filter GroupChat`（VeraBotKit 目录），确认业务断言先失败。
- [x] 实现模型、独立群协议/parser/reducer；APIClient 内群请求复用现有鉴权/刷新/会话代次检查与私有 call，不复制第二套令牌管理。
- [x] 对 streaming 提交生成一次 UUID；401 同会话重发保持 UUID，409 request_exists 查询轮次，禁止自动生成新 UUID 再调用。
- [x] 添加 GC-08 网络 mock：刷新时注销/账号切换终止旧请求；断线恢复取服务器快照，不重放 delta。
- [x] Run：`swift test --filter GroupChat` 全部 PASS；全量 `swift test` 206/206 PASS。

交付：稳定的群请求/消息事件类型与 UI 状态处理；不改变私聊事件格式。

## Task 4 / G2：群上下文与真实顺序发言

**Files:**
- Create: `backend/verabot/agents/group_context.py`
- Create: `backend/verabot/agents/group_runtime.py`
- Create: `backend/scripts/test/group_runtime_test.py`
- Modify: `backend/verabot/services/llm.py`
- Modify: `backend/verabot/api/routers/groups.py`
- Modify: `backend/verabot/db/group_store.py`

**Interfaces:** 消费 Task 2 类型和 store API；产出 build/run 及 Spec §6.3 SSE，复用 llm.stream_chat，tools 固定为 None。

- [x] 写 mock LLM 测试 GC-02/03/04/10/11：single 仅 B；round A→B→C；捕获 B prompt 断言含 A 实际回答、无私聊秘密/其他成员 instructions/长期记忆。
- [x] 测试 24 条/12000 字符上下文边界、保留本轮用户问题、来源标签不能被用户提供的 Bot 名称覆盖。
- [x] 运行 `uv run python scripts/test/group_runtime_test.py` 确认业务断言失败后实现 group_context.build 和群 prompt，不复制私聊的工具/记忆承诺。
- [x] 实现串行生成、message_start 前落库、delta 定向、message_done 全量文本、逐成员 usage、turn_done 聚合；不把群讨论写入 delegations 或旧 messages。
- [x] 增加可选 max_tokens，只有群传 768；测试旧 llm 请求 body 不变，群 body 含上限。
- [x] 实现每次调用前预算检查、空回复一次重试和超时常量；用可控 mock clock/超时配置测试，不实际等 240 秒。
- [x] Run：`uv run python scripts/test/group_runtime_test.py` 与 `uv run python scripts/test/llm_body_test.py`；预期全部 PASS。

交付：可以通过群接口获得真实、分别归属成员的文字回复。

## Task 5 / G2：停止、中断恢复与单人重试

**Files:**
- Create: `backend/scripts/test/group_lifecycle_test.py`
- Modify: `backend/verabot/agents/group_runtime.py`
- Modify: `backend/verabot/services/groups.py`
- Modify: `backend/verabot/db/group_store.py`
- Modify: `backend/verabot/api/routers/groups.py`
- Modify: `backend/verabot/main.py`

**Interfaces:** store 新增 `recover_interrupted_turns() -> int`；runtime 在单进程持有以 `(user_id, group_id, turn_id)` 为键的取消入口；stop 必须先验证所有权并持久化 cancel_requested，不能仅删除进程内任务。

- [x] 写 GC-06/07/08/09/10：A 完成 B 部分生成后停止，C 从未调用；late delta 丢弃；重复停止和 finalize 不重复 usage。
- [x] 写断线/取消/异常/重启测试：已知 usage 一次入账、未知 usage 标识保留；running 变 interrupted；下一轮可领取；不启动隐式模型任务。
- [x] 写 GC-07 重试测试：仅重试原失败 Bot，新 UUID/new turn/new message 引用 retry_of；按原 context_end_message_id 重建历史，不带后来讨论，不重复旧成员。
- [x] 写 Bot 删除竞态测试：调用前再次校验 Bot 存在；已在生成中的发言停止并保留快照，后续成员继续；群管理活动冲突为 409。
- [x] 实现停止/重试/启动恢复；取消 finally 仅短 DB 事务，确保终态与部分文字在任务真正退出时保存。
- [x] Run（backend）：`uv run python scripts/test/group_lifecycle_test.py`；预期全部 PASS。

交付：可停止、可解释失败、可恢复历史，无自动续跑。

## Task 6 / G2：iOS 正式接入与用户状态

**Files:**
- Create: `frontend/ios/VeraBot/Features/GroupChat/GroupChatViewModel.swift`
- Create: `frontend/ios/VeraBot/Features/GroupChat/GroupInfoView.swift`
- Modify: Task 1 的 GroupListView/CreateGroupSheet/GroupChatView
- Modify: `frontend/ios/VeraBot/Features/BotList/BotListView.swift`
- Test: `frontend/ios/Packages/VeraBotKit/Tests/VeraBotKitTests/GroupChatReducerTests.swift`

**Interfaces:** `GroupChatViewModel(group: ChatGroup, api: any GroupChatAPI)`；`load()`、`send(text:mode:targetBotID:)`、`stop()`、`retry(messageID:)`、`loadOlder()`；内部 reducer 统一维护流状态；环境账号会话变化使旧任务失效。

- [x] 接群列表/创建/管理/分页；失败保留草稿/已有历史，加载中不显示“没有群”。
- [x] 将预览消息替换为真正服务端数据，按服务器 message ID 更新，不用固定数组下标猜发言者。
- [x] 点名、本地默认偏好与讨论队列对应请求字段；输入时显示所有成员顺序和正在发言者，停止后恢复输入。
- [x] 失败回复展示重试；清空/删除 confirmation、409 先停提示和成功导航接真实 API。
- [x] 离开页/后台/注销/切换账号取消流并尝试 stop；网络失败不伪报已停止，重新进入查询；已保存正文可读。
- [x] 不显示群附件或工具入口；不新增自动 TTS；使用现有 Bot 警告/等待形象及 Debug 详情边界。
- [x] Run VeraBotKit `swift test`；使用独立 DerivedData 做 Simulator build；用户交互验收另列，不自动代做。

交付：可以从 App 完整使用文字群聊，已有私聊入口与行为正常。

## Task 7 / G3：回归、文档和用户验收交付

**Files:**
- Create: `docs/testing/2026-10-11-bot-group-chat.md`（实际执行日期不同则用执行日）
- Modify: `docs/README.md`、`docs/STATUS.md`、`docs/CHANGELOG.md`
- Modify: `docs/product/FEATURES.md`、`docs/design/ARCHITECTURE.md`、`docs/design/MULTI_AGENT_DESIGN.md`
- Modify: `docs/testing/TEST_CASES_v0.1.md`、`backend/README.md`（新 API/单进程边界）

- [x] 后端运行 group_store/runtime/lifecycle 三组 mock 测试。
- [x] 回归 `multi_agent_test.py`、`status_event_test.py`、`auth_stability_test.py`、`llm_body_test.py`；检查不消耗真实模型额度、不碰正式数据库。
- [x] VeraBotKit `swift test` 和 iOS Simulator build；构建成功与交互通过分别记录。
- [x] 更新 API、事件、schema、首版限制、GC-01～12 结果；无证据项目标待测，不能复制旧群聊不存在的通过记录。
- [x] 向用户提供模拟器运行环境与用例：三 Bot 创建 → A 回答 → 点名 B → 全体讨论 → 停止 → 重进 → 重试 → 清空/删除。
- [ ] 用户确认真实模型请求与讨论体验后才标为验收通过；未得到授权不调用真实模型验收、不提交/合并/推送。

## 规划自检记录

- 覆盖：Spec §5 交互对应 Task 1/6；§6 存储/API/SSE 对应 Task 2/3；§7 上下文/预算/生命周期对应 Task 4/5；§9 验收对应 Task 7。
- Review Focus 五项均在 Task 2～6 分配了可观察的断言或人工用例。
- 没有工具/长期记忆/附件的隐含实施任务；未改私聊核心；没有把当前已有脏文件加入规划提交。
- 群聊氛围已确认伙伴讨论；用户回复「OK，继续」后 G0 代码已制作，构建与用户界面确认分别记录。G1/G2 已完成，G3 待用户验收，范围变化同步修订 Spec 与本文件。

## G1 执行记录

2026-10-11：Task 2/3 已完成，详见 [G1 验证记录](../../testing/2026-10-11-bot-group-chat-g1.md)。群管理 REST 已实现；chat/retry 仅预备客户端协议，后端模型与 UI 接线由 G2/G3 完成。409 request_exists 会查询原轮次并抛出带服务器快照的 GroupRequestExists，供 ViewModel 恢复，不生成新请求 ID。停止 API 此阶段只持久化取消标记，模型取消与启动恢复由 G2 完成。

## G2 执行记录

2026-10-11：用户授权继续 G2，完成 Task 4/5/6，含 iOS 正式接线；[验证记录](../../testing/2026-10-11-bot-group-chat-g2.md)。Task 5 Ruling：重试 turn_start 引用原问题消息，事件属于新 turn，避免重复用户消息；其他严格等同 turn_id 的客户端需同步。Task 6 Ruling：ViewModel 放在 VeraBotNetworking 供 App 使用/包测试，未来模块迁移需同步公开类型。工作树未提交，真实模型未调用，G3 验收未完成。

## G3 执行记录

2026-10-11：Task 7 自动回归、真实 HTTP 模拟提供者联调、文档与隔离模拟器准备已执行；[G3记录](../../testing/2026-10-11-bot-group-chat.md)。人工交互与真实模型质量未验收，故不标记整体验收通过。没有提交/合并/推送。

## 阶段编号说明（2026-10-11）

首版只有 G0～G3；Task 1～7 是实施任务，不是 G1～G7。Task 4/5/6 已在 G2 完成，Task 7 对应 G3。用户确认创建群、默认回应、全体讨论通过；点名与默认成员同步已修复并更新现有验收模拟器，待人工复验。没有已批准的 G4～G7 范围，后续工具/记忆/附件仍属待规划方向。
