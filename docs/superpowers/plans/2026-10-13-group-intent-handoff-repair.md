# 群聊意图与交接全面修复计划

> 使用 executing-plans 在本对话连续实施。用户已明确授权修复；以已确认设计和复审报告为约束。工作树沿用 group-intent-handoff，产品代码不提交、合并或部署。

**Goal:** 修复复审 R01–R16 及相邻的消息身份、事件重放、历史回复和成员失效边界，让实现符合已确认群聊设计。

**Architecture:** 保留服务端统一调度、持久任务/输入/步骤/澄清/事件和单进程 worker。任务完成依据全部有效步骤；用户输入先原子接受并隔离旧版本，再由路由判断延续/换题。真实 provider 调用单独领取额度及幂等记账，取消与读取并发；客户端持续解析事件，并保存待确认输入。

**Tech Stack:** 原 Python/FastAPI/SQLite/asyncio、SwiftUI 与 VeraBotKit；不新增外部依赖。

**Spec:** ../specs/2026-10-12-group-intent-and-handoff-design.md；复审 ../../testing/2026-10-13-group-intent-and-handoff-review.md。

## Global Constraints

- 不恢复默认成员，不引入群外资料/工具权限；群人数2–4，自动链6次实际成员调用、每步60秒/768 tokens、累计240秒。
- 同一澄清保持负责人；点名/回复/新话题优先；保留原目标和累积回答。咨询支持有界返回栈，交接传完整合同。
- 停止必须关闭上游，迟到结果不能安排动作；已知 usage 记一次，未知保持未知。
- 实际测试使用临时数据和假 provider；真实模型及设备验收单列。最终一次独立复审。

## Review Focus

- 多人第一位完成或等待用户，其他成员的顺序与任务状态不能丢失（Task1）。
- 新指令在模型无首事件时到达，旧版本必须迅速释放，尾文/用量仍可保存（Task3）。
- 澄清回答只有“好的”、换题或自然语言点名，不能丢需求或覆盖有效选人（Task2）。
- SSE 未结束、断线重连、快照与历史读取之间事件到达，不能漏身份/内容/进度（Task4/5）。
- POST已接受但回执不可查、离开重进、双设备409、清空后旧observer返回，不能重复提交或恢复旧状态（Task5）。

## Task 1：任务步骤完成与合作合同（R01/R12/R16）

Files: db/group_execution_store.py、services/group_actions.py、agents/group_context.py；测试 group_repair_state_test.py。
Interfaces: commit_step 完成需无有效 queued/running 步骤；next_steps 保留 completion_criteria 和 consult_stack；build_execution 加载经归属校验的明确群资料；retry 恢复原咨询关系。
- [x] 写并运行失败用例：多人/全体全数完成、嵌套咨询/交接返回、完成条件/旧群资料进入提示。
- [x] 实现步骤状态、咨询栈与合同传递，按指定引用加载群资料。
- [x] 重跑新测试及已有 store/handoff/worker，记录通过证据。

## Task 2：输入延续、澄清与路由（R08/R09/R10/R11）

Files: db/group_execution_store.py、services/group_dispatch.py、group_routing.py；测试 group_repair_routing_test.py。
Interfaces: create_input 保留此前 task goal/owner，接受时递增版本、撤销旧待执行动作；apply_route 在 replace 后切换新task，继续保持原task；routing_context 提供原目标、累积输入及真实历史回复。
- [x] 失败用例：运行补充沿用目标/负责人、独立换题新task/正确Bot、自然点名改向、连续答案不覆盖原目标、历史回复/失效成员。
- [x] 实现路由优先级和持久需求，删除把短肯定当已解决的捷径。
- [x] 重跑路由/澄清/API/worker测试，记录通过证据。

## Task 3：调用级预算、取消及费用（R03/R04/R05/R06）

Files: group_execution_store.py、group_runtime.py、group_worker.py；测试 group_repair_runtime_test.py。
Interfaces: begin_member_call 原子限制真实6次/剩余耗时；record_call 幂等记账（包含取消）；interrupt_step 可保存安全的最终片段；worker 独立等待取消并关闭generator。
- [x] 失败用例：空重试计2次且费用求和、第6次不能空重试、每日预算耗尽零provider请求、无首事件迅速取消、尾文/已知用量停止后仍记一次、累计时间上限。
- [x] 实现每次provider前预算/计数、调用ledger、可取消读取和剩余耗时限制。
- [x] 重跑worker/runtime/API及私聊回归，记录通过证据。

## Task 4：可重放实时事件（R02相邻边界）

Files: group_execution_store.py、api/group_execution.py、Core/GroupExecutionReducer.swift；测试 group_repair_events_test.py 与 GroupExecutionRepairTests.swift。
Interfaces: message_start/snapshot/done 携完整消息身份；task_updated/clarification_updated 携快照；receipt不跳过尚未应用事件；snapshot与消息读取后的重放不能漏内容。
- [x] 失败用例：事件带身份和终态、重放能重建聊天/负责人、receipt cursor不跳过消息、旧任务事件只推进cursor不覆盖新状态。
- [x] 实现事件合同与reducer，兼容已存在历史事件。
- [x] 跑后端事件/HTTP及Swift过滤回归。

## Task 5：客户端提交、观察与恢复（R02/R07/R13/R14/R15）

Files: Networking/GroupChatAPI.swift、Data/GroupChatViewModel.swift、ConversationRepository.swift、Persistence/ConversationStore.swift、Core/GroupExecution.swift、GroupExecutionStatusView.swift；测试 GroupExecutionRepairTests.swift 和实际本地socket流。
Interfaces: SSE逐帧yield；pendingGroupInput在SQLite账号范围持久存储，结果确认前保持同UUID；409只同步不重发；clear隔离observer并重置执行；等待澄清可停止、停止可继续；断线保留cursor并恢复。
- [x] 失败用例：EOF前收到消息、不确定POST+lookup失败后重进同UUID、重复发送不能并发、双设备冲突同步、清空后正常新消息、等待停止与继续可达。
- [x] 实现提交生命周期/真实事件处理/视图入口，删除旧请求绑定死代码。
- [x] Swift全量、localhost socket/SSE、iOS Simulator构建并核对警告。

## Task 6：整体验收与独立复审

Files: docs/testing/2026-10-13-group-intent-handoff-repair.md、STATUS/原计划/验收文档。
- [x] 所有修复用例与相关后端/Swift回归、临时HTTP、Simulator构建通过；SQL检查如有基线失败如实记录。
- [x] 派发一次独立全实现复审；重要问题先失败用例再修复并复跑。
- [x] R01–R16逐项记录修复与证据；设计验收1–10区分自动化与真实模型/设备状态；纠正原完成标记。
