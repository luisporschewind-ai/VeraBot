# 群聊意图分配与任务交接复审

日期：2026-10-13。审查工作树：`/Users/admin/.codex/worktrees/group-intent-handoff/VeraBot-v0.1`，基线 `4fc063d`，包含尚未提交的新文件。

## 结论

架构方向符合确认设计，但实现未完整执行到位，不宜按“任务 1–9 全部完成”进入合并或部署。默认回应者已真正移除；服务端任务、步骤、澄清、事件和 worker 的分层符合完整后台接力模式；单次咨询 A→B→A 和直接交接 A→B 的基本路径存在。关键状态转换、运行控制和客户端观察仍有确定性缺陷。

本次检查了设计稿、计划、后端调用链、iOS 数据流及对应测试，并通过两份独立复审交叉检查。诊断只使用临时 SQLite 和假模型，没有访问真实模型、运行正式库迁移或改动产品代码。以下区分“临时诊断复现”和“静态代码证实”，不把构建通过当作交互验收。

## 优先修复：P1

### R01 多人点名和全体发言在第一位结束后停止

`backend/verabot/db/group_execution_store.py:361` 无论是否还有已排队成员，都将任务改成 completed；`:214` 的领取查询只接受 queued/running 任务。临时 SQLite 复现：安排 A、B；A 完成后任务 completed，B 仍 queued，下一次领取返回 None。违反设计 §6 的“所有所选成员依次回应”。任务完成必须由所有有效待执行步骤共同决定。

### R02 iOS 在 SSE 结束后才解析事件

`frontend/ios/Packages/VeraBotKit/Sources/VeraBotNetworking/GroupChatAPI.swift:149` 先收集全部行，`:161` 在读取结束后才 decode/yield；服务端事件连接在任务 queued/running 时保持打开。静态代码证实：执行期间没有实时文字和交接进度；读取途中失败时已收到的帧也未应用。应边读边处理完整事件帧。

### R03 新执行路径没有每日用量限制

`backend/verabot/agents/group_runtime.py:48` 直接调用成员模型；`backend/verabot/services/group_routing.py:200` 直接调用分类模型。当前 token budget 检查只留在未使用的旧 runtime.run 中。静态调用链证实：协议 v2 的提交、路由及成员调用均未检查每日预算，额度用尽仍可继续生成。需要在实际调用前检查，并将当次已知用量纳入限制。

### R04 空回复重试绕过六次调用上限并漏记第一次用量

`backend/verabot/agents/group_runtime.py:44` 一次成员步骤可调用两次模型，存储层只在 claim_next 为该步骤计一次；`:60` 还用第二次 usage 覆盖第一次。临时假模型复现：两次实际请求的 token 总数分别 3、5，持久 call_count=1、usage=5。设计 §9 要求每次实际调用计数，咨询返回及空回复重试均不能绕过额度。

### R05 停止无法及时终止正在等待的流

`backend/verabot/agents/group_runtime.py:49` 在等待下一个事件期间不观察取消；`group_worker.request_cancel` 只设置 Event，不取消待完成的上游 await。临时假流复现：停在首事件之前，发 stop 后 1.2 秒 worker 仍未退出；成员调用可继续阻塞到 60 秒超时，并持有全局 worker 锁。新指令优先的目标因此没有兑现。应让停止信号与上游读取并发等待，并关闭上游。

### R06 停止时丢弃尾部正文和已知用量

`backend/verabot/services/group_worker.py:96` 对 stopped 结果只调用 interrupt_step，丢弃 result 中 content/usage；存储中断方法只保留上次 snapshot，没有调用记账。临时复现：已有 256 字符快照，模型返回额外尾部及已知 usage=77；停止后只有 256 字符，用量行数为零。路由取消、语义 stop 提前返回也会绕过用量提交。需将状态隔离与结果/用量保存分开，迟到结果不能调度后继，但已知费用必须记一次。

### R07 请求结果持续不确定时，客户端会换 UUID 重发

`frontend/ios/Packages/VeraBotKit/Sources/VeraBotData/GroupChatViewModel.swift:120` 请求 ID 仅存在于 send 的局部变量。POST 已接受、响应丢失且 receipt 查询同样失败后，仅恢复草稿；用户再次发送或离开重进会创建新 UUID。`:125` 还会取消上一个提交，入口没有 !sending 保护。静态数据流证实：后端同 UUID 幂等能力不能覆盖这些场景，可能重复执行。应持久保留尚未确认的完整请求及 UUID，并阻止第二次不确定提交。

## 需要补齐：P2

### R08 运行中的补充被提前当作新任务

`backend/verabot/db/group_execution_store.py:139` 只把 awaiting_user 且带 clarification_id 的请求视为继续；其余请求在分类之前停止当前任务并创建新 task。客户端 `GroupChatViewModel.swift:119` 也只对等待澄清带 task/version。即使“预算再加一个限制”是原目标的补充，路由器已经看不到原运行任务的身份和负责人。违反设计 §4 当前任务补充与 §9 更新旧目标的要求。应先保存待判断输入，区分继续/替换后再做版本化转换。

### R09 澄清答案覆盖完整任务目标

`backend/verabot/db/group_execution_store.py:173` 把继续中的 task.goal 直接写成最新答案；`group_routing.py:173` 的简短肯定快路径再读取该 goal。临时复现：原目标“帮我安排一次周末旅行”，Bot 问“从北京出发吗？”，用户答“好的”，路由得到 goal="好的"。随后 apply_route 将澄清 resolved，执行提示不再含活动澄清。群历史可能暂时帮助模型恢复，但结构化完整需求没有可靠保留，超过历史窗口后不能保障。应持续保存原目标和累积答案，信息充分后形成完整需求。

### R10 换题时丢弃分类器选出的专业成员

`backend/verabot/services/group_routing.py:120` 对 replace 无条件清空 speaker_ids，随后 `:138` 以无相关候选的公平选择重新选人，并可能制造“用户希望完成的事情”缺项。临时复现：分类器为新旅行话题选 B，最终返回 A。换题应解除旧澄清绑定并保留新意图的有效分配。

### R11 活动澄清压过自然语言明确点名

`backend/verabot/services/group_routing.py:105` 仅在没有澄清时处理自然语言称呼；`:127` 随后强制旧 owner。临时复现：“写作者，接下来你来处理”，分类器明确选写作者 B，最终仍返回研究员 A。违反设计 §4 的称呼优先于活动澄清。应先处理新的有效称呼，再决定是否延续原 owner。

### R12 被咨询成员的后续协作动作被悄悄改成返回

`backend/verabot/services/group_actions.py:47` 只要有 consult_return_step_id，就在查看 action.kind 之前返回任务 owner。临时复现：B 输出通过校验的 handoff C，实际计划为返回 A；咨询 C 也同样被吞掉。当前只实现了一层返回指针，未实现计划中的返回栈。应实现受预算约束的咨询关系，或明确拒绝不支持的动作，不能记录“交接成功”却执行另一动作。

### R13 清空群后保留旧澄清和观察状态

`frontend/ios/Packages/VeraBotKit/Sources/VeraBotData/GroupChatViewModel.swift:248` 只清消息 state，未重置 execution、旧 messages/cursor 或隔离 observer。等待澄清时清空后，下一次 send 仍携带已取消的 clarification/version，服务端返回 409；旧任务状态也留在界面。应将清空后的执行状态和观察周期一起重置。

### R14 停止和继续入口不完整

`GroupChatViewModel.swift:214` 拒绝 awaitingUser 状态的 stop，UI 也因 busy=false 不显示停止；后端本身支持结束等待澄清。`frontend/ios/VeraBot/Features/GroupChat/GroupExecutionStatusView.swift:10` 外层排除 stopped，`:29` 中 stopped 的“继续任务”永远不可见。两条都是静态代码可确定的 UI 分支缺口。

### R15 双设备冲突未恢复服务端快照

`GroupChatViewModel.swift:132` 将提交失败统一当作不确定请求，查 receipt，404 后重发；最外层只显示通用 409 文案。没有采用冲突中最新 task/clarification，也不重新读取 execution。第二设备回复旧澄清后仍保留旧状态，继续发送会反复冲突。计划明确要求“同步新快照且不重发”，对应实现和测试未落实。

### R16 交接合同中的资料和完成条件没有完整进入下一步

`backend/verabot/services/group_actions.py:55`、`:60` 创建 successor 时漏掉 completion_criteria；`backend/verabot/agents/group_context.py:82` 不加载明确的 context_message_ids/attachment_ids，只使用常规最近 24 条历史。校验和保存引用不能替代实际提供给模型；较早群消息、旧附件以及交接完成条件会失效。应在权限校验后按引用构建下一步上下文，并把完成条件传递到执行提示。

## 架构忠实度与测试评价

符合：统一服务端调度器不伪装成 Bot；成员身份用 ID；默认字段仅留在历史迁移；持久状态与 SSE 观察分离；群资料与私聊/工具权限分离；单进程约束与确认计划一致。

未落实：多人任务完成条件、当前目标延续、部分路由优先级、完整需求累积、咨询返回关系、实际调用级预算/记账、及时取消，以及客户端持续观察/不确定请求恢复。问题集中在跨模块状态转换，暂不需要推翻整套架构。

此前测试通过的事实仍成立，但不足以证明完整设计成立：

- GroupExecutionTests 的 observer 立即结束，无法检测 EOF 前没有事件；不确定请求只有 lookup 404 后成功重试的用例。
- “澄清负责人恢复”主要是静态快照 JSON 往返，不等于连续答案、双设备冲突和应用恢复的完整链路。
- handoff 中六次额度用例只断言布尔 helper，没有证明真实运行器空重试被计数。
- 换题测试期待的成员刚好也是公平选择得到的第一位，没发现分类器选择被丢弃。
- localhost 用例覆盖简单单成员咨询/交接，未覆盖多人首轮全部完成及故障组合。

计划里全部勾选、台账任务全部完成，应在修复与对应回归后重新核定。已通过的测试数量、模拟器构建和单次演示不能作为完整交付依据。

## 建议处理顺序

1. 先修任务/输入/步骤的状态转换，覆盖多人全部完成、补充/换题区分、澄清目标与引用传递。
2. 修真实调用级计数/用量、每日预算、取消及迟到结果处理。
3. 修客户端边读边解析、事件身份/状态同步、不确定请求持久恢复、冲突/清空/停止/继续入口。
4. 将每个复现转成行为回归，跑后端与真实客户端组合的临时服务联调，再进行真实模型和用户设备验收。

本次仅审查，产品代码未修复。真实模型选择质量和设备体验仍待验收；上述问题多数不依赖真实模型即可确定。
