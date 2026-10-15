# 2026-10-14 集成之后的遗留问题

PR #31 已合入 main（`8b90ef8`）。`6bd6062` 把 `ChatView` 的消息单元格拆开，避开 Swift 类型检查超时。本文件记录当时留下的问题，以及分支 `fix/2026-10-14-followups` 处理后的状态。

## 已处理

### 本机假模型服务没有私聊回复

`backend/scripts/dev/primary_bot_manual.py` 原来只在进程里跑主 Bot 任务和定时调度。私聊回复要另起 `python -m verabot.services.chat_tasks`，而假模型端口是随机的，这个独立进程对不上同一个模型和数据库。

现在同一次启动会：

- 把假模型绑在 `VERABOT_FAKE_MODEL_PORT`（默认 `0`，仍由系统分配），并把 `DEEPSEEK_BASE_URL` 设成这个地址后再导入应用。
- `stream: true` 时返回 SSE（一段固定中文，说明这是本地假回复）；非流式请求仍返回原来的任务 JSON。
- 在 API 进程里同时跑私聊 worker、主 Bot worker 和定时 `tick`。退出时取消私聊循环。
- API 自己还会拉起群执行 worker。群聊如果走到模型，也打到同一个假模型。

从 `backend/` 启动：

```bash
python scripts/dev/primary_bot_manual.py --data-dir /tmp/verabot-primary-manual --port 8096
```

账号仍是 `primary-test` / `primary-test-2026`。

### 群聊页没有把可见消息交给通知同步

私聊页会把当前屏幕上的消息 id 交给 `NotificationEventSync`。群聊页之前只做了未读已读，没有做这件事，所以人待在群里时，前台仍可能把这条群回复当成新通知弹出来。

现在 `GroupChatView` 用和私聊相同的视口测量，写入 `visibleGroupID` 和 `visibleMessageIDs`，并清掉 `visibleBotID`。信息页、相册、文件、相机盖住对话时清空可见 id。离开该群时，只有当前记录的还是这个群才清空。

同步时分两种对话，避免两套自增 id 撞号：

- 打开的是私聊：仍要求 `visibleBotID == note.botId`。
- 打开的是群：只对 `thread_id == group:{群 id}`，或 `link` 为 `group/{群 id}` / 以 `group/{群 id}/` 开头的通知使用这组 id。

群消息完成（`group_execution_store.commit_step`）目前不调用 `notify()`。因此今天不会为一条群回复单独写入通知事件，通知同步也不会为它弹横幅。页面接线按私聊的可见性规则准备好了；若以后要在离开群之后提示，应在完成事务里用保存点发布，`thread_id` 用 `group:{id}`，并补上群深链。点按未知链接现在会落到收件箱。

列表滚离底部时的「有新回复 ↓」仍保留，和私聊一样，它不是通知横幅。

### SQL 分层

PR #33（`refactor/sql-layer-cleanup`，合入 `244e906`）已把当时留下的直连查询收进 `db/`：

- `api/routers/bots.py`（`bot_tool_calls`）→ `audit_store`
- `services/actions/__init__.py`（`confirm`）→ `action_store`
- `services/mcp/oauth.py` → `mcp_store`
- `services/memory/`（`collaboration` / `embeddings` / `extract` / `growth` / `quick_prompts` / `service` / `suggestions`）→ 对应 memory / suggestion / vector 等 store

`sql_layer_check.py` 现对 `db/` 以外模块严格检查（无 known 白名单）。合入时：`sql_layer_check` SQL-LAYER-01/02 通过；`run_offline.py` 59 通过 / 6 跳过（仍依赖已启动服务、真实模型或外网的脚本除外）。

### 离线测试入口

`scheduled_task_executor_test.py` 在插入 `backend/` 搜索路径之前就导入了 `verabot`，从仓库根目录直接跑会报 `No module named verabot`。已把路径设置挪到导入之前。`scheduled_task_*_test.py` 原先只有测试类、没有脚本入口，直接执行会什么都不跑；现在以脚本运行时会进入 `unittest.main()`。

一条命令跑完全部离线后端检查（每个脚本单独进程；这些脚本在 import 时各自建库，不能放进同一次 pytest）：

```bash
cd backend && uv run python scripts/test/run_offline.py
```

跳过依赖已启动服务、真实模型或外网的脚本：`smoke_test.py`、`web_browser_test.py`、`web_query_test.py`、`mcp_oauth_test.py`、`group_http_test.py`、`group_execution_http_test.py`。`sql_layer_check.py` 包含在这条命令里。

本分支在这台 Linux 上跑完这条命令：59 通过，0 失败，6 个跳过。`scheduled_task_executor_test.py` 从仓库根目录直接执行，10 项通过。假模型服务用同一个进程登录 `primary-test` 并发送私聊后，助手消息状态为 `completed`，正文是上面的固定假回复。

### 离线提示统一（补充，PR #34）

PR #34（`fix/offline-notice-unify`，合入 `e888375`）后：助理列表不再叠两条失败提示；各主页面用单个 `ConnectionNotice`（标题「暂时连接不上」、按钮「重新连接」）。`AppState.message(for:)` 不再直接抛 `localizedDescription`。本文件原先关注的群聊可见性 / 假模型等问题与该 PR 无关；离线文案与单条横幅以 #34 为准。

### Bot 数量限制（补充，PR #35 / #36）

PR #35 已合入 UI 层 10 Bot / 群聊 2～5 限制。PR #36 跟进：去掉助理列表「我的 Bot（n/10）」展示与创建群聊底部提示卡片（说明改 footer）。规格与变更记录见 [bot-limits](../superpowers/specs/2026-10-14-bot-limits.md)。PR #37 已接线群成员增删；左滑 `role: .destructive` 会在确认前移走行，由 `fix/group-member-remove` 修复（非 destructive + `.tint(.red)` + 确认后 `withAnimation` 再删；添加改为多选、无 footer）。

### 群 await_user 空 missing_information 误失败（补充，PR #38）

现象：成员已完整流出正文，但 `group_next_step` 为 `kind=await_user` 且 `missing_information=[]` 时，`group_actions.validate` 抛错，`group_runtime` 通吃异常把步骤/消息标 `failed`，iOS 在完整回复下显示「回应暂未完成/再试一次」。修复：有真实追问时从 `result`/正文派生 `missing_information`；有非空正文时校验失败则 coerce（`await_user` 或降为 `completed`）并打 warning，不再失败；工具 schema/prompt 标明 `await_user` 必填非空 `missing_information`。回归见 `group_handoff_test`。

### 群编排内部状态对用户可见（补充，PR #38）

原则：Bot↔Bot 路由、action kind、校验错误、step/task 状态与重试原因不得进入用户 UI。实现：`group_execution_store._public_message_status` 在 commit/interrupt/recover 时，非空正文消息对外 `completed`（步骤仍可失败）；iOS `presentsIncompleteReply` 仅空正文显示失败 footer。历史库中「有正文 + failed」由客户端门控兼容。回归见 `group_execution_store_test` / `GroupMessagePresentsIncompleteReplyOnlyWhenBotContentEmpty`。

### Worker 未加载 .env，私聊回复全部失败（2026-10-15）

现象：私聊「大管家」发送「早上好」得到「⚠️ 模型没有返回内容（已自动重试）」；「调查员」一直显示「排队中」。

根因：`chat_reply_events` 记录的错误是「服务器未配置 DEEPSEEK_API_KEY」。API 由 `start.sh` 启动，会导出 `backend/.env`；chat worker 则在 screen 中直接执行 `python -m verabot.services.chat_tasks`，没有这些变量。`verabot.core.config` 在导入时读取环境变量，因此 worker 中 Key 为空，任务在 1 秒内失败。界面文案把配置错误也显示为「模型没有返回内容」。

修复：新增 `verabot/core/envfile.py`（仅标准库）。`chat_tasks`、`owned_tasks`、`scheduled_tasks` 的 `__main__` 在导入其他模块前调用 `load_env_file()`（不覆盖已导出变量），并 `require("DEEPSEEK_API_KEY")`，缺失时直接退出并提示。回归：`scripts/test/worker_env_test.py`。

### 失败任务在客户端停在「排队中」（2026-10-15）

`APIClient.durableEvents` 用 `bytes.lines` 读 SSE；`AsyncLineSequence` 会丢弃空行，而 SSE 以空行结束一个事件，`DurableSSEParser` 因此从不派发事件。服务端快照已是 `failed`，客户端仍显示「排队中 / 取消排队」与转圈，直到流超时。现改为按字节切行保留空行；解析器在遇到下一条 `id:` 时兜底派发上一事件。回归：`ChatContinuityRegressionTests`。

### 新消息提示规则调整（2026-10-15）

- 「新」分隔线只在进入对话、或从后台回到前台时，标在当时第一条未读回复上方（单条也显示）；正在看对话时到达的回复不显示；离开即清除，看过后再次进入不会再出现（`ConversationReadingSession.dividerMessageID` / `resume`）。
- 去掉 Bot 头像上方的「新消息」标签与「有新回复 ↓」按钮（私聊、群聊）。
- 会话列表的未读数字改为强调色小圆点（无数字，无障碍标签仍读出条数）。

### 打开对话后再次进入仍显示未读（2026-10-15）

现象：「健康助手」回复后列表出现未读，进入对话再离开，再次进入仍显示未读。

原因：已读只靠可见性判定上报（气泡至少 25% 可见并停留 0.5 秒，且需在前台、页面可见）。快速进出、长回复只露出一小部分或滚动位置不在该条时，不会上报，未读一直保留。

修复：`AppState.markConversationRead(kind:id:)` 在进入对话、回到前台、离开对话时，把该对话 `unread_messages` 全部写入本地已读队列（`enqueueRead`）并经 `POST` 已读接口上报；`ConversationActivity.entryReadBatch` 按消息去重并取最高修订。本次进入的「新」分隔线仍按进入前的未读显示一次，下次进入不再出现。回归：`entryReadBatchCoversAllUnreadMessages`。

### Bot 回复错位与回复中可重复发送（2026-10-15）

- `MessageRow` Bot 侧内层 `VStack` 原为 `.trailing` 对齐，操作行比短气泡宽时气泡被推向右侧，与头像之间出现空隙；改为 `.leading`。
- 回复排队 / 生成中允许继续发送并显示「排队中 / 取消排队」。现私聊以 `ChatViewModel.replyInProgress` 判定，输入栏右侧显示停止按钮并拦截发送；群聊以 `GroupChatViewModel.busy` 拦截发送。

### 打开对话后再次进入仍显示未读（2026-10-15）

现象：「健康助手」回复后列表出现未读，进入对话再离开，再次进入仍显示未读。

原因：已读只靠可见性判定上报（气泡至少 25% 可见并停留 0.5 秒，且需在前台、页面可见）。快速进出、长回复只露出一小部分或滚动位置不在该条时，不会上报，未读一直保留。

修复：`AppState.markConversationRead(kind:id:)` 在进入对话、回到前台、离开对话时，把该对话 `unread_messages` 全部写入本地已读队列（`enqueueRead`）并经 `POST` 已读接口上报；`ConversationActivity.entryReadBatch` 按消息去重并取最高修订。本次进入的「新」分隔线仍按进入前的未读显示一次，下次进入不再出现。回归：`entryReadBatchCoversAllUnreadMessages`。

### Bot 回复错位与回复中可重复发送（2026-10-15）

- `MessageRow` Bot 侧内层 `VStack` 原为 `.trailing` 对齐，操作行比短气泡宽时气泡被推向右侧，与头像之间出现空隙；改为 `.leading`。
- 回复排队 / 生成中允许继续发送并显示「排队中 / 取消排队」。现私聊以 `ChatViewModel.replyInProgress` 判定，输入栏右侧显示停止按钮并拦截发送；群聊以 `GroupChatViewModel.busy` 拦截发送。

## 会话列表未读点与时间不对齐（已修复 2026-10-15）

未读点原以 overlay 偏移挂在行右上角，与时间错位。现放入预览行尾部，与时间右缘对齐、垂直居中于预览行。

## 后续再做

这些不在本分支里实现：

- APNs / 远程推送。App 挂起或关掉之后，新的远程消息不会立刻到达。已经排进系统的本地提醒不依赖这条链路。
- 后台刷新。前台大约每 5 秒拉一次通知事件，失败后按 5 / 15 / 30 / 60 秒退避；退到后台后这条循环会停。`BGAppRefresh` 不能当作即时通道。
- 真机锁屏、系统声音、专注模式，以及双设备已读。

## 本环境没有验证

这台 Linux 环境没有 Swift 工具链，也没有 Xcode。`GroupChatView`、`ChatView`、`NotificationEventSync` 的改动没有编译，也没有在模拟器里看过横幅。群聊单元格拆成 `messageCell`，是为了避开 `6bd6062` 修过的类型检查超时，但这里无法确认编译时间。
