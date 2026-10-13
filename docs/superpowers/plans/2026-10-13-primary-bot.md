# 主 Bot 第一版实施计划

> 用户已回复“确认, 执行”，采用Native隔离实现。实现完成与各任务取舍见[交付记录](../../testing/2026-10-13-primary-bot.md)及本地ledger；原待评审说明为计划写作快照。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for native execution, or superpowers:subagent-driven-development only if the user chooses delegation. Steps use checkbox (`- [ ]`) syntax for tracking. 用户已确认设计并要求开始实施；本计划为新增的具体执行契约，待评审与执行方式确认。禁止据此重复开发已合入的群 v2。

**Goal:** 从现有 Bot 选择日常负责人，支持明确交办/周期工作、持久进度、有限咨询、阻塞求助和 MCP 批准后继续。

**Architecture:** 保持群执行和现有定时 v1 路径，新建账号主 Bot 设置及独立业务任务/步骤/事件存储。复用 SQLite、lease/version/call_id 模式和既有 MCP 冻结参数确认；周期由原排程产生唯一业务实例。新 Worker 运行在独立后台进程，手机仅提交/观察，初期不抽取或重构群引擎。

**Tech Stack:** Python/FastAPI/SQLite/asyncio、现有模型和工具调用层；SwiftUI、VeraBotCore/Networking/Data/Persistence；不新增供应商、Redis/Celery、APNs 或电脑操作环境。

**Spec:** [已确认方案](../specs/2026-10-13-primary-bot-design.md)。用户于 2026-10-13 回复“OK, 开始实施, 实施前检查进度”，采用推荐 B 范围；具体工程契约见本计划。

## Global Constraints

- 起点：本机 main `b81caed`，群功能 `a01b2d7` 已合入，源码 schema v25；原开发库升级与真实群交互仍未完成，不由本任务代做。
- 主工作区有其他未提交 UI/文档，产品实现使用 native 工具创建隔离工作树、分支 `codex/primary-bot`，基于检查时本地 main。执行前重新确认 HEAD/迁移版本；不复制无关 UI 改动。
- 每账号零或一个主 Bot；选择不自动启用主动执行或扩权；更换不移交旧任务；删除清空关联并停止其未完成步骤，不自动换负责人。
- 第一版仅明确交办/周期工作；App 内查看，不加入 APNs、生产部署、Gmail 邮件工具或根据闲聊推断新任务。普通聊天默认不创建任务；通过“交办任务”入口确认目标才启动。
- 租约90秒/每15秒续租；提供者已知临时失败30/120秒、最多3次尝试。进程重启标未知在途步骤 interrupted，不重放；完成步骤不重跑。
- 每次用户触发的自动链最多6次实际模型生成（含咨询返回、工具后再生成和空回复重试），等待用户释放Worker；账号日额度、主动额度与任务总额度全部检查，未知用量不记成0。
- 新路径默认单模型调用60秒、自动链累计运行240秒（等待不计）；每次链累计输出2048 tokens、工具4轮/8次，预算计数持久化。首次任务总用量上限20000 tokens、账号每日主动上限20000 tokens，均为软上限并仍受账号原额度约束；创建界面显示上限。续链不清零任务总额度。
- 每次执行取冻结授权与当前权限交集；外部结果污染标记跨步骤保留；咨询Bot无MCP权限，不开放后台记忆写入或未经专项接入的内置写工具。
- 主 Bot 不改变群动态选人，不成为群默认成员；没有新授权则不能读取其他私聊或敏感共享记忆。
- 所有新增SQL在db层；针对新增代码检查，不宣称既有全库SQL违规已修复。只使用临时数据库/假提供者验证，正式数据库/服务/设备交付和真实模型另列验收步骤。
- 本轮授权不包含合并、推送、删除工作树或混入其他改动；完成后提供可审阅变更。依用户后续范围决定提交与集成。

## Review Focus

- 双设备同时回答/批准：版本与唯一resolution约束只产生一个后继（Task 4/7）。
- 选择主Bot与费用授权分离：选择后空闲不调用模型，主动关闭能取消后台步骤（Task 1/5）。
- 周期等待用户：跳过新发生，不重复追问，回答恢复原实例（Task 6）。
- 工具调用结果未知：旧批准、服务重启、定义变化不能重发已可能执行的操作（Task 7）。
- 账号切换及离线事件：旧请求不能写入新账号/服务器，清空历史不复活任务消息（Task 8）。

## Task 1：主 Bot 账号设置与迁移（P0）

**Files:** Create `backend/verabot/db/migrations/v026_primary_bot.py`、`backend/verabot/db/primary_bot_store.py`、`backend/verabot/services/primary_bot.py`、`backend/verabot/api/routers/primary_bot.py`、`backend/verabot/api/primary_bot_schemas.py`、`backend/scripts/test/primary_bot_test.py`；Modify `db/migrations/__init__.py`、`services/users.py`、`main.py`、`db/bot_store.py`。

**Interfaces:** `primary_bot.get(user_id:int)->dict`；`primary_bot.update(user_id:int,payload:dict,expected_version:int)->dict`。返回 primary_bot_id/active_enabled/daily_token_limit/version；`GET/PATCH /api/primary-bot`，PATCH必须expected_version，null明确取消。`GET /api/me`附可选primary_bot_id，不返回私密配置。

- [ ] 临时库测试：迁移两次不损数据；设置自己的Bot；他人/不存在Bot统一404；旧version409；并发选择仅一方成功；置顶/群成员/权限不变；设身份不调用模型。
- [ ] 运行 `PYTHONPATH=. .venv/bin/python scripts/test/primary_bot_test.py`，观察新接口/迁移缺失失败。
- [ ] 新建按user_id唯一的primary_bot_settings表（Bot引用ON DELETE SET NULL），存设置版本、active_enabled默认false、日限额默认20000；删除Bot时同事务清空身份并推进版本。用户服务公开字段从该表读取，不扩大旧敏感资料查询。
- [ ] GET/PATCH与所有权/版本验证落地；禁止仅通过客户端本地设置维护身份；再运行该测试要求全部PASS。

## Task 2：iOS 身份选择、徽章与账号缓存（P0）

**Files:** Create `VeraBotCore/PrimaryBot.swift`、`VeraBotNetworking/APIClient+PrimaryBot.swift`、`VeraBotData/PrimaryBotRepository.swift`（均位于`frontend/ios/Packages/VeraBotKit/Sources`）、对应`Tests/VeraBotKitTests/PrimaryBotTests.swift`；Modify `VeraBotCore/Models.swift`、`VeraBotPersistence/ConversationStore.swift`、App的`AppState.swift`、`Core/UI/BotAvatar.swift`、`Core/UI/LiveBotAvatar.swift`、`Features/BotInfo/BotInfoView.swift`、`Features/BotList/BotListView.swift`。

**Interfaces:** Swift `PrimaryBotSettings:Codable,Sendable,Equatable`映射Task1字段；`PrimaryBotRepository.load()`/`update(botID:activeEnabled:expectedVersion:)`；User.primaryBotID缺键为nil。仓库按账号/服务器保存设置快照，写入失败保留旧权威版本。

- [ ] 测试旧User解码、设置回读、409同步、离线回读与账号切换丢弃迟到结果；头像是否主Bot由账号设置与botID比较，不改Bot人设或shape字段。
- [ ] 运行`swift test --filter PrimaryBotTests`观察失败；再实现Core/Networking/Data/Persistence协议与默认兼容。
- [ ] 详情菜单增加设置/取消；统一头像外叠SF Symbol星形徽章及“主 Bot”无障碍说明，形状/照片不变；助理页主Bot快捷入口不改变用户排序。所有按钮原生样式。
- [ ] 重跑身份测试并构建一次；更新P0状态。此时只完成身份，不宣称持续办事已完成。

## Task 3：定时任务管理与明确交办入口（P1）

**Files:** Create `VeraBotCore/ScheduledTask.swift`、`VeraBotNetworking/APIClient+ScheduledTasks.swift`、`VeraBotData/ScheduledTaskRepository.swift`、`Tests/VeraBotKitTests/ScheduledTaskTests.swift`；App新增`Features/Tasks/ScheduledTaskListView.swift`、`ScheduledTaskEditorView.swift`、`ScheduledTaskHistoryView.swift`，Modify `Features/Chat/ChatView.swift`。

**Interfaces:** Swift `ScheduledTask/Run/Create/Update`严格映射现有`api/scheduled_task_schemas.py`；API list/detail/create/update/pause/resume/delete/run/history。每个创建/手动执行意图保留稳定Idempotency-Key直到确定回执；编辑/暂停/删除用expected_version。

- [ ] 测试重复提交沿用key、编辑冲突不覆盖、服务器时区/DST错误原样显示、取消编辑零请求、旧账号结果丢弃。所有测试先失败后实现。
- [ ] 在Bot更多菜单新增任务入口，周期编辑确认标题/指令/时区/首次时间/频率/权限范围；默认当前Bot，日常快捷交办默认主Bot。
- [ ] 一次性交办先提供目标与完成标准草稿，不经确认启动；业务提交在Task4接线，期间入口不伪称已提交。自然语言频率可用现有模型生成待确认草稿，但不增加直接写排程工具。
- [ ] 完成Core/API/UI字段对照并运行专项Swift、现有36项定时回归。P1验收周期CRUD及结果查看，原v1仍只读。

## Task 4：持久业务任务、输入、步骤与事件（P2）

**Files:** Create `db/migrations/v027_owned_tasks.py`、`db/owned_task_store.py`、`db/owned_task_types.py`、`services/owned_tasks/{__init__,service}.py`、`api/owned_task_schemas.py`、`api/routers/owned_tasks.py`及`scripts/test/owned_task_{store,api}_test.py`；Modify `main.py`/迁移入口。

**Interfaces:** `create(user_id:int,payload:dict,key:str)->dict`；`submit_input(user_id:int,task_id:int,payload:dict,key:str,expected_version:int)->dict`；`control(user_id:int,task_id:int,action:str,expected_version:int)->dict`；`snapshot(user_id:int,task_id:int)->dict`。新`/api/owned-tasks`创建/查询、`/{id}/inputs`、`/{id}/stop|continue|transfer`、`/{id}/events?after_id=`。任何输入/控制先持久后执行，不调用run_chat。

- [ ] 测试请求幂等/内容不同409、双设备补充仅一次、等待用户释放执行锁、停止/移交推进版本、跨账号404、删除负责人停止步骤、事件ID清空后不复用；先运行两脚本确认失败。
- [ ] 创建owned_tasks/inputs/steps/waits/events/calls。保存目标、完成标准、origin引用、负责人身份快照、权限/记忆引用、总预算、链计数、状态/version、租约/检查点与唯一action_key；每任务只允许一个running步骤。
- [ ] 状态严格限queued/running/awaiting_user/awaiting_approval/retry_wait/completed/stopped/failed/interrupted；wait绑定task/step/version。新用户输入关联原目标并取消旧版本，重放相同key仅返回原回执。
- [ ] transfer仅显式请求，等待或停止后移交；按接收Bot重新取授权交集，失去所需权限则awaiting_user。身份设置更换不调用transfer。实现API，回归要求全部PASS。

## Task 5：受限后台执行、工具策略与有限咨询（P2）

**Files:** Create `services/owned_tasks/{worker,executor,policy,context,delivery,__main__}.py`、`scripts/test/owned_task_{worker,executor,process,policy}_test.py`；Modify `db/owned_task_store.py`、`agents/tool_router.py`、`tools/registry.py`。

**Interfaces:** `worker.process_one(owner:str)->bool`；`store.claim_next(owner:str,now:str)->dict|None`；`store.commit_step(step_id:int,lease_token:str,version:int,result:dict)->bool`；`executor.run_step(step:dict)->dict`。动作completed/consult/await_user/await_approval/retry_wait受JSON schema与服务器校验；consult生成独立子步骤，结果回原负责人，无递归run_once。

- [ ] 先测试lease竞争/续租、停止迟到正文与已知usage、重启不重复提供者请求、空闲零模型调用、主动关闭取消排队/在途步骤、六次实际调用含重试与咨询返回。
- [ ] 实现独立进程`python -m verabot.services.owned_tasks`，支持`--once`；不在API启动新任务Worker。全部实际模型请求前领取唯一call_id/额度计数，usage单独去重持久；超时/软预算依据Global Constraints。
- [ ] 工具白名单冻结且当前再核验。天气/提醒列表/目录认可MCP读可用；网页搜索和正文读取按既有policy使用，来源引用和计数持久，外部污染跨步骤保留；咨询Bot不使用MCP/联网，不调用普通ask_bot绕开限制。
- [ ] 只读取当前任务资料及明确授权记忆；记忆写入/提醒写入/自建任务工具拒绝。模型完成动作核验必需步骤/成果，缺结果不可completed。结果持久后去重投递原Bot对话/通知；清除消息不得再投递复活。
- [ ] 三类临时服务验证：A咨询B回A；Worker强杀恢复；通知故障只重投递。保持既有群worker协议/表不变，以上专项全部PASS。

## Task 6：周期产生业务实例与阻塞去重（P2）

**Files:** Create `db/migrations/v028_owned_schedule_bridge.py`、`services/owned_tasks/schedules.py`、`scripts/test/owned_task_schedule_test.py`；Modify `services/scheduled_tasks/{scheduler,worker,service}.py`、`db/{scheduled_task_store,scheduled_run_store,owned_task_store}.py`、`api/scheduled_task_schemas.py`。

**Interfaces:** 新排程可选`execution_mode=owned`（旧值默认read_only）；`schedules.enqueue_occurrence(c,run:dict)->int|None`绑定唯一scheduled_run_id与业务任务。不得同时跑原executor和owned_worker；周期规则沿用schedule.py。

- [ ] 测试旧排程全部行为不变、重复tick一次实例、原实例等待时新发生标skipped/awaiting_previous_run、回答仍恢复原实例；跨重启投递/计费不重复。
- [ ] 仅用户确认的owned排程走桥接；同一事务产生run/业务实例/链接，新worker完成后更新对应run。使用现有skip/latest/DST；业务排程结果只由一个投递路径负责。
- [ ] 日常主Bot仅在创建时解析为固定owner；主Bot更换不改旧排程。新增权限必须重新确认修改，不自动刷新任务授权上限。
- [ ] 新专项及原36项回归PASS，P2完成明确交办/周期跟进/求助，但MCP写确认续跑依Task7。

## Task 7：MCP 操作确认与任务回接（P3）

**Files:** Create `db/migrations/v029_owned_task_actions.py`、`services/owned_tasks/approvals.py`、`scripts/test/owned_task_approval_test.py`；Modify `services/actions/__init__.py`、`db/{action_store,owned_task_store}.py`、`agents/tool_router.py`、`api/routers/actions.py`。

**Interfaces:** `approvals.create(ctx,tool:dict,arguments:dict)->dict`保存task_id/step_id/task_version与冻结参数；`approvals.resolve(c,action:dict,resolution:str,result:dict|None)->bool`通过唯一resolution_id回接。旧action无任务引用保持原行为。

- [ ] 先测确认前/拒绝零远程调用、双设备批准只一次、过期/已停止/旧version不调用、工具定义变更重新确认；成功结果回接丢失可重试回接但不再调用远程。
- [ ] 支持提出批准的MCP写操作，但调用前再次核验现有连接/授权/冻结参数/定义hash/版本。wait解除与后继创建原子且幂等，拒绝/过期保存为awaiting_user并说明原因。
- [ ] 调用已领取后进程终止或上游超时保持unknown/interrupted；只允许有上游幂等或结果查询证据的恢复，不以“未知”重新调用。批准不自动解除外部资料污染限制。
- [ ] 新审批测试和`mcp_m3_test.py`独立临时库回归PASS；不要把原卡片执行消息和任务交付重复展示/重复记账。

## Task 8：iOS 持续任务、求助与事件恢复（P2/P3）

**Files:** Create `VeraBotCore/OwnedTask.swift`、`VeraBotNetworking/APIClient+OwnedTasks.swift`、`VeraBotData/OwnedTaskRepository.swift`、`Tests/VeraBotKitTests/OwnedTaskTests.swift`；Modify `VeraBotPersistence/ConversationStore.swift`、`Features/Tasks/*`、`Features/Chat/ChatView.swift`、`Features/Chat/ChatViewModel.swift`。

**Interfaces:** 任务快照、输入回执、单调cursor和task/step/version身份保持一致。Repository.submit/answer/stop/continue/transfer稳定请求ID，事件帧边读边应用；wait/action卡片操作携带准确任务版本。网络失败留待确定请求，不另建UUID重发。

- [ ] 先测真实localhost帧在服务器未结束时到达、重复事件去重、双设备409同步、离开只停止观察、等待两次回答沿同目标、清历史/换账号丢弃旧消息和旧缓存。
- [ ] 正式任务列表分进行中/等你处理/已完成；详情显示目标/完成标准/负责人/进度/下一步/费用及停止/继续/移交。提交草稿明确显示主动范围与预算，用户确认后才调用业务API。
- [ ] 求助提供明确缺失信息和建议，复用MCP卡片显示批准；普通聊天“好的”不自动匹配任务批准。App重新进入回读快照+事件，不仅依赖通知。
- [ ] 运行专项及Swift全量一次、模拟器构建；实际模型/用户交互保持待验收，原群聊天路由与SSE契约回归。

## Task 9：分阶段验收、文档与交付准备

**Files:** 更新`README.md`、`docs/{STATUS,CHANGELOG,README,ROADMAP_NEXT}.md`、`docs/product/FEATURES.md`、`docs/design/ARCHITECTURE.md`、`docs/ops/RUN_LOCAL.md`；新增`docs/testing/2026-10-13-primary-bot.md`及任务服务README。

- [ ] P0、P1、P2、P3分别记录源码状态/测试/用户未验收项，不能只完成徽章便标整体完成。
- [ ] 后端各脚本独立临时库运行；原定时36项、group_handoff/group_worker与MCP确认回归按修改影响选择，避免全目录discover污染。记录新增SQL检查结果与既有基线区别。
- [ ] 副本v25→v29迁移两次检查完整性/计数、旧User与旧排程兼容；正式数据库不自动升级。如果并行迁移编号变化，整体顺延并同步契约/测试。
- [ ] 假提供者端到端：确认交办→主动后台→缺资料→App重启回读→补充→咨询→MCP确认→下一步完成；中途分别停止、断开、杀Worker和投递失败不重复操作。
- [ ] 准备隔离模型/数据库手动环境，用户真实模型与UI验收列未触发；未经明确请求不替换当前8000/8094验收服务、不安装真机、不推送或合入main。
- [ ] 提供范围清晰的可审阅diff、阶段完成清单及运行方式；本计划全部阶段通过后才标功能自动验证完成，保留部署/APNs/真实验收边界。

## 计划自查与执行选择

设计覆盖对应：身份Task1/2；任务入口Task3；生命周期/版本Task4/5；周期Task6；确认Task7；用户交互/缓存Task8；交付Task9。群独立策略贯穿所有任务，不提取其业务表或扩大其权限。

推荐 **Native**：由当前代理在一个隔离工作树顺序实施，先P0/P1再P2/P3；这些任务共享协议与生命周期，逐任务换代理会增加上下文成本。用户未选择委派，因此当前不派子代理。

计划待用户评审，确认后按选定方式执行。既有方案“开始实施”的授权持续有效，无需再次确认功能目标；此处审阅的是本轮新增具体接口、预算与执行契约。
