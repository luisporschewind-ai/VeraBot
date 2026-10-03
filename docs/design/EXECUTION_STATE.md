# 执行状态机 (Execution State Machine) — v1.1

> 状态：**已实现**。v1.0 (2026-10-03，`d43176e`)：Core 状态 + 测试。v1.1 (2026-10-03，Boss 批准 4 项决定)：后端新增 SSE `status` 事件 (召回记忆 + 委派内部进度)；Core 新增 `recalling`、委派进度、短暂受阻 `blocked`；头像实验室新增「回复中」「委派中」并接入映射与演示。
> 代码：后端 `backend/verabot/agents/runtime.py` (`status_data` / `_emit_status` / `_run_tool_streaming`)、`tools/registry.py` (`TurnState.status_queue` / `parent_id`)；iOS `VeraBotCore/ExecutionState.swift` (`ChatStatus`、`ExecutionState`、`ExecutionStateMachine`)、`VeraBotNetworking/APIClient.swift` (`ChatEvent.status`、`executionEvent`)、`Features/Chat/ChatViewModel.swift` (只读 `executionState` + 受阻计时)、`Features/Settings/AvatarLab*.swift` (映射与动画)。
> 测试：后端 `scripts/test/status_event_test.py` STAT-01~08 (含契约)；iOS `ExecutionStateTests.swift` EXEC-01~33。
> **对话界面未改**：`ChatViewModel` 只暴露状态，没有视图读取；头像实验室 (设置 › 调试) 可以演示。**Web 冻结**：忽略 `status` 事件 (未知事件本来就跳过)。

## 1. 后端 `status` 事件 (新增，向后兼容)

```
event: status   data: {"phase", "depth", "bot_name", "tool", "parent_id"}   # 固定 5 个键，未用到的为 null
```

| phase | 何时发 | depth | bot_name | tool | parent_id |
|---|---|---|---|---|---|
| `recalling` | 每轮开头、召回记忆 / 组装上下文之前 (仅用户开启记忆时) | 0 | 当前 Bot | null | null |
| `thinking` | 被委派 Bot 每次调用模型前 (`run_once`) | ≥1 | 被委派 Bot | null | 外层 `tool_start.id` |
| `tool` | 被委派 Bot 调用工具前 (含再次 `ask_bot`) | ≥1 | 被委派 Bot | 工具名 | 外层 `tool_start.id` |

- 机制：外层工具执行期间 `run_chat` 在 `TurnState` 上挂一个 `asyncio.Queue`，委派树里的 `run_once` 往里放进度，`_run_tool_streaming` 一边等工具一边转发，因此进度**实时**出现在外层 `tool_start` 与 `tool_result` 之间。`TurnState` 跨整棵委派树共享，所以两跳委派 (depth 2) 的 `parent_id` 仍是最外层那次 `ask_bot` 的 id。
- 不写入 `messages.traces`，不计入用量；旧客户端 / Web 忽略。
- 被委派 Bot 内部工具的**结果**不推送 (隐私与上下文隔离不变)，只推送「在调用哪个工具」。

## 2. 状态 (States)

| 状态 | 含义 | `isActive` |
|---|---|---|
| `idle` | 没有进行中的回复 | 否 |
| `recalling` | 召回记忆 / 准备上下文 (status recalling) | 是 |
| `thinking` | 等首字；或工具返回后模型继续处理 | 是 |
| `callingTool(name)` | 调用 `ask_bot` 以外的工具 (含记忆工具) | 是 |
| `delegating(botName, progress)` | `ask_bot` 委派；`progress` = 最近一条内部进度 `DelegationProgress(botName, depth, tool?)`，`tool == nil` 表示对方在思考；未收到进度时为 nil | 是 |
| `replying` | 正在输出文字 | 是 |
| `blocked(code, message)` | **短暂受阻**：工具 / 委派被拒绝或失败，展示 `blockedDisplayDuration` (1.2 s) 后回到原流程 | 是 |
| `awaitingConfirmation` | 回复结束，本轮有待确认的记忆卡片 | 否 |
| `completed` | 正常结束 | 否 |
| `failed(message)` | 整轮出错 | 否 |

## 3. 输入事件与来源

| `ExecutionEvent` | 来源 |
|---|---|
| `sent` | 客户端：发出消息 |
| `delta(text)` | SSE `delta` |
| `toolStart(trace)` | SSE `tool_start` `{id, name, args}` |
| `toolResult(trace)` | SSE `tool_result` `{id, name, args, result}`；`result.error` 非空 → 受阻；记忆 `memory_id` + `status = proposed` → 待确认 |
| `status(ChatStatus)` | SSE `status` (§1) |
| `error(message)` | SSE `error`；HTTP 429 / 401 / 404、网络错误 |
| `done` / `streamEnded` | SSE `done` / 流结束 |
| `blockedElapsed(serial)` | 客户端：受阻展示时间到 (`ChatViewModel` 用 `Task.sleep` 计时；Core 本身无计时器) |
| `confirmationResolved(memoryID)` | 客户端：卡片处理成功 |
| `reset` | 客户端：清空对话等 |

受阻判定 (`ExecutionStateMachine.failure(of:)`)：`result.error` 存在且非空字符串，`code` 可选。覆盖委派拒绝 `self` / `loop` / `not_in_allowlist` / `target_refuses` / `turn_cap` / `budget`、找不到 Bot (无 code)、权限 `unknown_tool` / `tool_not_allowed` / `max_depth` / `memory_not_delegable` / `memory_disabled`、参数错误、工具异常、记忆工具错误 (如 `proposal_cap`)。`already_known` / `previously_declined` 不是错误。

## 4. 转移表 (Transitions)

「活跃」= `isActive` (含 `recalling`、`blocked`)。「流程状态」= 最近开始且未返回的工具状态，没有则 `thinking`。

| 当前 | 事件 | 下一状态 | 说明 |
|---|---|---|---|
| 任意 | `sent` | `thinking` | 清空未返回工具、待确认集合 |
| `thinking` | `status(recalling)` | `recalling` | 其他状态下忽略 (已出字 / 已调工具) |
| 活跃 | `delta` (非空) | `replying` | 也会提前结束 `recalling` / `blocked` |
| 活跃 | `toolStart` (`ask_bot`) | `delegating(bot, nil)` | |
| 活跃 | `toolStart` (其他) | `callingTool(name)` | |
| 活跃 | `status(thinking / tool)`，depth ≥ 1，`parent_id` 指向未返回的 `ask_bot` | 更新该委派的 `progress`；非受阻时切到流程状态 | `parent_id` 不匹配或指向非委派工具：忽略 |
| 活跃 | `status` 未知 phase | 不变 | 向前兼容 |
| 活跃 | `toolResult` 成功 | 流程状态 | 卡片加入待确认 |
| 活跃 | `toolResult` 带 error | `blocked(code, message)` | `blockedSerial += 1`，记住流程状态 |
| `blocked` | `blockedElapsed(serial)` (serial 为最新) | 记住的流程状态 | 旧计时器忽略 |
| 活跃 | `error` | `failed(message)` | |
| 活跃 | `done` / `streamEnded` | 无待确认 → `completed`，否则 `awaitingConfirmation` | |
| `awaitingConfirmation` | `confirmationResolved(id)` | 集合清空后 `idle` | |
| 任意 | `reset` | `idle` | |
| 非活跃 | 其余流事件 | 不变 | 迟到事件忽略；`failed` 后的 `done` 保持 `failed` |

## 5. 后端 → 状态机 对照

| 后端信号 | 状态 |
|---|---|
| (客户端发送) | `thinking` |
| `status` recalling | `recalling` |
| `delta` | `replying` |
| `tool_start` 其他 / `ask_bot` | `callingTool` / `delegating` |
| `status` thinking / tool (depth ≥ 1) | `delegating.progress` |
| `tool_result` 带 `error` | `blocked` (短暂) |
| `tool_result` 记忆卡片 + `done` | `awaitingConfirmation` |
| `done` | `completed` |
| `error`、HTTP 错误 | `failed` |

未使用的后端信号：`error.code`、`done.usage`、`done.memory_ids`、委派内部工具结果 (不推送)、持久化状态 (`delegations.status`、`reminders.done`、`memories.status`，属于历史记录)。

## 6. 状态机 → 头像实验室 (8 种)

映射在 App 层 `AvatarLabState.init(_ execution:)`，Core 不依赖界面。

| `ExecutionState` | `AvatarLabState` | 动画 (系统 `phaseAnimator`) |
|---|---|---|
| `idle` | 空闲 `idle` | 单次轻微缩放 |
| `recalling`、`thinking` | 思考中 `thinking` | **循环**：轻摆 + 眼睛看向一侧 |
| `callingTool` | 执行中 `working` | **循环**：上下跳动 |
| `delegating` | 委派中 `delegating` (新) | **循环**：侧移 + 眼睛看向另一侧 |
| `replying` | 回复中 `replying` (新) | **循环**：纵向起伏 + 张嘴 |
| `awaitingConfirmation` | 等你确认 `waiting` | 单次 |
| `completed` | 已完成 `done` | 单次轻跳 |
| `blocked`、`failed` | 遇到阻塞 `blocked` | 单次轻摇；`blocked` 1.2 s 后回到原状态，`failed` 停留 |

- 持续状态只在**视图可见且 App 在前台**时循环 (`onAppear` / `onDisappear` + `scenePhase`)，离开屏幕即停止；其余状态在状态切换或「重播」时播放一次。
- 「减弱动态效果」开启时全部静态。
- 实验室「按状态机演示一轮对话」：用与后端同形的事件 (召回 → 委派 + 进度 → 被拒工具 → 回复 → 完成) 驱动真实 `ExecutionStateMachine`，事先算好帧序列 (`AvatarLabDemo.frames`) 再按时间播放，下方显示「状态机：… → 头像：…」。实际头像顺序：**思考中 → 委派中 (进度文字变化) → 思考中 → 执行中 → 遇到阻塞 (1.2 s) → 思考中 → 回复中 → 已完成 → 空闲** (委派结束、阻塞结束后都会先回到思考中)。停止 / 重新开始 / 手动选状态会让旧的演示作废 (运行令牌)，不会两轮叠加。
- 状态角标在头像**右下角** (尺寸 0.26，避开 V豆 顶部圆点和星点右上角的星光)，底色 `avatarMarkFill` (浅色白 / 深色 #2C2C2E)，描边用角色背景色。
- 颜色：角色色已换为 `Theme.swift` 的头像语义色 (`avatarBeanBody` 等，浅色 / 深色各一套)，以及 `avatarInk`、`avatarBlush`、`avatarBlockedMark` (systemOrange)、`avatarMarkFill`；实验室不再有固定 hex。

## 7. 未做 / 待定

- 对话页尚未显示状态 (文案或头像)，`completed` 之后何时 `reset` 待界面方案确定。
- 委派内部工具的结果、`error.code` 未进入状态。
