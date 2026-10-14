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

PR #35 已合入 UI 层 10 Bot / 群聊 2～5 限制。PR #36 跟进：去掉助理列表「我的 Bot（n/10）」展示与创建群聊底部提示卡片（说明改 footer）。规格与变更记录见 [bot-limits](../superpowers/specs/2026-10-14-bot-limits.md)。群成员增删 UI 仍不存在。

## 后续再做

这些不在本分支里实现：

- APNs / 远程推送。App 挂起或关掉之后，新的远程消息不会立刻到达。已经排进系统的本地提醒不依赖这条链路。
- 后台刷新。前台大约每 5 秒拉一次通知事件，失败后按 5 / 15 / 30 / 60 秒退避；退到后台后这条循环会停。`BGAppRefresh` 不能当作即时通道。
- 真机锁屏、系统声音、专注模式，以及双设备已读。

## 本环境没有验证

这台 Linux 环境没有 Swift 工具链，也没有 Xcode。`GroupChatView`、`ChatView`、`NotificationEventSync` 的改动没有编译，也没有在模拟器里看过横幅。群聊单元格拆成 `messageCell`，是为了避开 `6bd6062` 修过的类型检查超时，但这里无法确认编译时间。
