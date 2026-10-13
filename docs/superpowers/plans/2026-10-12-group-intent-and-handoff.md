# 群聊意图分配、动态澄清与任务交接实施计划

> **执行状态（2026-10-13）：** 用户已授权在本对话实施。初轮实现的“任务1–9全部完成”判断经复审撤回；16项缺陷及追加组合问题已按2026-10-13修复计划处理。当前进入用户手动验收，见[修复记录](../../testing/2026-10-13-group-intent-handoff-repair.md)。下方复选框保留初轮执行记录，不代表完整产品验收。没有提交、合并或推送。

**Goal:** 移除默认回应者，按上下文分配发言者，保持同一次澄清的负责人，并支持可停止、可恢复查询的群内咨询和任务接力。

**Architecture:** SQLite 保存任务、用户输入、执行步骤、澄清及事件，服务端单 worker 顺序领取步骤，SSE 只观察已持久化事件。保留现有群历史和消息 ID；路由与群内协作独立于私聊、定时任务及外部工具。

**Tech Stack:** 现有 Python/FastAPI/SQLite/asyncio、LLM stream_chat/complete_json、SwiftUI、VeraBotCore/Networking/Data/Persistence；不新增服务、供应商或产品依赖。

**Spec:** [已确认设计稿](../specs/2026-10-12-group-intent-and-handoff-design.md)。用户于 2026-10-12 回复“设计稿确认”。

## Global Constraints

- 采用设计稿推荐的完整执行方式：离开页面只停止观察，服务器继续执行有限任务；明确停止才取消任务。API 服务仍要求单 worker，不承诺多进程部署或 APNs 通知。
- 创建群人数仍为 2–4，同账号最多 10 个群，群名 1–64 字符，用户正文最多 2000 字符，单条附件最多 1 个。
- 每个用户输入的自动链最多 6 次 Bot 模型调用，咨询返回计数；同一问题最多自动返回修改一次。路由调用独立计费，也检查每日预算。
- 保留当前单 Bot 60 秒、单条回复 768 tokens、最近 24 条群消息和 12000 字符正文窗口；每条自动链总执行上限 240 秒，等待用户时间不计入执行耗时。
- 显式点名 > 回复关系 > 自然语言明确称呼 > 当前澄清 > 当前任务 > 职责；先识别明确停止和换题，避免把新请求吞入旧澄清。
- 不保留固定默认 Bot、首成员回退或本地点名粘性；公平澄清选择由服务器持久化，同一次澄清锁定 owner_member_id。
- 群内动作仅为 completed、consult、handoff、await_user；不得读取成员私聊/长期记忆，不新增联网、MCP、提醒或外部写入权限。
- 所有 SQL 位于 db/；事务内不调用模型。请求、步骤、usage 和事件具有独立幂等键；跨账号/跨群资源访问返回 404。
- 本计划仅定义检查和验收；执行时离线测试使用临时库与假模型。正式数据库迁移、真实模型验收、提交/合并/推送不由设计确认自动授权。

## Review Focus

1. 两台设备同时回答旧追问：只保留一个有效版本，第二次提交不能重复交接；Task 2/6 覆盖。
2. 用户说“好的”与明确换题：前者保持原澄清负责人，后者取消旧澄清并独立分配；Task 3 覆盖。
3. App 离开或观察流断开：服务器继续执行；重进得到真实状态，不把观察断线写成任务中断；Task 5/7 覆盖。
4. 停止/清空与迟到模型结果竞争：保留停止前内容，旧版本不能追加消息、安排动作或重启任务，已知费用仍记一次；Task 2/4/5 覆盖。
5. 更新前的本地群 JSON 与旧客户端请求：历史/草稿保留，新路由不恢复默认字段，旧协议写请求被明确拒绝；Task 1/6/7 覆盖。

## 文件职责与固定协议

后端新增 `db/group_execution_types.py`（共享类型）、`db/group_execution_store.py`（任务/步骤/澄清/事件/调用记账）、`services/group_dispatch.py`（事务级用户输入和业务规则）、`services/group_actions.py`（动作验证与下一步规划）、`services/group_worker.py`（生命周期与取消）、`api/routers/group_execution.py`（新执行 API）。现有 `group_routing.py` 只判意图，`group_runtime.py` 改为一个成员步骤的执行器，`group_context.py` 加入任务/澄清/交接资料。

客户端新增 `VeraBotCore/GroupExecution.swift`（公开协议）、`GroupExecutionReducer.swift`（按版本处理事件）、`VeraBotNetworking/GroupExecutionAPI.swift`（提交/观察），现有 GroupChatViewModel 和群界面调用这些协议。持久化层用现有 card_states 保存观察游标及任务快照，不新建客户端执行队列。

固定标识：`task_id` 表示一次持续目标；`version` 在用户修改目标/停止时递增；`input_id` 表示一次用户输入及其 6 次调用额度；`turn_id` 保留现有消息轮次；`step_id` 表示一次成员生成；`clarification_id` 跨多个输入保持。新独立请求创建新 task，澄清回答/当前任务补充沿用 task、创建新 input。停止不清零旧链计数，显式继续创建新 input。

`GroupInput` 字段：client_request_id UUID、message、target_member_ids（有序、不重复）、everyone Bool、reply_to_message_id?、attachment_ids、expected_task_id?、expected_version?、clarification_id?。目标列表和 everyone 互斥；服务器确定 Bot ID。待执行成员只存 member_id，不靠名称识别身份。

`RouteDecision` 字段：intent（respond/clarify/continue/replace/stop）、speaker_member_ids、goal、missing_information、clarification_id?、usage?、usage_unknown。stop 表示用户语义停止；明确 stop API 不需要模型判定。分类数据无效时调用确定性动态选择，模型调用故障和语义含糊分别记录。

`GroupAction` 字段：kind、target_member_id?、goal、result、context_message_ids、attachment_ids、completion_criteria、issue_key?、missing_information。completed 不带目标；consult/handoff 必须有同群可用目标；await_user 关联当前负责人和真实追问正文。`issue_key` 标识本轮要修改的同一个问题，防止通过变换动作 ID 重置回返次数。

GroupStep 的 kind 为 route 或 member：route 只调用意图分类，不占 6 次成员额度；member 调用一个成员并占额度。步骤结果固定为 `{content, action, usage, usage_unknown, status, error_code}`；status 为 completed/failed/stopped/interrupted。任务 awaiting_user 时该输入的旧 turn 记 completed，等待事实由 task 和 clarification 表示，避免改动旧轮次 CHECK 约束。

事件 envelope：id（递增 SSE cursor）、group_id、task_id、version、input_id、turn_id?、type、data。类型为 task_updated、clarification_updated，以及现有 turn_start/message_start/status/message_done/turn_done/error；新增 message_snapshot 包含累计正文。message_snapshot 替换正文，不追加累计文本。

## Task 1：迁移、共享类型和移除默认字段的存储语义

**Files:**
- Create: `backend/verabot/db/migrations/v024_group_execution.py`
- Create: `backend/verabot/db/group_execution_types.py`
- Create: `backend/scripts/test/group_execution_test_support.py`
- Create: `backend/scripts/test/group_execution_migration_test.py`
- Modify: `backend/verabot/db/migrations/__init__.py`, `backend/verabot/db/group_types.py`, `backend/verabot/db/group_store.py`

**Interfaces:**
- Produces: GroupInput、RouteDecision、GroupAction、GroupTask、GroupStep、GroupClarification、GroupEvent 的 TypedDict/枚举；公开序列化字段与上节完全一致。
- Produces: `group_store.create_group(user_id: int, name: str, bot_ids: list[int]) -> Group`；Group 无 default_bot_id。
- Fixture: `GroupExecutionFixture` 提供临时 DB、uid、other_uid、gid、members 和独立假模型，不启动后台 worker、不读取正式配置。

- [x] 添加 `test_migration_preserves_history_and_nulls_legacy_defaults`：v23 夹具升级两次，群/成员/消息/附件数量及历史 ID 不变；旧 default_bot_id 为 NULL，新 Group 不输出此字段，schema 为 24。
- [x] 添加 `test_one_active_clarification_and_one_running_step_per_group`：并发插入第二个活动澄清或执行步骤被唯一约束拒绝；不同群可独立保留状态。
- [x] 在 backend 运行 `uv run python scripts/test/group_execution_migration_test.py`，确认新行为在实施前失败。
- [x] v24 创建 `chat_group_tasks`、`chat_group_task_inputs`、`chat_group_steps`、`chat_group_clarifications`、`chat_group_events`、`chat_group_usage_calls`。tasks 保存 goal/version/state/owner/root_message_id；inputs 保存请求 hash、turn_id、链调用数/累计耗时；steps 保存 kind、action_key、input、version、成员、状态、consult_return_step_id、issue_key、lease_token 和过期时间；clarifications 保存 owner、原问题、缺失信息、最新追问/状态；events 保存有序 envelope；usage_calls 用 call_id 唯一约束绑定 usage_log。成员表新增 nullable last_clarified_at，最近发言数从当前群消息统计，换澄清负责人时更新新负责人成员行，保留前任公平选择时间。
- [x] 群主表保留 nullable 的旧列作为历史兼容数据，迁移时置 NULL；所有新读写移除默认语义。已有 turns 的 single/round 和消息表不重建；新执行状态由 tasks/steps 承担，旧历史依旧可读。
- [x] 保持迁移事务与外键约束，不调用 executescript；如果执行时最新 schema 已超过 23，顺延迁移编号并同步本计划，不覆盖并行迁移。
- [x] 再运行迁移测试，要求所有断言通过；保存仅包含本任务文件的可审阅 diff。

## Task 2：原子输入、澄清锁定、版本隔离与幂等存储

**Files:**
- Create: `backend/verabot/db/group_execution_store.py`
- Create: `backend/verabot/services/group_dispatch.py`
- Create: `backend/scripts/test/group_execution_store_test.py`
- Modify: `backend/verabot/db/group_store.py`

**Interfaces:**
- `group_dispatch.submit(user_id: int, group_id: int, request: GroupInput) -> GroupTask`：先原子保存用户输入和待路由步骤，再由 worker 分类；重复请求返回同一个快照，冲突正文返回 409。
- `store.snapshot(user_id: int, group_id: int, task_id: int | None = None) -> GroupTask | None`。
- `store.claim_next(worker_id: str, now: str) -> GroupStep | None`：事务领取，确保同群单步骤运行。
- `store.save_snapshot(step_id: int, lease_token: str, version: int, content: str) -> bool`。
- `store.commit_step(step_id: int, lease_token: str, version: int, result: dict) -> bool`：正文、状态、协作动作/后续步骤和事件在一个事务提交。
- `store.stop(user_id: int, group_id: int, task_id: int, expected_version: int) -> GroupTask`。
- `store.record_call(call_id: str, user_id: int, bot_id: int | None, kind: str, usage: dict | None, usage_unknown: bool) -> bool`。

- [x] 添加 `test_two_devices_answer_same_clarification_once`：相同 clarification/version 的不同并发请求只接受一个；另一条 409 task_version_changed，不产生第二次交接。
- [x] 添加 `test_stop_fences_late_result_and_keeps_usage_once`：停止后旧 lease/version 无法写正文或步骤，迟到已知 usage 可按 call_id 记一次；重复 stop 不再递增版本。
- [x] 添加 `test_request_idempotency_before_routing`、`test_clear_invalidates_waiting_clarification`、`test_cross_account_task_and_reference_are_404`。
- [x] 运行 `uv run python scripts/test/group_execution_store_test.py`，确认缺少新接口时失败。
- [x] 实现 submit：显式目标/回复/附件先校验归属，短事务领取请求、保存用户消息和原始待路由输入。调用模型前已有 input ID；分类服务失败不丢用户消息。旧运行版本先撤销待执行动作并标记 turn，再创建新 input；旧模型未取消确认前，领取约束不允许新步骤同时运行。
- [x] 澄清公平选择统计持久化，事务写 owner 和最近选择时间；等待用户释放 turn 的 running 锁，但保留 task.awaiting_user。新输入推进 version，旧双设备快照返回明确 409 并带最新 snapshot。
- [x] 回复部分文本与事件统一事务；clear/delete 作废任务及澄清并清理关联行，保留已知费用账目。旧 lease 不得因群删除后又创建同名群而继续写入。
- [x] 记账：路由 call_id 写 kind=group_routing，成员步骤沿用 kind=group_chat。新步骤的 save_reply 使用统一 call ledger，避免现有 save_reply 和新 ledger 双重记账；旧历史恢复保留原 usage_logged 兼容。
- [x] 再运行本任务测试及 Task 1 测试，要求 PASS；保存本任务 diff。

## Task 3：带上下文的路由和动态澄清选人

**Files:**
- Modify: `backend/verabot/services/group_routing.py`
- Create: `backend/scripts/test/group_clarification_test.py`
- Modify: `backend/scripts/test/group_routing_test.py`

**Interfaces:**
- `resolve(user_id: int, group: Group, request: GroupInput, snapshot: GroupTask | None, history: list[GroupMessage], clarification: GroupClarification | None) -> RouteDecision`。
- `choose_clarifier(group: Group, relevant_member_ids: list[int], current_owner_id: int | None, fairness: dict) -> int | None`：纯函数；同等相关时按最近澄清选择时间、近期发言数、稳定成员顺序排序。
- `store.apply_route(step_id: int, lease_token: str, version: int, decision: RouteDecision) -> bool`：在 Task 2 store 中事务创建初始成员步骤或更新澄清，提交前再次校验 version/成员可用性。

- [x] 添加 `test_clear_request_with_two_capable_bots_does_not_clarify`、`test_ambiguous_goal_selects_dynamic_clarifier`、`test_ok_preserves_owner_but_new_topic_releases_it`。
- [x] 添加 `test_clarification_owner_survives_two_answers_and_restart`、`test_owner_unavailable_transfers_all_answers`、`test_router_failure_never_uses_legacy_default`、`test_same_name_does_not_forge_identity`。
- [x] 运行 `uv run python scripts/test/group_clarification_test.py`，确认新路由行为在实施前失败。
- [x] 实现优先级及明确停止/换题判断：结构化点名/回复先确定目标；纯澄清回答保持 owner，除非明确换题、停止或用户改点名。一般语义分类包含最近 24 条/12000 字符、任务目标、缺失信息和本条输入，不读取私聊。
- [x] 分类请求仅允许受校验 JSON，无工具，max_tokens=512；结果须符合 RouteDecision 且目标是可用成员。usage 交由 Task 2 ledger 记一次。无效结果/异常通过确定规则和动态 choose_clarifier 回退，不把模型故障日志当成用户含糊的证据。
- [x] 明确目标不可用时保留指向信息，由已有澄清负责人说明并询问需求；没有现任负责人时选择动态澄清 Bot。零可用成员返回 read_only，不编造回复。
- [x] 再运行两个路由/澄清测试文件，要求 PASS；保存本任务 diff。

## Task 4：单成员执行、结构化咨询与交接

**Files:**
- Create: `backend/verabot/services/group_actions.py`
- Modify: `backend/verabot/agents/group_runtime.py`, `backend/verabot/agents/group_context.py`
- Create: `backend/scripts/test/group_handoff_test.py`
- Modify: `backend/scripts/test/group_runtime_test.py`

**Interfaces:**
- `group_runtime.run_step(step: GroupStep, should_stop: Callable[[], bool]) -> dict`：一名成员的一次生成，返回 content、GroupAction、usage/unknown 和最终状态；增量交 Task 2 save_snapshot。
- `group_actions.validate(user_id: int, group: Group, task: GroupTask, step: GroupStep, raw_action: dict) -> GroupAction`。
- `group_actions.next_steps(task: GroupTask, step: GroupStep, action: GroupAction) -> list[dict]`：纯规划，不执行模型/SQL；Task 2 commit_step 原子落地。

- [x] 添加 `test_consult_returns_to_original_owner`：A→B→A，目标和 B 的结果完整返回，A 保持任务负责人；`test_handoff_changes_owner`：A→B，最终 B 交付，不再自动调用 A。
- [x] 添加 `test_plain_text_mention_does_not_schedule`、`test_invalid_or_duplicate_action_cannot_call_model`、`test_clarifier_asks_once_then_waits`、`test_resolved_clarification_handoff_keeps_all_requirements`。
- [x] 添加 `test_six_calls_includes_consult_return`、`test_one_revision_return_per_issue`、`test_group_context_does_not_load_private_history_or_tools`。
- [x] 运行 `uv run python scripts/test/group_handoff_test.py`，确认缺少新动作处理时失败。
- [x] llm.stream_chat 只暴露内部函数 `group_next_step`，严格要求 GroupAction 结构，最多一个协作动作；不接入私聊通用工具。无动作且正文完成时按 completed；多个/无效动作记录友好失败，不执行其中部分动作。
- [x] group_context.build 加当前目标、当前成员、澄清收集结果、咨询返回信息、允许的下一步和剩余调用预算。await_user 须有真实追问正文，保存追问后停止该执行链，不生成第二个自问步骤。
- [x] consult 建立返回栈，B 完成后调度 A；handoff 不建立返回栈。合作目标只可来自本群，附件引用按群归属校验；实际有效动作落地后显示交接状态，正文提名不触发。
- [x] 每次调用（包括空回复重试）都占用 6 次额度；只有零正文且零动作允许一次空回复重试，不能超过链额度/耗时。每步 60 秒/768 tokens，链累计 240 秒，停止/预算用尽后不安排新动作。
- [x] 再运行 handoff/runtime 测试，要求 PASS；保存本任务 diff。

## Task 5：服务端独立 worker、持久事件和中断恢复

**Files:**
- Create: `backend/verabot/services/group_worker.py`
- Modify: `backend/verabot/main.py`, `backend/verabot/db/group_execution_store.py`
- Create: `backend/scripts/test/group_worker_test.py`
- Modify: `backend/scripts/test/group_lifecycle_test.py`

**Interfaces:**
- `group_worker.process_one(worker_id: str) -> bool`，`group_worker.loop(worker_id: str) -> None`。
- `store.recover_interrupted(now: str) -> int`，`store.events(user_id: int, group_id: int, after_id: int, limit: int = 100) -> list[GroupEvent]`。
- `group_worker.request_cancel(task_id: int) -> None` 仅加速关闭上游；停止事实以持久任务版本为准。

- [x] 添加 `test_disconnect_observer_does_not_stop_worker`、`test_expired_or_shutdown_running_step_is_interrupted_not_replayed`、`test_queued_unstarted_step_is_safe_to_claim_after_restart`。
- [x] 添加 `test_stop_before_handoff_commit_has_no_successor`、`test_two_workers_cannot_claim_same_group`、`test_new_input_waits_for_old_model_cleanup`、`test_event_snapshot_and_usage_commit_are_atomic`。
- [x] 运行 `uv run python scripts/test/group_worker_test.py`，确认缺少 worker 时失败。
- [x] 单服务进程内托管 worker；持久 claim 使用 lease token/版本，lease 90 秒、每 15 秒续期、最多每 1 秒检查 stop。不同群可排队，首版一个群执行 worker 串行服务所有群，不引入模型并行调度。
- [x] 持久 message_snapshot 每新增 256 字符或距上次写入 1 秒（有新正文时）落地，最终全量保存；事件累计正文可重放，客户端无需依赖断线前 delta。SSE heartbeat 不写业务事件。
- [x] main startup 先恢复旧轮次和新的失效 running：有过模型调用的步骤置 interrupted，待执行后继不自动接着调用；awaiting_user 澄清保持原 owner。从未开始的 queued 输入可领取。shutdown 取消/等待 worker 清理、保存部分文本和已知 usage，未知值不伪造为零。
- [x] 与 scheduled_tasks 的 worker 和 lease 分离，不移动其表或改变其恢复策略。保持当前 API 单 worker 部署限制。
- [x] 再运行 worker/lifecycle 测试，要求 PASS；保存本任务 diff。

## Task 6：群协议 v2、提交与观察 API

**Files:**
- Create: `backend/verabot/api/routers/group_execution.py`
- Modify: `backend/verabot/api/group_schemas.py`, `backend/verabot/api/routers/groups.py`, `backend/verabot/api/routers/meta.py`, `backend/verabot/main.py`
- Create: `backend/scripts/test/group_execution_api_test.py`
- Modify: `backend/scripts/test/group_store_test.py`, `backend/scripts/test/group_http_test.py`, `backend/scripts/dev/group_chat_demo.py`

**Interfaces:**
- `POST /api/groups/{gid}/inputs` → 202 `{task,input_id,turn_id,event_cursor}`；重复 UUID 返回相同资源和 200，不再次分类。
- `GET /api/groups/{gid}/inputs/{client_request_id}` → 同一 receipt 或 404，用于确认提交结果，不启动模型。
- `GET /api/groups/{gid}/execution` → `{task?,clarification?,event_cursor}`，快照/游标在同一 SQLite 读取事务获得。
- `GET /api/groups/{gid}/events?after_id=N` → SSE，首版所有业务事件持久保留，按 id 严格递增；跨群游标不得返回其他群内容。
- `POST /api/groups/{gid}/tasks/{tid}/stop`，`POST .../{tid}/resume`，`POST /api/groups/{gid}/messages/{mid}/retry-v2`：都带 client_request_id/expected_version，返回最新 task。resume 创建新 input；retry 只重试失败成员步骤，不重做已完成成员和已提交动作。
- 群写请求要求 `X-VeraBot-Group-Protocol: 2`；meta 返回 group_protocol_version=2。不满足时返回 426 group_upgrade_required。旧 history GET 保持可读，旧 chat/retry 写入口明确拒绝，不进入旧默认回退路径。

- [x] 添加 `test_submit_ack_survives_socket_disconnect`、`test_duplicate_submit_returns_same_input_without_model_call`、`test_reply_reference_and_cursor_cannot_cross_group`、`test_stop_waiting_clarification_without_running_turn`。
- [x] 添加 `test_old_protocol_writes_are_426_and_history_is_readable`、`test_create_and_rename_without_default_field`、`test_retry_only_failed_step`、`test_clear_waiting_task_and_late_result`。
- [x] 运行 `uv run python scripts/test/group_execution_api_test.py`，确认新 API 尚未存在时失败。
- [x] 接线 Task 2/3/5；observer 断开仅关闭读取器，不能调用 interrupted 或停止模型。SSE 支持 Last-Event-ID/after_id，重复/过期任务事件由版本识别；游标前的数据在首版不清理，避免默默缺事件。
- [x] 426 检查作用于全部群写入口；移除 default_bot_id 的输入字段和服务逻辑，包含管理和 clear/delete 的协议校验。修改测试夹具和独立 demo 的版本 header；启动正式服务不引用假模型。
- [x] 再运行 API/store/http 的临时库用例，要求 HTTP 契约和事件顺序符合本节；保存本任务 diff。

## Task 7：Swift 协议、观察状态和离线快照兼容

**Files:**
- Create: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/GroupExecution.swift`
- Create: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/GroupExecutionReducer.swift`
- Create: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotNetworking/GroupExecutionAPI.swift`
- Modify: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/GroupChat.swift`, `Sources/VeraBotNetworking/GroupChatAPI.swift`, `Sources/VeraBotNetworking/GroupChatEventParser.swift`
- Modify: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotData/GroupChatViewModel.swift`, `Sources/VeraBotData/ConversationRepository.swift`, `Sources/VeraBotPersistence/ConversationStore.swift`
- Create: `frontend/ios/Packages/VeraBotKit/Tests/VeraBotKitTests/GroupExecutionTests.swift`
- Modify: `Tests/VeraBotKitTests/GroupChatNetworkTests.swift`, `GroupChatViewModelTests.swift`, `GroupPersistenceRecoveryTests.swift`, `GroupChatContractTests.swift`

**Interfaces:**
- Swift GroupInputRequest/GroupTask/GroupClarification/GroupExecutionEvent 与后端字段对齐；新增协议 `submitGroupInput(groupID:request:) async throws -> GroupInputReceipt`、`groupExecution(groupID:) async throws -> GroupExecutionSnapshot`、`observeGroupExecution(groupID:afterID:) -> AsyncThrowingStream<GroupExecutionEvent,Error>`、`stopGroupTask(groupID:taskID:expectedVersion:requestID:) async throws -> GroupTask`、对应 resume/retry 方法。
- `GroupExecutionReducer.apply(_:to:)` 按 group/task/version/cursor 校验，message_snapshot 全量替换，历史 turnDone 不丢弃当前新任务状态。
- GroupChatViewModel 的 leave 仅 detach observer/saveDraft；stop 单独请求服务端。send 在任务运行时也可提交新指令，基于当前版本；loading、提交防重和 session guard 仍有效。

- [x] 添加 `oldGroupJSONWithoutDefaultDecodesAndPreservesDraft`、`sameClarifierAfterReloadAndAccountScopedCache`、`observerDisconnectDoesNotMarkTaskInterrupted`、`lateOldVersionEventDoesNotReplaceNewTask`、`cumulativeSnapshotIsNotDuplicated`。
- [x] 添加 `leaveNeverCallsStopButExplicitStopDoes`、`concurrentDevicesConflictRestoresSnapshotWithoutResend`、`submitUncertainQueriesSameUUID`：提交连接中断时按 UUID 查询 Task 6 的 receipt；若 404，仅使用同一个 UUID 和同一正文重试，不能生成新 UUID。已有请求与不同正文返回 409。
- [x] 在包目录运行 `swift test --filter GroupExecution`，确认新协议/行为尚未存在时失败。
- [x] ChatGroup 解码忽略旧 default 字段，删除 defaultMemberID/defaultBotID/preferredBotID；旧缓存 JSON 的历史与草稿继续读取。旧 UserDefaults 点名偏好清理且不参与任何路由。
- [x] 增加 repository 保存/读取群执行快照及事件 cursor，复用 card_states 的 kind=group/card_kind=execution；消息和 cursor 同一事务保存，防止崩溃后漏正文。离线缓存显示“进度待同步”，不把缓存 streaming 自动改成服务器 interrupted。
- [x] load 先显示本地历史，再取得快照与游标，随后观察新事件；旧 epoch/账号事件不写当前 UI 或新账号缓存。后台/注销停止观察，不隐式停止服务端任务。
- [x] 再运行 GroupExecution、GroupChat、GroupPersistence 相关包测试，要求 PASS；保存本任务 diff。

## Task 8：群界面去默认、多人点名、回复和交接状态

**Files:**
- Modify: `frontend/ios/VeraBot/Features/GroupChat/CreateGroupSheet.swift`, `GroupInfoView.swift`, `GroupChatView.swift`
- Create: `frontend/ios/VeraBot/Features/GroupChat/GroupExecutionStatusView.swift`
- Modify: `frontend/ios/VeraBot/Features/GroupChat/MentionTextEditor.swift`（仅必要的目标收集接线）
- Modify: `frontend/ios/Packages/VeraBotKit/Tests/VeraBotKitTests/GroupChatContractTests.swift`

**Interfaces:**
- `GroupExecutionStatusView(snapshot: GroupExecutionSnapshot, onStop: () -> Void, onResume: () -> Void)`；只显示当前成员、接力、等待用户/中断/失败的产品状态。
- 输入收集有序全部 mention token，映射 target_member_ids；everyone 覆盖成员集合。正文只有名字不生成结构化点名。回复入口携带真实 reply_to_message_id，不仅拼接文本。

- [x] 添加 `multiMentionKeepsSelectedOrder`、`everyoneDoesNotMixWithExplicitTargets`、`createAndRenameRequestsContainNoDefaultField`；运行对应 Swift 过滤测试，确认旧行为失败。
- [x] 创建页只选群名/成员，设置页移除默认选择和标记，删除旧偏好读写。保留头像、成员状态、Markdown、附件、语音和当前键盘交互。
- [x] 接入实际任务状态和回复入口；待澄清时正常显示 Bot 追问，发送用户回答携带 clarification/version。正在执行时发送新指令可提交，停止按钮使用 task 而非只看 running turn。
- [x] 不在正文中显示内部 ID/lease/JSON 动作；交接状态在动作验证和保存后展示。显示“后台继续”需要当前服务返回 v2 支持，旧服务不得误显示此能力。
- [x] 再运行相关 Swift 测试；用独立 DerivedData 构建现有 VeraBot scheme 到可用 iOS Simulator，要求 BUILD SUCCEEDED。此处是构建验证，设备点按由 Task 9 单列。

## Task 9：集成回归、部署说明和用户验收交付

**Files:**
- Create: `backend/scripts/test/group_execution_http_test.py`
- Create: `docs/testing/2026-10-12-group-intent-and-handoff.md`
- Modify: `backend/README.md`, `docs/README.md`, `docs/STATUS.md`, `docs/CHANGELOG.md`, `docs/product/FEATURES.md`
- Modify: `docs/ops/RUN_LOCAL.md`, `docs/design/ARCHITECTURE.md`, `docs/testing/TEST_CASES_v0.1.md`

**Interfaces:** Task 1–8 的数据库、API、worker、iOS 协议；本任务不增加新的产品能力。

- [x] 临时库/假模型运行 `group_execution_migration_test.py`、`group_execution_store_test.py`、`group_clarification_test.py`、`group_routing_test.py`、`group_handoff_test.py`、`group_worker_test.py`、`group_execution_api_test.py`。每个命令在 backend 为 `uv run python scripts/test/<文件>`，要求全部 PASS；首轮失败修复后只重跑受影响组。
- [x] 独立 localhost 临时 demo 服务运行 socket/SSE 用例：含糊输入→A追问→用户回答→仍A→明确后交给B；关闭观察连接→服务器B完成→重连读完成快照；咨询A→B→A；停止后无后继；旧协议426。`uv run python scripts/test/group_execution_http_test.py http://127.0.0.1:8093` 仅连接新建临时 demo，不连正式8000。
- [x] 运行现有 group_store/runtime/lifecycle 和私聊 `multi_agent_test.py`、`status_event_test.py`、`llm_body_test.py`、`sql_layer_check.py`；相关 scheduled_task_store/worker 与 ConversationRepository 包测试证明没有改其行为。所有这些用例必须使用临时夹具，无真实调用。
- [x] 包目录 `swift test`，完成模拟器 Debug 构建；按交付范围再决定设备构建/安装。验证日志与用户交互结果分别记录，不用假模型通过记录替代真实讨论质量。
- [x] 记录设计验收项 1–10 的 Pass/Fail/Problem/Not-triggered，逐项区分自动化证据与真实模型/设备验收；未触发的现场检查保持 Not-triggered，假模型结果不替代真实体验。
- [x] 部署说明包含：服务端备份/v23→v24 迁移和 v2 App 的顺序；旧群只清默认值不删历史；API 单 worker；worker 托管；停止/后台差异；未知 usage 和中断恢复；旧客户端升级提示。正式库迁移前准备可恢复备份，执行须有用户授权。
- [x] 更新状态文档只写本轮实际完成和证据。提交/合并/推送另按用户明确范围操作，不能把整个工作区自动加入提交。

## 计划自检与执行交接

- Spec §1/10 默认移除：Task 1/6/7/8；§4/5 动态澄清：Task 2/3/7；§6 多人排序：Task 3/4/8；§7 协作：Task 4；§8 持久任务：Task 2/5/6/7；§9 限制/停止：Task 2/4/5/6；§11 验收：Task 9。
- 五项 Review Focus 已分别落入任务测试；协议字段、ID 和函数名由前置 Interfaces 定义，后续步骤引用同一合同。
- 全文采用推荐的后台完整模式，不同时实现请求绑定模式；仍保留单 API worker 限制，不改造为通用任务平台。
- 已在 `/Users/admin/.codex/worktrees/group-intent-handoff/VeraBot-v0.1` 隔离工作树按任务顺序实施；主工作区未改动。当前实现和证据见 [实现记录](../../testing/2026-10-12-group-intent-and-handoff.md)。
- 后续整合、正式数据库迁移、真实模型/设备验收及提交、合并、推送仍需按用户明确指示另行处理。
