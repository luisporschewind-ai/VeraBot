# 2026-10-14 集成：对话持续执行与本地通知

基线 `origin/main` `5a91461`。三条未完成分支合入 `integration/2026-10-14`，没有合并进 main。

## 纳入

- `wip/main-uncommitted`（`c9d7bd8`）：会话列表共用 `ConversationRowHeader`；群设置、连接器令牌、通知实验室的关闭入口改为 `DismissToolbarButton`。设计文档保留。列表时间优先用会话活动里的最新消息时间，避免和旧时间标签重复。
- `codex/chat-continuity`（`988a86a`）：私聊持久回复任务、独立 worker、回执与检查点、会话未读和列表工作状态。
- `codex/local-notifications`（`b91dcf2`）：提醒排程修正、持久通知事件、前台同步、任务结果分类。

## 集成时补上的缺口

- 两条分支都占用 schema v30。对话持续执行保持 v30，通知事件顺延为 v31。Worker 在 schema 低于 31 时拒绝启动，避免缺列后继续跑。
- `add_message` 同时支持调用方事务和会话代次。
- 旧 `/chat` 在成功结束时，与助手消息同一事务写入一条 `bot_message`。
- 持久回复在完成、等待补充、等待确认、失败、中断时写 `bot_message`；用户主动停止不发。通知失败只回滚通知保存点，不撤销已发布回复。
- 主 Bot 任务结果用 `task_result`，中间步骤不再另发「任务有新进度」。会话清空后的旧代次结果不写回新会话，也不再响一次。
- 对话页同时保留未读标签、可见后已读，以及通知用的可见消息区域。

## 留到后面

- APNs，以及 App 挂起或关闭期间新远程消息的即时触达。本地已排提醒不依赖这条链路。
- 后台刷新任务。前台约每 5 秒拉一次事件，失败按 5/15/30/60 秒退避；退后台后这条循环会停。
- 计划中的 `chat_continuity_http_test.py`、真实 socket 断开和常驻进程监督没有写。现有回归使用假模型和临时库。
- 群聊页没有把当前可见消息交给通知同步。人在群聊里时，前台仍可能弹出该群回复的提示。
- 真机锁屏、系统声音、专注模式、双设备已读，以及 iOS 模拟器构建。本环境没有 Swift 工具链，也没有 Xcode。

## 自动测试

在 `backend/` 用独立进程跑离线脚本（这个仓库的脚本在 import 时各自建库，不能放进同一次 `pytest` 收集）。57 个脚本通过。`scheduled_task_executor_test.py` 需要 `PYTHONPATH=.`，通过。`sql_layer_check.py` 仍失败，失败点在未改动的 `services/memory/` SQL，不是这次集成引入的。

跳过：`smoke_test.py`、`web_browser_test.py`、`web_query_test.py`、`mcp_oauth_test.py`、`group_http_test.py`、`group_execution_http_test.py`。这些脚本依赖真实模型、浏览器或已经启动的 HTTP 服务。

`uv run --with pytest pytest` 在收集阶段中断：多个脚本共用一个解释器时会抢同一个数据库路径。这是原有跑法限制，单脚本结果以上面为准。

Swift Package 与 iOS 工程没有编译。
