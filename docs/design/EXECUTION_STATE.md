# 执行状态机 (Execution State Machine) — v1.0

> 状态：**已实现 (2026-10-03)**，Boss 批准第 1 步「只做 Core 状态 + 测试」。代码：`frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/ExecutionState.swift`；SSE 映射：`VeraBotNetworking/APIClient.swift` 的 `ChatEvent.executionEvent`；测试：`Tests/VeraBotKitTests/ExecutionStateTests.swift` (EXEC-01~19)。
> **界面未改**：`ChatViewModel` 只读暴露 `executionState`，没有任何视图使用它。**后端未改**，状态全部由现有 SSE 事件推导。

## 1. 目的

明确「Bot 现在在做什么」，替代原来由 `sending` / `streaming` / traces 推断的做法，作为以后状态文案、头像动画 (见 §6) 的唯一数据源。纯数据、无 UI、无网络、无计时器，可在 Linux / macOS 上 `swift test`。

## 2. 状态 (States)

| 状态 | 含义 | `isActive` |
|---|---|---|
| `idle` | 没有进行中的回复 | 否 |
| `thinking` | 已发送，等首字；或工具返回后模型继续处理 | 是 |
| `callingTool(name:)` | 调用 `ask_bot` 以外的工具 (含 `remember` / `forget_memory`)，值为后端工具名 | 是 |
| `delegating(botName:)` | `ask_bot` 委派，值为 `args.bot_name` (缺失为空串) | 是 |
| `replying` | 正在输出文字 | 是 |
| `awaitingConfirmation` | 回复结束，本轮产生了待确认的记忆卡片 | 否 |
| `completed` | 回复正常结束 | 否 |
| `failed(message:)` | 本轮出错 | 否 |

## 3. 输入事件与后端对应 (Event mapping)

| 输入 `ExecutionEvent` | 来源 |
|---|---|
| `sent` | 客户端：用户发出消息 (`ChatViewModel.send`) |
| `delta(text)` | SSE `delta` `{text}` |
| `toolStart(trace)` | SSE `tool_start` `{id, name, args}` |
| `toolResult(trace)` | SSE `tool_result` `{id, name, args, result}`；记忆工具 `result.memory_id` + `status = proposed` 视为确认卡片 (与 `MemoryProposal.isCard` 相同) |
| `error(message)` | SSE `error` `{message, code?}`；客户端 HTTP 429 / 网络错误 |
| `done` | SSE `done` `{message_id, usage, memory_ids}` |
| `streamEnded` | 客户端：SSE 流结束 (无论是否收到 done) |
| `confirmationResolved(memoryID:)` | 客户端：卡片「记住 / 编辑后记住 / 不用」成功 |
| `reset` | 客户端：清空对话；以后也用于完成提示展示结束、离开页面 |

后端顺序 (`agents/runtime.py`)：每轮 LLM 先 `delta*`，有工具调用时逐个 `tool_start` → `tool_result` (串行)，再进入下一轮；出错时先 `error` 再 `done`；`done` 总是最后一个事件。被委派 Bot 的内部过程不推送事件 (只看到外层 `ask_bot` 的 start / result)。

## 4. 转移表 (Transitions)

| 当前状态 | 事件 | 下一状态 | 说明 |
|---|---|---|---|
| 任意 | `sent` | `thinking` | 清空未返回工具和待确认集合 |
| 活跃 | `delta` (非空) | `replying` | 空串忽略 |
| 活跃 | `toolStart` (`ask_bot`) | `delegating(botName)` | 记录为未返回工具 |
| 活跃 | `toolStart` (其他) | `callingTool(name)` | 同上 |
| 活跃 | `toolResult` | 最近开始且未返回的工具状态；没有则 `thinking` | 卡片结果加入待确认集合；无对应 start 也接受 |
| 活跃 | `error` | `failed(message)` | |
| 活跃 | `done` / `streamEnded` | 待确认为空 → `completed`，否则 `awaitingConfirmation` | |
| `awaitingConfirmation` | `confirmationResolved(id)` | 集合清空后 → `idle` | 不在集合中的 id 忽略 |
| 任意 | `reset` | `idle` | 清空所有内部记录 |
| 非活跃 | `delta` / `toolStart` / `toolResult` / `error` / `done` / `streamEnded` | 不变 | 迟到 / 重复事件忽略；因此 `failed` 后的 `done` 保持 `failed` |

规则：出错优先于待确认 (有卡片也显示 `failed`，卡片本身仍在对话里可点)；新的一轮 `sent` 会丢弃上一轮的待确认记录 (卡片仍可点，只是不再影响状态)。`completed` 不会自动回到 `idle`，由界面层在展示完成提示后发 `reset` (目前未接)。

## 5. 接入现状

- `ChatViewModel`：`private(set) var execution`、`var executionState`；在 `send` 开始、每个 SSE 事件、429 / 网络错误、流结束、确认 / 拒绝卡片、清空对话时喂事件。**没有视图读取**，界面行为不变。
- 首页列表不接：后端没有后台任务，离开对话页后状态不准。

## 6. 以后对接头像实验室 (AvatarLab) 的建议映射

头像实验室 (`Features/Settings/AvatarLab*.swift`，调试页入口) 的 `AvatarLabState` 有 6 种：空闲、思考中、执行中、等你确认、已完成、遇到阻塞。建议在 App 层 (不放进 Core) 做一层映射：

| `ExecutionState` | `AvatarLabState` |
|---|---|
| `idle` | `idle` |
| `thinking` | `thinking` |
| `callingTool` / `delegating` | `working` |
| `replying` | `working` (或以后新增「回复中」) |
| `awaitingConfirmation` | `waiting` |
| `completed` | `done` (展示后 `reset` → `idle`) |
| `failed` | `blocked` |

待 Boss 决定：是否为 `replying` / `delegating` 单独设计动作；持续状态 (thinking / working) 是否循环播放 (实验室目前每次触发只播一次)；正式使用前颜色需换成 Theme 语义色、支持深色模式。

## 7. 以后可选 (未做)

后端新增 `status` 事件 (如「正在回忆」「被委派 Bot 内部进度」) 时，在 `ExecutionEvent` 加对应 case，并加前后端契约测试；现有 5 种事件保持兼容。
