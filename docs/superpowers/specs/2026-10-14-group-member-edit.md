# VeraBot V0.1：已有群聊增删 Bot 成员（2026-10-14）

## 目标

在群设置页支持向已有群聊添加 / 移除 Bot 成员。产品上限仍由 UI（`BotProductLimits`：每群 2～5 个 Bot）约束；服务端只做归属与空群防护，不引入与创建页不一致的硬产品上限。

## 范围

| 做 | 不做 |
|---|---|
| `POST/DELETE /api/groups/{id}/members` | 改 schema / 迁移 |
| `group_store` 增删成员（SQL 仅在 `db/`） | 改 orchestrator / routing / worker 逻辑 |
| 群设置「添加 Bot」与成员滑动删除 | 自动踢人、自动补员、批量成员 PATCH |
| VeraBotKit API / ViewModel / 离线后端测试 | 本机 Swift 构建（Cloud VM 无 Xcode） |

成员变更对**下一条消息**生效；进行中的任务 / turn 不中断、不重算。

## 现状（实施前只读）

- `chat_group_members` 已有；`UNIQUE(group_id, bot_id)`；消息/步骤对 `member_id` 为 `ON DELETE SET NULL` → 硬删成员行无需改表。
- `GroupUpdateRequest` / `GroupPatchIn` 仅改名；`GroupInfoView` 成员区只读展示；`BotProductLimits.canAddMember` / `canRemoveMember` 已预留。
- 创建契约服务端仍为 2～4（历史）；产品 UI 为 2～5。本功能服务端**不加**「最多 5」硬限制。

## API

均需 `X-VeraBot-Group-Protocol: 2`；租户校验；他人群 404。

| 方法 | 路径 | 请求 | 成功 |
|---|---|---|---|
| POST | `/api/groups/{id}/members` | `{ "bot_id": int }` | 200，完整群对象 |
| DELETE | `/api/groups/{id}/members/{member_id}` | — | 200，完整群对象 |

校验：

- 添加：群存在；Bot 属当前用户；该 Bot 尚非本群成员。
- 移除：成员属于本群；若该成员仍绑定 `bot_id`，且是群内最后一个仍绑定 Bot 的成员 → 422（防空群）；历史不可用成员（`bot_id` 已空）可移除。
- **不**因 `group_busy` 拒绝；不取消进行中任务。
- **不**强制 2～5 产品窗（UI 负责）；服务端唯一人数相关规则是「不能删光最后一个仍绑定的 Bot」。

## UI（`GroupInfoView`）

Boss 参考（群信息页成员卡，三张截图）：成员行 = 头像 + 名称 + chevron；同卡最后一行为蓝色 `person.badge.plus` + **「添加成员」**；成员行左滑露出红色 **minus.circle** 破坏性按钮；点按后系统确认框标题 **「移除 {Name}？」**，正文 **「该成员将离开此群聊。Bot 本身会保留。」**，按钮 **取消** / 红色 **移除**。交互对齐该参考；不改群设置页其余区块布局。

- 成员区标题继续用 `BotProductLimits.botMemberCount`（只计 `botID != nil`）。
- 「添加成员」行：打开多选 sheet（checkmark，风格对齐 `CreateGroupSheet`，**无底部 footer 说明**）；仅未入群 Bot 可选；`current + selected` 达 5 时禁用继续勾选；「添加」在已选 ≥1 时可用。确认后顺序 `POST`；部分失败保留已成功成员并以 `ConnectionNotice` 提示；成功用 `withAnimation` 写入列表。历史 >5 可查看、禁止再加、不自动踢人；\<2 不自动改成员。
- 成员行：左滑按钮 **非** `role: .destructive`（避免确认前移走行），显式 `.tint(.red)` 保持红色敏感样式 → 确认后再调 API；成功后 `withAnimation` 移除该行；取消则行保留。`canRemoveMember` 为 false 时不可删仍计为 Bot 的成员；不可用成员可删。
- 成功后刷新当前群模型，并尽量同步列表/本地缓存；API 失败不丢已成功变更，错误走 `app.message(for:)` / `ConnectionNotice`。

## 边界与测试

| 场景 | 期望 |
|---|---|
| 添加本人未入群 Bot | 成功，成员列表含新成员 |
| 添加他人 Bot / 已是成员 / 不存在群 | 422 / 422 / 404 |
| 移除倒数第二个仍绑定 Bot | 成功 |
| 移除最后一个仍绑定 Bot | 422 |
| 移除不可用成员 | 成功 |
| 讨论进行中增删成员 | 允许；进行中任务不受影响 |
| 历史 >5 | UI 禁止添加；服务端仍可添加（本 PR 不测服务端强加 5） |
| Kit | 请求编码与 API 路径；`BotProductLimits` 成员边界（已有） |

## 变更记录

### 2026-10-14 · 首版实现

- 后端：`group_store.add_member` / `remove_member`；路由与 `GroupMemberAddIn`；`group_store_test` 增删回归。
- iOS：API / ViewModel / `GroupInfoView`（Boss 参考：同卡「添加成员」、左滑 `minus.circle`、确认「移除 {Name}？」）+ 添加 sheet；Kit 契约 / ViewModel 测试。
- 文档：本规格；`CHANGELOG` / `STATUS`；`bot-limits` 变更记录补「成员编辑已接线」。无 schema / Runtime / orchestrator 改动。

### 2026-10-14 · 移除确认与动画修复（`fix/group-member-remove`）

- 左滑按钮去掉 `role: .destructive`，显式 `.tint(.red)` 保持红色敏感操作样式；确认框点「移除」后才请求 API；「取消」保留该行。
- `removeMember` / `addMember` 先返回服务端群快照、不立刻改 `group`；视图在成功后 `withAnimation { applyGroup }` 做 List 原生增删动画；失败保持原列表（添加则为部分成功后的快照）并提示错误。
- 添加成员 sheet：去掉底部 hint/footer；改为多选 +「添加」；`addMembers` 顺序 POST，部分失败保留成功项。
- 同 PR：未读「新」分隔线样式对齐 Boss 参考（见 [chat-continuity](2026-10-14-chat-continuity-design.md) 变更记录）。
- 群设置页：顶部居中群头像；去掉「群聊名称」分区标题；群名输入居中、加粗、字号大一号。
- 同 PR 后端：`await_user` + 空 `missing_information` 在已有正文/追问时 coerce，不再把完整回复标失败（见 known-issues）。

### 2026-10-14 · 添加成员 sheet 行高对齐

- `AddGroupMemberSheet` 候选行与 `GroupInfoMemberRow` 一致：头像 30、`HStack` spacing 10、`listRowInsets(top/bottom: 2, leading/trailing: 20)`。

### 2026-10-14 · 编排内部不对用户暴露（公开消息状态）

Boss 原则：Bot↔Bot 群编排内部（路由、action kind、校验错误、step/task 状态、重试原因）不得出现在用户可见 UI。

- 后端：`commit_step` / `interrupt_step` / `recover_interrupted` 经 `_public_message_status`：步骤可为 `failed`/`interrupted`/`stopped`，但消息有非空正文时对外 `status=completed`。
- iOS：`GroupMessage.presentsIncompleteReply`——仅 bot 且非 completed/streaming、且去空白后正文为空时，才显示「回应暂未完成 / 再试一次」与警告头像；有可用正文则按正常回复渲染。`canRetry` 同步门控。
- 规格见 [bot-group-chat-design](2026-10-11-bot-group-chat-design.md) §6.1 / §5、[intent-handoff](2026-10-12-group-intent-and-handoff-design.md) §5.3 / §10。
