# 俄罗斯方块云端接管实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Subagents require separate authorization.

**Goal:** 用户一键把同一局交给Bot，离开App/锁屏/终止客户端后服务端继续，返回可查询真实进度并收回。

**Architecture:** 本地玩家段与服务端Bot段通过版本化快照交接；SQLite持久化会话、幂等操作和事件，带epoch与租约的独立worker推进确定性引擎。规划器纯计算，LLM可选表达不参与操作循环。

**Tech Stack:** 现有FastAPI/Pydantic/SQLite、Python独立受监督进程、Swift Codable/Networking；不引入Redis或新外部服务。

**Spec:** [接管方案](../../product/2026-10-18-tetris-bot-takeover-proposal.md)、[执行基线 §4、§7、§8](../specs/2026-10-18-game-upgrade-execution-baseline.md)。

**状态（2026-10-19续推）：**C1–C3协议、schema38/API/存储、规划/worker已实现并通过隔离测试；C4生产客户端模型/缓存/接口与页面接入完成，472项Swift测试及App模拟器构建通过，人工V-07未完成。C5隔离launchd首次心跳与SIGKILL自动重启通过；16局及8局10分钟均未达标；4局600秒p95 89.329ms/0错误/0 HTTP失败通过，当前容量固定4局。正式库未迁移、正式服务未部署，手机锁屏代玩尚不能作为已交付。 见[唯一总账](../../tasks/2026-10-18-game-upgrade-progress.md)。

## Global Constraints

- 仅俄罗斯方块、同一局、每用户同时1局Bot托管、不自动下一局、原clientID收回、他端只读；纯本地不依赖网络。
- 只支持固定`vera-tetris-2`，Swift/Python使用相同规则样本；不改变原得分，不读取未公开bag给规划器/模型。
- 每次提交验证userID、version、controlEpoch与有效lease；先持久化再发布，不因锁屏停止服务端。
- 进行中保留，结束7天后清理；后台手机停声、停轮询，返回不补播历史事件。
- 当前迁移源码最高37，计划新文件名v038；真正实施前重查版本/并行工作，若38被占用则顺延并统一更新计划、测试和注册，不能覆盖现有迁移。
- 不占用聊天、定时、持续任务worker；无新第三方依赖、无Web改动、不在本轮执行正式部署。

## Review Focus

- POST已成功但响应丢失，不能本地恢复/重做导致双控（C2幂等与C4离线状态测试）。
- 旧worker计算完后提交到新epoch、租约过期、两个worker争同局（C2/C3真实SQLite竞争测试）。
- 清行阶段收回、交回包丢失和重进App，不能重复清行或旧盘覆盖新盘（C3过渡/C4恢复测试）。
- 服务重启、停机1小时、手机被终止，不能按现实时间补落死亡或停止云端（C3恢复/C5真机测试）。
- 跨用户、非原设备收回、非法快照、旧规则升级，不能泄露或破坏其他局（C1/C2鉴权与协议测试）。

## 文件结构

- Contract：新`docs/contracts/tetris-session-v1.schema.json`、`docs/contracts/tetris-v2-fixtures.json`、`scripts/check_tetris_contract.py`。
- Swift Core：L3 `TetrisGame.swift/TetrisRules.swift`、新`TetrisSession.swift`（DTO与纯交接状态）；Networking新`TetrisSessions.swift`及`VeraBotAPI.swift`声明；Tests新`TetrisParityTests.swift/TetrisSessionTests.swift/TetrisSessionAPITests.swift`。
- Backend纯引擎：新`backend/verabot/services/tetris_sessions/rules.py`、`planner.py`、`contracts.py`、`service.py`、`worker.py`、`__init__.py`、`__main__.py`、`README.md`。
- 数据库：新`backend/verabot/db/tetris_session_store.py`、`db/migrations/v038_tetris_sessions.py`；改`db/migrations/__init__.py`、`db/schema.py`以注册并备份。
- API：新`backend/verabot/api/tetris_session_schemas.py`、`api/routers/tetris_sessions.py`；改`backend/verabot/main.py`仅注册路由，不在API进程启动游戏循环。
- App：新`Features/Playground/TetrisSessionModel.swift`、`TetrisSessionCache.swift`；改`TetrisGameView.swift`、`TetrisCompanionViews.swift`、工程pbxproj。
- Test scripts：`backend/scripts/test/tetris_rules_test.py`、`tetris_session_store_test.py`、`tetris_session_api_test.py`、`tetris_planner_test.py`、`tetris_session_worker_test.py`、`tetris_session_process_test.py`；均临时数据库/假时钟、不调用模型。
- Ops：新`backend/scripts/tetris_worker.sh`（start/stop/status，托管进程+pid/log路径）、`docs/ops/TETRIS_SESSIONS.md`；部署监督配置根据当前宿主现有进程管理方式生成可审查文件，不能凭本机shell存活宣称常驻已交付。

## C1：确定性状态合同与Python同版规则

**Consumes:** L3的状态/动作/时间规则。**Produces:** `rules.restore(snapshot: dict) -> GameState`、`rules.apply(state, action: str) -> list[GameEvent]`、`rules.advance(state, milliseconds: int) -> list[GameEvent]`、`rules.snapshot(state) -> dict`；恢复验证抛`InvalidSnapshot`。和Swift均由同份JSON Schema/fixtures驱动，JSON字段使用camelCase。

- [x] 写JSON Schema，required字段覆盖基线§4状态与§7会话/操作请求；board恰好200个0…7，rotation0…3、rng UInt32非0、计时边界、phase/resumePhase枚举，禁止未知action/字段。语义校验phase/活动四格/重叠/顶部规则在restore执行，不能只靠结构校验。
- [x] 人工核算并保存固定fixtures：七袋前21块、贴墙/地旋转、阻挡、负行顶死、500ms锁定与15次上限、180ms清行中暂停、四行800分、硬降得分、同时间不同advance分块。每项有initial/actions+elapsed/expectedSnapshot/expectedEvents。两端分别读取，不以Python新实现自动生成所有预期。
- [x] Swift `TetrisParityTests` 与 `tetris_rules_test.py`先获得缺失实现红灯，再实现纯Python规则；所有数值按32位掩码、整数ms，禁止调用random.shuffle代替跨端PRNG。不让planner访问rng/bag。
- [x] Run `swift test --package-path frontend/ios/Packages/VeraBotKit --filter TetrisParityTests`、`cd backend && .venv/bin/python scripts/test/tetris_rules_test.py`，预期所有fixture逐字段相同；`python3 scripts/check_tetris_contract.py`校验样本、schema引用与版本（脚本使用已有Pydantic/stdlib，不为此添加依赖）。
- [x] 将ruleVersion和fixtureSHA256写入构建/worker信息；API拒绝不支持的版本422。完成C1才可写持久会话；若规则需改，先升级版本与双端fixture，不继续混用旧局。

## C2：持久归属、幂等API、限额与迁移

**Produces store:** `create_handoff(c,user_id,body,now)`、`apply_command(c,user_id,session_id,body,now)`、`get_operation(c,user_id,request_id)`、`claim(c,owner,now,lease_seconds=10)`、`commit_batch(c,session_id,expected_version,epoch,lease_token,snapshot,events,now)->bool`；事务由调用者持有，所有查改以userID隔离。

**Data:** `tetris_sessions`保存user/bot/originClient、controller/runState/version/epoch、snapshotJSON、pendingOperation、pendingClearController、玩家/Botscore/lines分段与回接基线、workerLeaseToken/expiry、nextDue/updated/ended；`tetris_operations`唯一(user_id,request_id)保存请求规范JSON哈希、结果/pending及sessionID；`tetris_events`唯一(session_id,eventSequence)保存逻辑时间、类型、统计归属和payload。结束清理级联。部分唯一索引限制每user仅一条未结束的bot控制局。

- [x] 在临时SQLite先测：相同requestID相同payload返回同结果；相同ID不同payload409；旧version/epoch失败且不改盘；他用户404；已存在bot托管时另一交出409；worker心跳过期/满16容量503且无控制权变更；手动clearing交出后清行仍计玩家、重复事件不加分、玩家+Bot增量等于总成绩。先红后实现migration/store，迁移执行两次无重复、外键有效、`PRAGMA integrity_check`为ok。
- [x] 迁移前用SQLite backup生成备份（遵循当前schema模块既有模式）；快照/幂等/队列在同一事务提交。为所有API POST设置payload≤64KiB，snapshot非法422；不能将requestID存在但payload不同作为成功重试。数据库事务不包含网络或规划计算。
- [x] 实现基线§7的POST/GET/operations/commands路由与错误码。GET只读不推进游戏；读取版本与快照是同一次一致性读。idempotency结果含已提交version，错误不泄露其他用户快照。命令schema明确handoff/pauseBot/resumeBot/reclaim/end/changeBot；换Bot先验证本用户Bot归属并暂停。
- [x] 增加API TestClient鉴权、非原client reclaim只读拒绝403、规则版本422、队列未持久化不确认交接的测试。新POST成功只表示权威归属已切换且任务持久化，暂不可把空队列/无worker状态假报持续运行。
- [x] 分别Run `cd backend && .venv/bin/python scripts/test/tetris_session_store_test.py`、`cd backend && .venv/bin/python scripts/test/tetris_session_api_test.py`、`cd backend && .venv/bin/python scripts/test/tetris_companion_test.py`，预期退出0。修改此计划的迁移号为实际号，并记录schema版本；不得在正式库试迁移作为测试。

## C3：合法规划与独立持续worker

**Produces:** `planner.plan(public_state: PlannerState, max_nodes=2000, budget_ms=20) -> Plan`，Plan含起始version/epoch、合法动作与每步最早逻辑时间；`worker.tick(owner: str, now) -> TickResult`、`recover_expired(now)`。`PlannerState`只含board/current/公开next与计时，类型不含rng/bag。

- [x] planner先红灯测试：只能输出从当前真实位置可达动作、动作间隔≥40ms、重力/锁定同步模拟；无合法改善时等待/正常结束而非改盘；相同状态固定预算下tie-break稳定；不读取bag。评价优先级按基线§7。验证所有输出用引擎重放，不只看最终格子为空。
- [x] worker测试：两个claim只有一个成功；过期lease不能续租/提交；reclaim pending后普通计划批提交失败；重复batch不重复事件/分数；存储提交失败不发布；重启从最后snapshot/events恢复且停机1小时不补落。先写失败再实现CAS提交和每100ms批推进。
- [x] pending收回：优先冻结普通planner路径；不在clearing时下一安全步交回，clearing时仅transition路径推进剩余清行动画，完成一次清行/生成后立即暂停并切player、epoch+1、废止lease。注入崩溃在pending写入后/清行提交前/交回回复前，恢复均只清一次且归属正确；清行贡献记给该块落定时控制方。
- [x] 独立进程载入env/数据库但不require模型API key；提供`--once`（一次扫描，临时DB测试用）、`--status`（心跳/活跃/等待/失败）、SIGTERM释放可释放租约并持久化安全点。规划放最多2个子进程的有界池，主循环继续处理暂停/续租；仅在新块或路径失效时规划，不每10ms对16局全量搜索。迟到结果校验version/epoch，否则丢弃。
- [x] 规划超预算使用目前最佳合法方案或等待重力，不秘密减速；worker心跳、逻辑推进延迟、拒绝旧lease、pending操作时长均可观测。`tick`不在长DB事务等待模型/进程。清理仅结束>7天的记录，进行中不删。
- [x] 分别Run `cd backend && .venv/bin/python scripts/test/tetris_planner_test.py`、`cd backend && .venv/bin/python scripts/test/tetris_session_worker_test.py`、`cd backend && .venv/bin/python scripts/test/tetris_session_process_test.py`，预期0失败；进程测试启动/停止两个受控测试worker验证租约恢复，不接触现有生产worker。生成可重放日志但不含token或模型密钥。

## C4：iOS交接、断网查询与回接

**Produces networking:** `createTetrisSession(_:)`、`tetrisSession(id:afterVersion:)`、`tetrisOperation(requestID:)`、`commandTetrisSession(id:request:)` async throws；DTO严格解码ruleVersion。

**Produces client:** `TetrisSessionModel.handoff(snapshot:botID:) async`、`reclaim() async`、`pauseBot() async`、`resumeBot() async`、`refresh() async`、`recoverPending() async`。纯状态enum local/pending/botRunning/botPaused/returned/ended/recoveryRequired，UI状态和server controller分开。

- [x] `TetrisSessionTests`先测试交出先冻结local/取消输入；网络超时保持pending；相同request重查成功才botRunning；409拉新状态不覆盖；reclaim返回才替换完整state；换账号后迟到结果丢弃。`TetrisSessionAPITests`用stub验证路径、方法、同requestID重试、403/409/422/503映射。
- [x] `TetrisSessionCache`只存serverURL+userID+clientID作用域的sessionID、requestID、请求哈希/必要snapshot与lastCommittedVersion；原子写文件到Application Support，按当前安装clientID绑定，退出/换账号清理内存任务但不能误删另账号云端局。请求发出前先持久化pending。缓存不存token、普通聊天或长期记忆。
- [x] 首次进入查询pending/云端权威状态再允许本地输入；断网显示恢复确认中/只读缓存，可另开纯本地新局，但不能以旧snapshot覆盖托管局。手动段本地推进不依赖轮询；再交出用同session command handoff与最新snapshot/server version，不能新建第二局。
- [x] 右侧新增交给Bot/我来玩与明确系统状态；服务能力/worker未就绪隐藏或禁用并给原因，不先做假成功按钮。Bot控制锁住掌机方向/A/B，START请求暂停/继续代玩并待服务确认；SELECT和聊聊在请求服务暂停后才开面板；关闭面板保持暂停。
- [x] 前台botRunning每250ms GET、botPaused每2s，后台停止网络观察与声音；返回拉最新状态，去重eventSequence，不补走/补播。收回到原client后同步→3/2/1→本地，收回响应丢失保持pending并查operation，不能因按钮亮起提前恢复。
- [ ] 跑Swift会话/接口/规则/输入/陪玩专项与全量，单次App构建；完成V-07中客户端断网/重复点/重进/多设备场景。C4不引入大模型实时操作调用，也不让安静模式暂停真实云端游戏。

## C5：可运维交付与故障验收

**Produces:** 可审查的worker监督配置、健康检查/启停脚本、迁移备份/恢复与发布步骤、`docs/testing/2026-10-18-tetris-takeover-evidence.md`，明确环境、版本、fixture hash与每项结果。

- [x] 先在测试DB启动API+独立worker，跑16局10分钟；记录每100ms提交循环的实际lateness，p95目标≤100ms，并发收回/暂停不饿死；结果不达标则以实测下调容量并同步基线/配置，不能保持16却虚报通过。监测DB锁等待、进程CPU与队列长度。
- [x] kill worker/重启API/租约到期/失去DB写权限/模型不可用；分别检查恢复点、无双控、无历史快进、无重复结算、可收回；模型失败不能阻塞真实操作。
- [ ] 生成监督配置并先用测试环境验证开机/进程退出后拉起，status能报告心跳。实际正式部署在可审查产物、备份与当前授权条件齐备后执行；禁止未经授权停止现有后端或改生产库。
- [ ] 真机交出后切微信、锁屏、终止App，各等待约2分钟；从服务事件证明持续推进，再进入读到同局并收回；关手机声音不能影响云端。完成V-07每项，失败保留证据，不仅截图显示“正在替你玩”。
- [ ] 回滚时先关闭新接管入口，再停止新规划并保留/暂停现有局供收回；不在旧程序读取前删除新表。数据库回滚按可验证备份恢复方案单独操作。用户验收完成后才标C5完成；部署、Git提交和推送分别记录。

## 自检与交接

方案交出/持续/返回/收回/聊天暂停/换Bot/贡献统计/故障/保留期限均有对应任务。协议与规则都引用唯一基线，所列类型、路径和测试不是已存在能力。真正实施前重查最高迁移号与工作区；下一入口是L3完成后的C1，不能跳过双端规则一致性直接做云端按钮。
