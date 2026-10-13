# 群聊意图分配与任务交接实现记录

日期：2026-10-13。代码位于独立 worktree：`/Users/admin/.codex/worktrees/group-intent-handoff/VeraBot-v0.1`，起点 `4fc063dd5771eac8dc45851e68163a3551b67b01`。用户已确认完整设计，并授权在本对话实施。主工作区未改动。

> 复审纠正：初轮测试不足以证明完整实现。R01–R16及组合问题已修复，最新状态与手动测试环境见[修复记录](2026-10-13-group-intent-handoff-repair.md)。下文数量为初轮快照。

## 初轮实现

- schema v24 增加持久任务、输入、步骤、澄清、事件和用量表。迁移清除旧 `default_bot_id` 值但保留群、成员、消息和附件。
- 新群协议 v2 用 UUID 提交输入并返回回执；按群内上下文动态选择 Bot。含糊输入由系统挑选澄清成员；澄清负责人、版本与缺失信息在用户回答和服务重启后保留。
- Bot 只能提交受校验的结构化动作。`consult` 结束后回到原负责人，`handoff` 改变任务负责人。单进程后台 worker 与持久事件支持断开观察后继续、游标重放、明确停止、失败步骤重试和恢复。
- iOS 改用回执/任务/事件协议；请求不确定时用同一个 UUID 查回执并重试。离开页面只取消观察，不发送停止；SQLite 在同一事务保存执行快照、cursor 和消息。创建/设置页移除默认回应者，点名保留选择顺序，everyone 清掉显式目标，回复动作带真实消息 ID；清除旧本地点名偏好。
- 旧群写入入口返回 426，历史读取保持可用。当前后端部署只支持一个 API 进程；不能启动多个副本共享本地 worker。

## 自动化验证

后端临时 SQLite 用例：migration 2、execution store 6、clarification 8、routing 3、handoff 10、worker 6、execution API 8、原群存储 14 均通过。旧 request-bound runtime/lifecycle 用例已改为验证旧写路径被 426 拒绝，和新 worker 测试分层。

本地临时服务 `127.0.0.1:8093` 使用 fake provider 跑 socket/SSE：无默认回应者创建、旧协议 426、重复 UUID 回执、背景 worker、澄清同一负责人、断开 observer 后完成和事件重放、咨询 A→B→A、交接由 B 完成、等待澄清可停止，均通过。测试使用 `/tmp/verabot-group-intent-handoff-final`，未连接现有开发/生产数据库，也未请求真实模型。

Swift Package 完整测试 **241 项 Swift Testing + 1 项 XCTest 通过**。XcodeBuildMCP 的 VeraBot scheme iOS Simulator Debug 最终构建 **BUILD SUCCEEDED**，无 warnings/errors。没有启动应用做点按，也没有运行真机验收。

## 用户验收边界

设计验收项 1–10 当前记录如下。自动用例只支撑对应代码路径，不代替真实模型质量和用户设备验收。

| # | 验收点 | 自动化证据 | 用户/真实环境状态 |
|---|---|---|---|
| 1 | 新旧群无默认回应者，路由故障/成员变化/重启不回退 | v24 迁移、旧 JSON 解码、无默认字段请求测试通过 | **Not-triggered**：真实库迁移及应用重进 |
| 2 | 意图清楚时选人，意图不足时由 Bot 澄清 | route/clarification 测试及 fake HTTP 澄清通过 | **Not-triggered**：真实模型分配与追问质量 |
| 3 | 连续回答/页面重进/服务重启保持同一负责人 | 持久化 owner 与回执测试通过 | **Not-triggered**：双设备竞争和真实重启体验 |
| 4 | 信息充分后停止澄清，并带全需求继续任务 | v2 请求带 clarification/task/version；HTTP 跟进通过 | **Not-triggered**：真实换题/补充资料场景 |
| 5 | 点名、换题、停止和成员不可用正确改向 | 成员目标编码、停止版本与成员隔离测试通过 | **Not-triggered**：实际 UI 和删除成员交互 |
| 6 | 多人点名顺序、everyone 覆盖、单次执行结束 | 顺序/去重/everyone 单测通过；runtime 每步单成员 | **Not-triggered**：键盘和点名现场操作 |
| 7 | consult 返回原负责人，handoff 改变负责人，正文提名不调度 | 结构化动作测试与 localhost A→B→A / handoff 通过 | **Not-triggered**：真实模型协作质量 |
| 8 | 停止、并发新指令、迟到事件、恢复不重复执行 | worker fencing、UUID、event cursor、显式 stop 测试通过 | **Not-triggered**：真实设备离开/后台/并发操作 |
| 9 | 调用预算/超时/用量记录，未知值保持未知 | worker/handoff/API 与主链路额度测试通过 | **Not-triggered**：真实 provider usage 与长任务体验 |
| 10 | 群成员/历史/附件隔离，不获得私聊或额外工具权限 | 用户隔离、群内上下文和引用校验测试通过 | **Not-triggered**：真实账号与附件验收 |

`sql_layer_check.py` 仍因仓库已有 services 层 SQL 报失败；本轮扫描的群聊新增文件没有 SQL-LAYER 命中。该全仓检查不构成此次群聊实现的通过项。

## 部署与回滚提醒

部署前先备份数据库；在副本验证 v23→v24、重复初始化幂等、群/成员/消息/附件计数和旧数据可读。先部署支持协议 v2 的单进程后端，再发布 v2 iOS 客户端；旧客户端写请求会收到 426。若回滚代码，应保留 v24 数据备份，不要尝试用旧版本启动新库，先恢复兼容的服务代码/库快照。正式数据库迁移尚未执行。

实现计划：[2026-10-12 群意图与交接计划](../superpowers/plans/2026-10-12-group-intent-and-handoff.md)；确认设计：[设计稿](../superpowers/specs/2026-10-12-group-intent-and-handoff-design.md)。
