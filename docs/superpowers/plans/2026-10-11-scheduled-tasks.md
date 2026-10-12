# 服务端定时任务第一版 Implementation Plan

2026-10-12 状态：实现已保存并整合到本地 main，当前验证与设备边界见 [Main 集成交付](../../testing/2026-10-12-main-integration.md)。下方为原实施步骤，原先不提交/合并限制已由本轮用户明确授权覆盖；未触发的真实服务与设备交互不标记通过。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现用户指定 Bot 的服务端定时执行闭环，包含任务 API、持久队列、独立后台进程、用量与结果投递。

**Architecture:** SQLite 保存任务、执行和尝试记录；独立进程内 Scheduler 入队、串行 Worker 执行，API 不启动任务循环。新增定时执行入口，复用模型、权限和通知基础，不模拟用户聊天。

**Tech Stack:** Python 3.11+、FastAPI、SQLite、asyncio、python-dateutil；无新增第三方依赖。

**Spec:** [已确认设计](../specs/2026-10-11-scheduled-tasks-design.md)。

## Global Constraints

- Scheduler 每 30 秒扫描；Worker 空闲每秒扫描；租约 90 秒、每 15 秒续租。
- 到期宽限 10 分钟；错过默认 skip，latest 最多补最近一次且年龄不超过 24 小时。
- 单次执行总超时 180 秒，最多 4 轮工具交互、8 次工具调用，每次尝试输出上限 2048 token。
- 重试间隔 30 秒、120 秒，总计最多 3 次尝试；中断不自动重跑。
- 只读工具名单在实际调用处强制校验；无委派、附件、记忆写入、提醒写入或任务自修改。
- 全部对象访问按 user_id 隔离；排程以 IANA 时区计算、UTC 保存。
- 本次不做 iOS 任务页面、聊天创建卡片、群任务、外部写入或 APNs。
- 不改正式数据库，不调用真实提供者，不推送或合并；保留现有未提交改动。实施使用隔离 worktree，执行前重查 AGENTS 和 Git 状态。
- 每项测试先失败再实现；每项完成后记录证据。提交仅在用户授权提交时执行，不从技能的建议推导提交权限。

## Review Focus

- Idempotency-Key 被复用于不同请求：返回 409，不能悄悄复用旧结果（Task 2）。
- 时钟向后或夏令时切换：已触发时刻不重复，缺失时刻跳过、重复时刻只执行一次（Task 3）。
- 暂停后用户手动执行：允许独立一次；不恢复周期，不被普通 paused 检查误取消（Task 4）。
- 写工具被伪装成只读或未知风险：服务端拒绝实际调用，不能仅凭模型或工具描述放行（Task 5）。
- 清空对话或删除结果消息后投递重试：历史保留，不重新生成模型结果、不恢复已删除消息（Task 6）。

## 文件边界

新增 `backend/verabot/services/scheduled_tasks/`：`contracts.py`（执行结果类型）、`clock.py`（UTC 时钟）、`schedule.py`（时间规则）、`service.py`（用户操作）、`scheduler.py`（入队）、`worker.py`（领取与恢复）、`executor.py`（模型循环）、`policy.py`（后台权限）、`delivery.py`（结果投递）、`__main__.py`（进程生命周期）、`__init__.py`（公共导出）。

新增 `backend/verabot/db/scheduled_task_store.py`：任务 SQL；`scheduled_run_store.py`：执行、尝试和租约 SQL。集成迁移为 `v023_scheduled_tasks.py`，保留主线 v21 会话同步与 v22 群附件。

新增 `backend/verabot/api/scheduled_task_schemas.py`、`api/routers/scheduled_tasks.py`；修改 `main.py` 仅注册 API。模型客户端 `services/llm.py`、权限上下文 `tools/registry.py`、统一工具入口 `agents/tool_router.py` 仅做此次所需最小扩展。

修改消息数据层与消息 API 增加可选任务来源，不改普通聊天显示逻辑；消息表来源采用新列 `source_kind` / `source_id`，普通消息默认空。后台消息显示正文以「定时任务：标题」开头，现有客户端即可辨认，API 额外返回结构化来源。

测试使用 `unittest`，临时 DB 环境在 import 前设置，运行命令均从 `backend` 目录执行。拆成 `scheduled_task_store_test.py`、`scheduled_task_api_test.py`、`scheduled_task_scheduler_test.py`、`scheduled_task_worker_test.py`、`scheduled_task_executor_test.py`、`scheduled_task_delivery_test.py`、`scheduled_task_process_test.py`。

### Task 1：迁移与持久记录

**Files:** 新增迁移、两个 store、contracts.py、clock.py；修改 migrations/__init__.py；测试 scheduled_task_store_test.py。

**Interfaces:** `ExecutionResult` dataclass 提供 state、text、error_code、error_summary、usage、usage_unknown、trace_summary；`clock.now() -> datetime` 返回 aware UTC。Store 方法接收显式连接，不自行提交，租户查询显式 user_id。

- [ ] 写 `test_migration_idempotent`：从 v20 迁移两次，3 张任务表与消息来源列存在、版本只升级一次、已有群消息不变。
- [ ] 写 `test_unique_occurrence_and_one_active_run`：同排程时刻第二条执行触发唯一约束；同任务第二条未终结执行也被拒绝。
- [ ] 运行 `python -m unittest discover -s scripts/test -p scheduled_task_store_test.py -v`，确认目标断言因缺失实现失败。
- [ ] 实现设计中的列、索引和状态 CHECK；补充 run.cancel_requested、task.pause_reason、request_hash、attempts.usage_unknown；bot_id 使用 ON DELETE SET NULL，任务与执行保留归属快照。
- [ ] 实现 `task_store.fetch(c, user_id, task_id) -> dict | None`、`run_store.fetch(c, user_id, task_id, run_id) -> dict | None`；实现任务、执行、尝试的事务内写入基础方法。
- [ ] 重跑测试，确认幂等迁移、用户隔离和约束通过；记录结果。

### Task 2：用户操作与 API

**Files:** service.py、schedule.py、API schema、router、main.py；测试 scheduled_task_api_test.py。

**Interfaces:** `service.create(user_id: int, payload: dict, idempotency_key: str) -> dict`；`update(user_id, task_id, payload, expected_version) -> dict`；`transition(user_id, task_id, action, expected_version) -> dict`；`run_now(user_id, task_id, idempotency_key) -> dict`。统一 `TaskError(code, message, status)` 转为 HTTP 错误。

- [ ] 写 API 测试：创建返回 201、有效 next_run_at；重复同 key 同 payload 返回原对象；不同 payload 409；其他用户所有详情与写操作 404；旧 version 409。
- [ ] 写边界测试：title 长度 1–200、instruction 长度 1–8000、幂等 key 长度 1–128；无效时区、无 offset 时间、过去开始时间、未知排程和跨用户 Bot 均拒绝。列表 limit 1–100、默认 20。
- [ ] 运行 `python -m unittest discover -s scripts/test -p scheduled_task_api_test.py -v`，确认失败。
- [ ] 实现所有 spec §8 接口；排程输入固定为 start_at（含 offset）、timezone、repeat（once/daily/weekdays/weekly）、weekdays（weekly 用 0–6 不重复列表）；服务端生成 RRULE，客户端不能提交自由 RRULE。
- [ ] 实现立即事务内版本检查、幂等 request hash、取消未开始旧执行、运行中 cancel_requested；详情返回列表与运行历史游标，run_now 不修改 next_run_at。
- [ ] 重跑 API 测试，补 completed 手动重跑、deleted 拒绝、paused 手动运行和 busy 409，记录结果。

### Task 3：Scheduler 与时间规则

**Files:** schedule.py、scheduler.py、两个 store；测试 scheduled_task_scheduler_test.py。

**Interfaces:** `schedule.next_after(task: dict, after: datetime) -> datetime | None`；`scheduler.tick(now: datetime | None = None) -> dict`，返回 enqueued/skipped/completed 计数。

- [ ] 写正常、10 分钟边界、24 小时补跑边界、停机三天每日任务、重复 tick、同任务忙碌与一次性测试。相同计划时刻断言 run 数量为 1；latest 断言只补 1 次且 next_run_at 在未来。
- [ ] 写 America/New_York 春季 02:30 不存在时跳过、秋季 01:30 只入队一次；时钟回拨后原时刻不重复执行；恢复暂停不补停期间任务。
- [ ] 运行 `python -m unittest discover -s scripts/test -p scheduled_task_scheduler_test.py -v`，确认失败。
- [ ] 实现时区往返转换验证、预设重复、宽限 `[0,600]` 秒正常触发、补跑年龄 `<=86400` 秒；短立即事务内复核及入队、推进。跳过积压只记汇总，不逐条无限生成历史。
- [ ] 实现修改排程版本隔离、重复任务忙碌跳过和下一次仍为未来；写两线程竞争 tick 测试，断言仍只生成一次。
- [ ] 重跑 Scheduler 测试，记录结果。

### Task 4：Worker、租约与重试

**Files:** worker.py、run store、contracts.py；测试 scheduled_task_worker_test.py。

**Interfaces:** `worker.process_one(owner: str) -> bool`；`worker.recover_expired(now: datetime | None = None) -> int`；`run_store.claim_next(c, owner, now) -> dict | None`；`renew(c, run_id, lease_token, now) -> bool`；`finish(c, run_id, lease_token, result: ExecutionResult, now) -> bool`。

- [ ] 写两个竞争领取者仅一人成功、90 秒租约过期、旧 token finish 被拒绝、15 秒续租、启动不恢复尚未过期租约的测试。
- [ ] 写失败重试 30/120 秒且总 3 次，非暂时失败不重试；暂停 queued 取消、running 尽力取消；paused 的手动执行允许且不恢复周期。
- [ ] 运行 `python -m unittest discover -s scripts/test -p scheduled_task_worker_test.py -v`，确认失败。
- [ ] 实现串行领取、续租和 180 秒总超时；恢复过期 running 为 interrupted，保留 attempt 与 usage_unknown；禁止自动 queued 重跑。
- [ ] 实现 attempt 原子开始/结束、可重试错误枚举（明确连接失败/限流/提供者 5xx）；未知异常、鉴权、权限、额度与总超时不重试。区分 manual 与 scheduled 的 paused 检查。
- [ ] 重跑 Worker 测试，记录结果。

### Task 5：独立 Bot 执行与工具权限

**Files:** executor.py、policy.py、必要的 tools/registry.py、agents/tool_router.py、services/llm.py 最小扩展；测试 scheduled_task_executor_test.py。

**Interfaces:** `executor.run_scheduled(run: dict) -> ExecutionResult`；`policy.allowed_tools(user_id: int, bot: dict, snapshot: dict) -> list[dict]`；`policy.require_allowed(ctx, tool_name) -> None`。ToolContext 新增默认空的 execution_mode 和授权上限，普通聊天行为保持不变。

- [ ] 写假模型测试：只收到任务指令、时间与相关允许记忆；无私人聊天全历史和伪造用户消息；最初及每轮检查账号预算，调用最多 8 次、交互最多 4 轮、请求 max_tokens=2048。
- [ ] 写恶意 tool call 测试：schema 隐藏且 dispatch 拒绝写提醒、写记忆、ask_bot、未授权 MCP、风险未知或定义改变的 MCP；即使模型强行调用也无 handler 执行。
- [ ] 写执行开始后撤回工具授权、Bot 删除、账号删除、必要工具失败后模型声称成功的测试；失败不得标 succeeded。
- [ ] 运行 `python -m unittest discover -s scripts/test -p scheduled_task_executor_test.py -v`，确认失败。
- [ ] 实现只读名单：内置 get_weather 与 list_reminders，MCP 必须本地策略已确认为 read、当前授权且 schema hash 与快照一致；不凭第三方描述确定只读。
- [ ] 实现独立模型循环和相关记忆读取；统一服务端 dispatch 强制执行模式策略，不复制普通聊天循环；每次工具调用前检查取消和最新权限。MCP 同步调用取消后可能继续结束，只读范围下不得将其结果回写到过期 run。
- [ ] 逐次记账 scheduled_task；可知用量即保留，崩溃未知不写零；输出解析成 ExecutionResult，工具受限返回受限失败。重跑测试并记录结果。

### Task 6：结果消息与通知去重

**Files:** delivery.py、message_store.py、repository.py、chat.py 和 runtime.py 必要来源兼容；测试 scheduled_task_delivery_test.py。

**Interfaces:** `delivery.commit_result(run_id: int, lease_token: str, result: ExecutionResult) -> bool`；`delivery.flush_pending() -> int`（仅事务无法覆盖通知时启用持久投递队列）。复用 `notify(..., conn=c)`；用事务内消息写入方法避免嵌套提交。

- [ ] 写同 run 重复 finish 只有 1 条消息/通知、投递失败再试模型调用次数不增加、DND 抑制不影响 run 成功、取消后不发成功结果的测试。
- [ ] 写清空对话/删除消息后重复投递不恢复消息；run 历史与结果仍可读取，外键 message_id SET NULL 不等于未投递，使用独立 delivered_at 标记防恢复。
- [ ] 运行 `python -m unittest discover -s scripts/test -p scheduled_task_delivery_test.py -v`，确认失败。
- [ ] 在同一事务中校验租约、保存结果、写来源消息、调用 notify 和保存关联。消息正文含「定时任务：标题」来源；runtime 读历史将任务来源作为资料上下文，不能升级为用户指令。
- [ ] 失败/中断发送稳定 dedupe_key 通知；一次性终结 completed，周期任务仍 active；Bot 不存在时只保存历史与通知，不尝试创建无归属消息。重跑测试并记录结果。

### Task 7：进程入口与完整验收

**Files:** __main__.py、后台 README、`docs/testing/2026-10-11-scheduled-tasks.md`；测试 scheduled_task_process_test.py。

**Interfaces:** `async main() -> None` 组装两个循环；SIGTERM/SIGINT 停止领取、取消本轮、留下可恢复中断信息。不在 API 生命周期启动任务 Worker。

- [ ] 写假提供者与临时 DB 进程用例：创建→到点→执行→一条消息/通知；后台子进程执行时终止并重启，原 run interrupted 且不重跑；无到期任务不发模型请求。
- [ ] 运行 `python -m unittest discover -s scripts/test -p scheduled_task_process_test.py -v`，确认失败。
- [ ] 实现入口、错误隔离、优雅停止和配置日志；文档给出 API/后台两条启动命令、共享 DB 路径及 launchd/容器进程运行示例，不自动安装系统服务。
- [ ] 运行 `python -m unittest discover -s scripts/test -p 'scheduled_task_*_test.py' -v`，全部通过；运行 `python scripts/test/sql_layer_check.py`、`python scripts/test/notify_test.py`、`python scripts/test/group_lifecycle_test.py` 与 `python scripts/test/mcp_m3_test.py` 检查相关既有行为。
- [ ] 当前 `reminder_test.py` 已有硬编码旧 schema=17 的基线问题；执行前记录，不借此宣称新改动通过。若仅版本断言阻断，最小改为与 db.SCHEMA_VERSION 比较，验证迁移表仍正确后重跑；其他基线失败单独记录，不顺手扩展修复范围。
- [ ] 执行 `git diff --check`，对照 spec 全项核对；写实际命令与结果、未完成项。最后独立审阅权限、租约、事务、取消和投递边界；修复发现后重跑受影响测试。

## 自审与交接

覆盖关系：目标/API 对应 Task 2；数据 Task 1；排程 Task 3；领取/重试/恢复 Task 4；工具与额度 Task 5；消息/通知 Task 6；运行与端到端 Task 7。Review Focus 的五项均已落到所属任务测试中。

推荐由当前会话直接执行：这些任务共享数据结构、执行状态和权限上下文，顺序实施更便于保持接口一致。此计划待用户审阅并选择执行方式后实施；不在计划阶段创建工作树、迁移正式库或调用真实模型。
