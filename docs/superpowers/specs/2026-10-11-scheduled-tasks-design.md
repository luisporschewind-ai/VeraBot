# 服务端定时任务第一版方案

日期：2026-10-11。状态：设计草案，待审阅；不代表实现或验收完成。

## 1. 目标与范围

用户指定 Bot、工作内容和时间，服务端在 App 未打开时执行，保存结果、用量和执行历史。成功结果出现在负责 Bot 的一对一对话，并进入通知中心。第一版以服务端 API 和后台执行闭环为交付重点。

支持一次性、每天、工作日、每周指定日；支持创建、查看、修改、暂停、恢复、删除、手动执行一次、查看执行历史。执行内容限于生成文本和服务端明确允许的只读查询，复用当前 Bot 的身份、模型与权限。

第一版不包含 iOS 任务中心、聊天创建任务工具、群任务、多 Bot 委派、长期多步骤续跑、附件输入、外部写入、自动创建其他任务和 APNs 真推送。没有接入的数据源不能被当作可用能力，例如资讯任务必须有实际获准的数据来源。

成功标准：一个任务能在指定时间生成且只生成一条执行记录，由后台进程领取，完成后留下可追溯结果；服务重启、重复扫描、权限撤回和用户暂停都不会导致盲目重复执行。

## 2. 当前基础与选择

现有 `services/reminders/scheduler.py` 每 30 秒处理提醒；`main.py` 随 FastAPI 启动该循环。已有 RRULE、时区、通知收件箱、Bot 工具权限、模型调用及用量记录。现有 `run_chat` 会写入用户消息，`run_once` 是被委派 Bot 的独立执行，两者不能直接作为定时任务入口。

选用 SQLite 持久队列 + 独立后台进程。第一版不增加 cron、Redis、Celery 或 APScheduler 依赖。系统 cron 可用于运维唤醒，但每个用户任务不写成系统 cron 项。

运行结构：

```text
API：管理任务定义，查看执行记录
                 ↓
SQLite：scheduled_tasks / scheduled_task_runs / scheduled_task_attempts
                 ↑
后台进程：Scheduler 生成到期执行记录 → Worker 领取并执行
                                           ↓
                               保存结果 + Bot 消息 + 站内通知
```

后台进程入口拟为 `python -m verabot.services.scheduled_tasks`。Scheduler 与 Worker 是两个独立异步循环，共用该进程；API 不启动这些循环。第一版部署仅启动一个该后台进程，由 launchd 或部署平台进程管理器自动重启。事务领取与租约提供重复领取保护，但这版不承诺多机队列支持。API 和后台进程必须使用同一数据库路径；部署迁移先完成，再启动后台进程。

## 3. 数据模型

`scheduled_tasks`：id、user_id、bot_id、title、instruction、state、timezone、start_at_utc、rrule、next_run_at_utc、misfire_policy、schedule_revision、version、created_at、updated_at、deleted_at。

- state：active / paused / completed / deleted。
- RRULE 为空表示一次性；第一版 API 仅接受上述预设排程，复用当前校验及计算能力。
- misfire_policy：skip（默认）或 latest（只补最近一次）。
- timezone 为 IANA 时区；绝对时间以 UTC 保存。排程不随手机时区变化。
- schedule_revision 在修改排程时递增；version 为全部用户修改的乐观锁。
- 删除使用软删除，历史保留。关联 Bot 删除时暂停任务并标注原因，不移交其他 Bot。

`scheduled_task_runs`：id、task_id、user_id、bot_id、trigger、scheduled_for_utc、schedule_revision、idempotency_key、state、task_snapshot_json、available_at、lease_owner、lease_token、lease_expires_at、attempt_count、started_at、finished_at、result_text、error_code、error_summary、message_id、notification_id。

- trigger：scheduled / manual。
- state：queued / running / retry_wait / succeeded / failed / interrupted / skipped / cancelled。
- 定时触发唯一约束为 `(task_id, schedule_revision, scheduled_for_utc)`；手动触发使用用户、任务和 Idempotency-Key 去重。
- snapshot 保存执行时的标题、指令、排程版本和工具授权上限；执行时仍须检查最新 Bot 和服务权限，不能使用快照恢复已撤回的权限。
- 同一任务至多存在一条 queued / running / retry_wait 执行，数据库约束兜底。

`scheduled_task_attempts`：id、run_id、attempt_number、started_at、finished_at、state、usage_json、error_code、trace_summary_json。逐次保留模型尝试及用量；日志和 trace 不保存凭据或外部资料全文。

具体迁移版本由实施时主线最新版本确定，不按旧文档里的 schema 数字预定。新表迁移必须幂等；不在方案阶段升级正式数据库。

## 4. 调度与时间语义

Scheduler 每 30 秒扫描 next_run_at_utc <= now 的 active 任务。触发目标是分钟级，不承诺精确秒级开始；队列繁忙时允许延迟，记录计划时间和实际开始时间。

每个任务在短 `BEGIN IMMEDIATE` 事务内复核状态、版本和已有执行，插入执行记录并推进 next_run_at；网络调用不放入数据库事务。重复扫描不能重复入队。

- 正常到期：10 分钟宽限内入队。
- 超过宽限：skip 记录跳过并推进未来；latest 只生成最近一次执行，其余积压记录汇总。补跑年龄上限 24 小时，超过也跳过。
- 一次性任务入队后 next_run_at 为空；本次执行终结后任务变为 completed，失败记录仍可手动重跑。
- 同任务已有未终结执行时，周期到点记录 skipped（previous_run_active）并推进未来，不积压更多轮。
- 恢复暂停任务从当前时间计算下一次，不自动补暂停期间的工作。
- 修改排程取消未开始的旧执行并从当前时间重算下一次；已运行执行继续使用原快照。修改指令取消未开始的旧执行，后续使用新指令，不重新制造过去的计划时刻。
- 夏令时不存在的本地时刻跳过该次；重复的本地时刻仅执行第一次。需在现有 RRULE 计算外验证真实时区转换，不能假设库已满足此规则。

## 5. 领取、执行与授权

Worker 第一版串行执行，每秒检查可领取记录。在立即事务中原子领取 queued / 到期 retry_wait，设置 running 和租约 token；每 15 秒续租，租约 90 秒。完成提交必须仍持有相同 token，过期 worker 不得写回。

新增独立 `run_scheduled` 入口。共享现有模型客户端、system prompt 和统一工具调度；不伪造用户消息，不读取执行时整个聊天历史。输入为任务指令、计划时间、实际时间以及当前 Bot 权限下检索到的相关记忆。第一版禁止写记忆，不触发用户消息提取。

工具策略是「任务保存的授权上限 ∩ 当前 Bot 权限 ∩ 后台只读白名单」，在 schema 暴露和实际 dispatch 两处校验。允许名单显式列举；MCP 必须已授权、工具定义未变更且策略明确标记只读，未知风险默认拒绝。禁止提醒写入、记忆写入、ask_bot、外部写入和任务自修改。

执行前检查账号有效性、Bot 存在、任务状态、工具连接和每日额度。任务读取、结果及关联消息均按 user_id 隔离；API 越权返回 404。外部内容保持不可信，不能修改任务指令或权限。

默认单次执行总超时 180 秒，最多 4 轮工具交互、8 次工具调用，每次尝试输出上限 2048 token。复用账号每日用量额度，定时用量单独标记 scheduled_task，并在执行前和每轮模型调用前检查；阈值是软限额，已发出的模型请求可能超过余额。第一版不宣称可精确控制金额，也不改变普通聊天用量计算。

用户暂停或删除时取消尚未开始的执行，并向正在执行的 Worker 发出数据库取消标记。Worker 在每轮和每次工具调用前检查，尽力取消当前模型请求；暂停响应说明 running 取消可能仍在处理中。已经发生的模型费用不能撤销。

## 6. 失败、重试与恢复

明确的临时失败可在 30 秒、120 秒后重试，总共至多 3 次尝试，每次实际消耗都记账。鉴权失败、权限撤回、额度不足、无效参数、未知异常及执行总超时不自动重试；给出具体可操作原因。

任务指令涉及不可用能力时失败，不输出假装完成的答复。模型返回普通文本也不自动证明任务完成：返回结构区分成功、受限与失败；遇到必要工具错误不得标为 succeeded。

租约过期的 running 标为 interrupted；启动恢复也只处理已过期租约，不把所有 running 一律退回 queued。第一版中断任务不自动重跑，用户可通过手动执行再次开始。模型请求是否已计费但未返回用量属于未知，记录 usage_unknown，不填为零或估算成确定用量。

排程入队至多一次不等于模型请求严格执行一次；重试可能产生额外模型请求和费用。服务端保证结果消息及通知去重，第一版通过只读范围限制重复操作影响。

## 7. 结果投递

成功结果先保存在 run 中，再以任务 id / run id 来源标记写入 Bot 对话，复用站内 `bot_message` 通知。消息必须能够区分定时输出与普通聊天输出，消息读取和历史拼装需兼容该来源字段。

结果、消息及通知收件箱创建尽量使用同一数据库事务；消息使用 run 唯一关联，通知使用 `scheduled_task:{run_id}` dedupe_key。若已有存储接口无法共用事务，则采用持久待投递标记和重试，投递重试不能再次执行模型。

失败、中断和权限问题保存到历史，并发送去重的站内通知；重复失败通知遵守现有免打扰与限流。通知被抑制不改变执行结果。暂停/删除取消的任务不发完成提醒。

APNs 未接入时，App 关闭期间仍可执行，但完成结果要在再次打开、刷新对话或通知中心后看到；不能用本地定时通知宣称动态任务已经完成。

## 8. API 契约

统一挂在 `/api/scheduled-tasks`，沿用当前认证。列表分页默认 20、上限 100；执行历史以 run id 游标分页。

| 接口 | 行为 |
| --- | --- |
| POST /api/scheduled-tasks | 创建任务，校验 Bot、指令、排程与时区，返回下次时间；必须 Idempotency-Key |
| GET /api/scheduled-tasks | 按 Bot、状态筛选列表 |
| GET /api/scheduled-tasks/{id} | 任务详情和最近执行摘要 |
| PATCH /api/scheduled-tasks/{id} | 修改，必须 expected_version；冲突 409 |
| POST /api/scheduled-tasks/{id}/pause | 暂停及取消未开始执行，必须 expected_version |
| POST /api/scheduled-tasks/{id}/resume | 恢复未来排程，必须 expected_version |
| DELETE /api/scheduled-tasks/{id} | 软删除，必须 expected_version，客户端应有删除确认 |
| POST /api/scheduled-tasks/{id}/run | 手动执行，必须 Idempotency-Key；不改变下一次排程 |
| GET /api/scheduled-tasks/{id}/runs | 查看每次执行状态、结果、原因和用量 |
| GET /api/scheduled-tasks/{id}/runs/{run_id} | 单次执行及尝试详情 |

手动执行允许 active / paused / completed，拒绝 deleted；同任务已有未终结执行返回 409。暂停状态下手动运行不恢复排程，但需显式区分用户手动授权与计划触发。所有写接口先校验用户身份及对象归属。

错误包含稳定 code 与简短中文说明，例如 task_busy、version_conflict、bot_deleted、permission_revoked、quota_exceeded、run_interrupted。技术堆栈和连接细节放调试记录。

## 9. 实施顺序与验收

1. 数据迁移、store、任务 service、CRUD 与时间计算。
2. Scheduler 入队、唯一约束、错过规则与排程修改。
3. Worker、租约、独立模型执行、工具策略与用量。
4. 结果对话、站内通知、投递去重和后台进程运行说明。
5. 离线契约测试与本地端到端验证；真实模型冒烟验证单独说明消耗与授权，不作为离线测试默认行为。

验收必须覆盖：一次性执行、重复规则、时区与夏令时、重复 tick、两个竞争领取者、同任务不重叠、暂停/删除竞态、修改后旧排程不执行、默认跳过与只补一次、重试上限、额度检查、Bot 删除、权限撤回、恶意工具调用、租约过期和旧 worker 写回被拒绝、结果投递重试不再次调用模型、用户隔离、API 幂等与版本冲突。

端到端用假时钟和假模型验证「创建 → 到点 → 后台执行 → run 成功 → 一条 Bot 消息 → 一条站内通知」；独立后台子进程重启用例验证 interrupted 记录保留且模型不自动重跑。第一版不以编译成功替代这些行为验证。

## 10. 交付边界

第一版交付服务端源码、迁移、API 文档、后台进程运行说明及离线测试证据。用户可先通过接口体验闭环；iOS 任务入口和聊天任务卡片在后续单独设计。

本草案基于当前仓库读取结果，未变更业务代码、运行正式迁移、部署常驻进程、调用真实模型、提交或推送 Git。设计审阅后再形成可执行实施计划。
