# 2026-10-18 「安排」P2：交给 Bot 执行

按已批准方案 [plans/2026-10-18-reminders-todo-tasks-unified.md](../plans/2026-10-18-reminders-todo-tasks-unified.md) 实施 P2：把「交给 Bot 执行」从只读变成可操作。分支 `feat/unified-items-p2`，基于 `main@0d535a8`。

## 后端

- **POST /api/items 带 `task`**（`backend/verabot/services/items/service.py`、`api/routers/items.py`）：可选 `task` 字段，同一请求先创建 scheduled（once/repeat）或 owned（持续）任务，再把 `reminders.task_kind/task_id` 关联到事项。scheduled 需要 `start_at`（带时区偏移）；owned 需要 `completion_criteria` 且沿用「主 Bot + 允许主动任务」检查。关联事项默认 `notify=0`；once/repeat 的事项 due 对齐任务首次执行。幂等：复用同一 Idempotency-Key（事项与任务各自按 Key 去重）。
- **任务操作代理** `POST /api/items/{id}/task/pause|resume|run|stop|continue|input`：内部转给现有 scheduled / owned 服务；按当前版本「最新优先」执行。scheduled 支持 pause/resume/run；owned 支持 stop/continue/input。不暴露 step / lease / token / trace / request_hash / authorization_json。
- **写回同步**（`services/items/sync.py`）：
  - owned 完成 → 事项自动完成（只完成事项，不动任务引擎）。
  - scheduled 删除 / owned 停止 → 事项保留、解除关联，写 `reminder_events`「task_unlinked / 任务已结束」并发出通知。
  - scheduled 每次调度推进 → 事项 due 跟随 `next_run_at_utc`（`services/scheduled_tasks/scheduler.py` 同事务调用）。
- **`propose_task` 工具**（`tools/reminder.py`）：Bot 在对话里提议，冻结参数进 `pending_actions`（kind `propose_task`，复用确认卡片 / SSE `confirmation_required`）；用户点确认后（`services/actions` 的 `confirm` 分支）才创建任务 + 关联事项，`source_kind=chat`。
- **删除语义** `DELETE /api/items/{id}?scope=…&task=stop|keep`：`stop` 先停/删关联任务再取消事项；`keep` 只删事项（任务继续）。
- **§5.2 权限**：沿用 `reminder_scope`（Bot 只能管理自己创建/被指派的事项）；`propose_task` 加入 `REMINDER_TOOLS`（不可委派、需白名单）。

## iOS（VeraBotKit + App）

- **Kit 模型**：`ItemTaskSummary` 增加 `history`（执行记录：时间 + 成功/失败）、`wait_question` / `wait_action_id`；新增 `ItemTaskWrite` 与 `APIClient.itemTaskAction / deleteItem`。
- **ReminderEditorView**：新增「交给 Bot 执行」开关（仅新建）——选择负责 Bot、填写要做什么、执行方式「到点做一次 / 按周期 / 持续直到完成」；持续模式无主动任务权限时给出原因与设置入口。
- **ReminderDetailView**：任务区块改为状态胶囊、下次执行、最近结果 +「查看全文」跳 Bot 私聊对应消息、执行记录；「等你处理」时显示问题 + 回答输入（有操作确认时进 `TaskApprovalView`）；底部提供 暂停/继续、立即执行（周期）、继续/停止（持续）；删除确认提供「删除并停止 Bot 任务」（红）/「仅删除事项」。
- **通知点按**：任务结果通知 → 事项详情；`awaiting_user/awaiting_approval` 时聚焦回答区块（`AppState.pendingItemFocusTask`）。
- **下线 TaskListView**：删除 `TaskListView.swift`、`TaskEditorView.swift`、`ScheduledTaskDetailView.swift` 及其 `project.pbxproj` 引用；对话与 Bot 编辑「任务」入口已在 P1 改为跳「安排」并预筛选 Bot。

## 验证

- `backend/scripts/test/unified_items_p2_test.py`：**全绿**（P2-01 创建+幂等、P2-02 owned 权限、P2-03/05 操作代理、P2-04 停止解除关联、P2-06 写回同步、P2-07 propose_task、P2-08 删除语义、P2-09 §5.2 + 旧接口兼容、P2-10 sql_layer_check）。
- `backend/scripts/test/unified_items_test.py`：**仍全绿**（无回归）。
- `swift test --disable-sandbox`（VeraBotKit）：**388 项 / 3 个 suite 全绿**。
- `xcodebuild`（iPhone 17 模拟器）：**未构建** —— 沙箱拒绝写 `~/Library/Caches/org.swift.swiftpm`（`Operation not permitted`），按约定不申请权限；集成后统一构建。

## 未完成 / 风险

- 任务创建采用「先建任务、再建事项，失败时补偿停止」而非严格同一事务（现有 scheduled/owned 创建函数各自开事务）；写回同步 + 对账兜底（方案 §10 风险 1 已说明）。
- iOS App 目标未在本环境编译（见上），视图改动需集成环境构建确认。
- 未改 CHANGELOG / STATUS / docs README；未合入 main、未推送。
