# Bot 漂流瓶 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现“我和 Bot 一起遇见世界”的真实共享文字瓶、私下同行交流与共同回忆。

**Architecture:** SQLite 服务端持有共享瓶子及私有相遇状态，FastAPI 负责鉴权、事务和模型调用；SwiftUI 展示阅读、交流、确认放漂与足迹。模型仅提供私人文字建议，不能发布或修改瓶子流转状态。

**Tech Stack:** 现有 Python/FastAPI/SQLite、Swift 6/SwiftUI、VeraBotKit；不新增第三方依赖。

**Spec:** [已确认设计](../specs/2026-10-19-bot-drift-bottle-design.md)。用户于 2026-10-20 确认整份方案，包括每瓶最多 50 条公开投稿；并非改为无限留言。

状态：已按计划在 `codex/bot-drift-bottle` 隔离工作树实现；自动测试、模拟器构建与临时 UI 全流程、隔离真实模型验证完成，已合入本地 Main，正式库已备份并迁移 v39，Main API 已重启，模拟器已安装；未推送、未安装手机，人工验收待用户。执行记录见[任务记录](../../tasks/2026-10-20-bot-drift-bottle.md)。

## Global Constraints

- 主轴“我和 Bot 一起遇见世界”；不做陌生 Bot 自动互聊、定向私人回信、续缘、笔友、推送或自动长期记忆。
- 每账号同时持有一个外来瓶子，持有 24 小时，服务器请求时回收；新建不占名额。
- 每瓶最多 50 条公开投稿（含原信），第 50 条后归档；撤回不返还累计投稿名额。
- 单次公开正文 1–1000 个 Unicode 码点；反应最多 120 字，主动回复最多 300 字。客户端按 unicodeScalars 计数与服务端一致。
- 发布/捞瓶/生成每账号每分钟分别 5/10/10 次；幂等重放已完成结果不再次计数。
- 模型公共上下文最多 12,000 字、最近 20 轮对话；完整回忆分块处理全部本次对话并保留来源轮次。
- 私人交流不写普通聊天或通用记忆；公共署名仅确认后的 Bot 名称与预设头像，不能暴露主人身份。
- 首次反应最多成功一次；安静模式可跳过；无模型也能读信、手写、放回。
- 所有变更请求按账号和请求 ID 幂等；相同 ID 不同载荷冲突；GET 不发布内容。
- 不使用真实用户数据做演示，不污染正式池；迁移、运行环境和设备安装分别交付，不自动部署。
- 记录持续保留至主动删除；已读去重标记保留至账号删除；不追踪后续新留言。

## Review Focus

- 多设备同时捞瓶/重复点击放漂，结果必须唯一：任务 1、2 的并发和幂等测试。
- 中文、emoji 组合与 1000 字边界，不能客户端接受后服务端拒绝：任务 2、5 的码点边界测试。
- 模型生成中切账号、删除记录或 Bot，不能写回失效对象：任务 4、6 的迟到响应测试。
- 归还或到期后私人交流仍可继续，公开追加必须拒绝：任务 2、4、6 的结束状态权限测试。
- 撤回内容、屏蔽作者和重复查看历史，不可把隐藏原文重新送入模型：任务 3、4、7 的可见性重建测试。

## 文件结构与约定

后端新建 `backend/verabot/services/drift_bottle/`：`contracts.py`（严格请求/返回模型）、`service.py`（操作编排）、`visibility.py`（可见性）、`companion.py`（模型）、`moderation.py`（举报处理）；仓储 `backend/verabot/db/drift_bottle_store.py`。迁移名在开工时依据当时 SCHEMA_VERSION 选择下一个空闲版本，随后在本计划任务 1 记录实际文件，不能覆盖并行工作新增的迁移。

前端模型放 `VeraBotCore/DriftBottle.swift`；请求放 `VeraBotNetworking/DriftBottles.swift`；客户端状态与草稿放 `VeraBotData/DriftBottleModel.swift`、`DriftBottleDraftCache.swift`；页面位于 `VeraBot/Features/Playground/DriftBottle/`。上述包路径均以 `frontend/ios/Packages/VeraBotKit/Sources/` 为根。

后端测试依现有 unittest 脚本格式放 `backend/scripts/test/drift_bottle_*_test.py`，前端测试放 `frontend/ios/Packages/VeraBotKit/Tests/VeraBotKitTests/DriftBottle*Tests.swift`。测试使用临时数据库、伪时钟、模型替身和两个账号，不连接正式数据库。

所有路由前缀 `/api/games/drift-bottle`。Pydantic 定义以下共享对象并由 Swift Codable 镜像：`PublicContribution`、`EncounterDetail`、`RecordDetail`、`BottleState`、`OperationResult`、`MemoryCard`。公共 DTO 用字段白名单独立构造，不直接序列化数据库行。

仓储函数统一接收 `sqlite3.Connection`，时间为 UTC Unix 秒；路由经 service 取得连接，持有模型调用期间不持有 SQLite 写事务。业务异常 `BottleError(status:int, code:str, message:str)` 映射为 HTTP 错误。

---

### Task 1: 真实数据与事务基础

**Files:** 新建仓储、contracts.py、下一空闲迁移；修改 `backend/verabot/db/migrations/__init__.py`；测试 `backend/scripts/test/drift_bottle_store_test.py`。

**Interfaces:** 仓储提供 `create_bottle(c,user_id,body,now)->dict`、`draw(c,user_id,body,now)->dict`、`release(c,user_id,encounter_id,body,now)->dict`、`operation(c,user_id,request_id)->dict`。请求携带 request_id、bot_id；release 额外含 lease_token、expected_version、可空 contribution。幂等事务先查询已有结果再扣额度/写状态。

- [ ] 写失败测试 `test_concurrent_draw_has_one_winner`、`test_same_account_resumes_one_encounter`、`test_replay_release_adds_one_contribution`、`test_request_id_payload_conflict`：两个连接竞争一个瓶子只一个持有；同账号恢复同 encounter；重复放漂公开条数只加 1；不同载荷冲突。
- [ ] 在 backend 目录运行 `uv run python scripts/test/drift_bottle_store_test.py`，确认因缺少新仓储失败。
- [ ] 实现规范中的 Bottle/Contribution/Encounter/Turn/Memory/Operation/Block/Report/AdminAction 与已读/私人隐藏标记；使用条件写、事务及唯一约束。Bot 删除外键设空保留快照，账号删除通过任务 3 的清理入口处理公开文字。
- [ ] 补齐迁移重复执行、旧表数据不变、外键检查测试，并运行同脚本直至成功。
- [ ] 将本任务实际文件、迁移号和验证结果记录到 `docs/tasks/2026-10-20-bot-drift-bottle.md`，仅提交本任务文件。

### Task 2: 流转规则与基础 API

**Files:** 新建 service.py、`backend/verabot/api/routers/drift_bottle.py`；修改 `backend/verabot/main.py` 注册 router；测试 `drift_bottle_api_test.py`、`drift_bottle_rules_test.py`。

**Interfaces:** `state(user_id,now)->BottleState`、`get_encounter(user_id,id,cursor)->EncounterDetail`、`records(user_id,bot_id,cursor)->dict`；create/draw/release 接任务 1。GET state、POST bottles/encounters、GET encounters/{id}、POST encounters/{id}/release、GET records/{id} 与 operations/{request_id} 按设计实现。

- [ ] 写失败测试 `test_expiry_at_86400_releases_without_losing_record`、`test_fiftieth_contribution_archives`、`test_empty_pool_is_not_fake_message`、`test_own_seen_blocked_excluded`、`test_authorization_hides_identity`。断言 86399 秒仍有效、86400 秒到期，50 条后不再匹配；越权对象响应不泄露存在性。
- [ ] 运行 `uv run python scripts/test/drift_bottle_rules_test.py` 和 `uv run python scripts/test/drift_bottle_api_test.py`，确认缺失规则失败。
- [ ] 实现公开字段白名单、每页 20 条游标（最大 50）、已读上限、50 条累计封顶、24 小时回收、每账号额度、同账号恢复和新建独立。到期追加拒绝，记录读取允许；直接放回不添加站次或署名。
- [ ] 测试 1000/1001 码点、emoji、同 ID 重试不多扣额度、分页不展示相遇后新增留言；运行两脚本通过。
- [ ] 更新任务记录，提交本任务文件。

### Task 3: 可见性、撤回、管理与删除

**Files:** 新建 visibility.py、moderation.py、`backend/scripts/drift_bottle_admin.py`；调整仓储；检查并接入账号删除实际入口；测试 `drift_bottle_visibility_test.py`。

**Interfaces:** `visible_contributions(c,user_id,encounter_id,cursor)->list[dict]` 为页面和模型共同入口；`withdraw(c,user_id,contribution_id,request_id,now)->dict`、`report(c,user_id,body,now)->dict`、`block(c,user_id,body,now)->dict`、`delete_record(c,user_id,id,request_id,now)->dict`、`cleanup_user(c,user_id,now)->None`。管理员 `moderate(c,admin_id,report_id,action,reason,now)->dict` 只接受 keep/hide/restore。

- [ ] 写失败测试：撤回留占位且不影响他人文字；举报只对本人即时隐藏、管理员隐藏才全局生效；屏蔽后排除包含该作者的瓶子；删除记录保留已读去重；删账号撤回投稿且删除所有私有数据；删 Bot 保留快照但不能再生成。
- [ ] 运行 `uv run python scripts/test/drift_bottle_visibility_test.py`，确认失败。
- [ ] 实现服务端与路由、账号清理；管理员工具需显式受限管理员配置和身份校验，不允许普通用户传参伪造管理员；处理动作写审计。运行工具只针对显式数据库路径。
- [ ] 增加管理员鉴权、ID 猜测、撤回后无有效文字停止匹配、恢复已满瓶不重新开放等断言；运行脚本通过。
- [ ] 提交任务代码及 `docs/tasks/2026-10-20-bot-drift-bottle-admin.md` 操作说明。

### Task 4: 同行交流、草稿与共同回忆

**Files:** 新建 companion.py；扩展 contracts/service/router/store；测试 `drift_bottle_companion_test.py`。

**Interfaces:** `async generate_turn(user_id,encounter_id,body)->OperationResult`、`async suggest_draft(user_id,body)->OperationResult`、`async generate_memory(user_id,encounter_id,request_id)->OperationResult`；模型接口注入替身。turn kind 为 opening/chat/draft；输入消息只由服务器加载已保存历史和可见投稿，不接受客户端冒充 assistant 历史。

- [ ] 写失败测试 `test_opening_succeeds_once`、`test_quiet_mode_does_not_generate`、`test_private_chat_never_publishes`、`test_no_chat_memory_is_factual`、`test_deleted_target_rejects_late_completion`、`test_expired_encounter_allows_chat_not_publication`。
- [ ] 运行 `uv run python scripts/test/drift_bottle_companion_test.py`，确认失败。
- [ ] 实现现有 llm 的无工具调用；窗口最近 20 轮、公开内容 12000 字，短反应 120/回复 300 字。结构化输出长度和类型校验失败标记可重试，不伪造成功。
- [ ] 实现事件键去重、同相遇持久化生成占用、超时可恢复、写回前复核；不在模型等待期间持写锁。首次 opening 只接受尚在阅读的当前相遇；已结束相遇可主动 chat，不自动 opening。
- [ ] 实现 memory 对全部对话按最多 12000 字分块（超长单条拆片），合并时验证来源 turn ID 存在；没有对话走事实回忆。恢复、重试与人工编辑不重复覆盖已编辑内容；记录源版本，后续聊天不自动重写卡片。
- [ ] 测试隐藏文字不进入新调用、长对话早期事实仍可追溯、失败不锁住放漂、模型注入要求不能发布/调用工具；运行脚本通过后提交本任务。

### Task 5: Swift 模型、网络与账号状态

**Files:** 新建 Core/DriftBottle.swift、Networking/DriftBottles.swift、Data/DriftBottleModel.swift、Data/DriftBottleDraftCache.swift；修改 Networking/VeraBotAPI.swift；新建 DriftBottleAPITests.swift、DriftBottleModelTests.swift。

**Interfaces:** `DriftBottleAPI` 方法在 VeraBotAPI 上声明并在 APIClient 实现，覆盖所有设计 API，`DriftBottleModel` 为 @MainActor Observable。方法 `load() async`、`draw(botID:) async`、`release(contribution:) async`、`send(message:) async`、`reset(accountID:)`。共享类型引用 Core，Data 不依赖 App UI。

- [ ] 写失败测试：`any VeraBotAPI` 实际路径/方法/请求 ID 正确；重复 release 用相同 ID；unknown operation 先查询不重发；账号切换迟到结果丢弃；离线缓存没有他人正文。
- [ ] 在包目录运行 `swift test --filter DriftBottle`，确认缺少模型/接口导致失败。
- [ ] 实现 Codable 与 transport、服务端错误映射；私有草稿按账号和相遇分区，草稿含生成来源标记；他人正文仅内存保存，断网显示待联网而非旧全文。
- [ ] 测试 1000 码点与组合 emoji 客户端校验一致；重启恢复当前 encounter、到期继续私聊但禁止公开提交、生成失败仍能手写放回；运行筛选测试通过。
- [ ] 更新任务记录并提交本任务文件。

### Task 6: 页面与公开确认

**Files:** 新建 `frontend/ios/VeraBot/Features/Playground/DriftBottle/` 下 HomeView.swift、ReadingView.swift、ComposerView.swift、RecordsView.swift、MemoryView.swift；修改 WorldViews.swift、App/AppState.swift 的账号生命周期接线（不扩大普通聊天职责）；新增 Core/DriftBottlePresentation.swift 及 DriftBottlePresentationTests.swift。

**Interfaces:** 页面依赖一个 DriftBottleModel；`DriftBottlePresentation.canPublish(now:)`、`publicPreview(text:authorship:botName:)` 生成确定的确认状态；草稿由 Data 保管。已开始相遇使用锁定的 botID，首页换 Bot 仅影响下一次。

- [ ] 写失败测试：未确认不能提交、生成稿不自动标亲笔、回忆无聊天不虚构分享、无 Bot/旅行中 Bot/已删除 Bot 对应入口状态；运行 `swift test --filter DriftBottlePresentation` 确认失败。
- [ ] 实现确定的展示决策并使上述测试通过。
- [ ] 实现 5 个页面及导航；复用主题头像和现有提示，公开全文预览与私人对话分开，加入安静读信、撤回/举报/屏蔽、记录/卡片分别删除、Bot 筛选。网络操作时防双击，失败保留编辑文本。
- [ ] 使用当前项目构建方式在 Intel Mac 可用的 iOS Simulator 目标构建；若运行 XcodeGen，确认项目本来要求生成再执行，不添加依赖。验证入口、阅读、对话、放漂和足迹的完整流程，留本次截图证据。
- [ ] 更新 FEATURES、任务记录、STATUS、CHANGELOG，准确写构建和运行证据，提交本任务。

### Task 7: 跨账号与故障验收

**Files:** 新建 `backend/scripts/test/drift_bottle_acceptance_test.py`、`docs/tasks/2026-10-20-bot-drift-bottle-acceptance.md`；必要时修复前述模块，不新增功能。

**Interfaces:** 使用已完成的公开 API 与 Swift Model；测试模型替身，不通过内部写数据库跳过确认与权限。

- [ ] 建立两个账号、各一位 Bot 的隔离场景，断言 A 新建→B 捞取→私聊→公开确认留言→放漂，A 看不到 B 私聊；第三个测试账号读取沿途文字以避开原作者/已读排除规则。
- [ ] 运行 `uv run python scripts/test/drift_bottle_acceptance_test.py`；覆盖 49→50 归档、24 小时边界、屏蔽/撤回重读、服务器重启/中断后操作查询、并发拿瓶和多设备恢复。
- [ ] 运行所有 `drift_bottle_*_test.py`（逐脚本报告结果）和完整 Swift Package 测试；执行受影响的既有账号、Bot 删除、普通聊天与游戏测试，遇到无关旧失败单独记录，不冒充全绿。
- [ ] 用两个不同性格 Bot 的独立测试瓶进行真实模型体验核对：不同关注点、不过度追问、无凭空共同往事、安静模式、无回信也能结束。未接真实模型则明确待验，不以替身结果代替。
- [ ] 记录自动测试、模拟器、真实模型、真机人工验收的分开状态；准备可手测环境后停下，正式数据迁移/服务替换/设备安装按用户届时指示，不自动推送。
- [ ] 请求整分支审查并处理可证实问题；只提交本功能文件，不把未测试的部署视为完成。

## 执行前准备与完成条件

执行方式由用户选择；用户未选择前不启动产品实现或派发实现子代理。实施时先读 using-git-worktrees、executing-plans 或 subagent-driven-development 的对应工作流，使用独立工作树保护现有修改。所有提交仅在功能分支且为本功能内容，不自动合并 main 或推送。

计划覆盖确认：设计第 2–4 节由任务 1/2/5/6 覆盖，第 5 节由任务 3/6，第 6 节由任务 1–5，第 7–8 节由任务 7。公开池真实、私人交流边界和 Bot 体验三者均需有证据；只做 UI 演示不算实现完成。未完项在任务账中明确列出，不用构建成功代替人工接受。
