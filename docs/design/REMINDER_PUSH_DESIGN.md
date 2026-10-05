# 提醒与推送模块设计 (Reminder & Push/Notification Design) — v1.0 定稿

> 状态：**v1.0 定稿**（Boss 于 2026-10-03 批准，§15 D1–D18 全部按推荐执行）。按 §14 R1 实施。
> 实施与验收：**R1 已实现并合入 main（schema v11）**；Boss 于 2026-10-04 验收通过（模拟器）。点按提醒通知按 §9.5 执行（打开该提醒，不直接进对话），已按设计接受。真机与 APNs (R2) 未测。
> 依据代码：`luisporschewind-ai/VeraBot` `main`（含缓存修复 `2a0dc0f` 之后的 main；`SCHEMA_VERSION = 9`），并参考未合并的 PR #6（头像）、**PR #7（插件 P1，schema v10，`builtin_reminder` 插件）**、PR #8（邮箱认领修复，schema 仍 v9）。
> schema 版本取合并时下一个可用号：PR #7 占 v10，本方案预计 **v11**（若届时 v10 未合并，则顺延到合并时的下一个号）。
> 目标路径：`docs/design/REMINDER_PUSH_DESIGN.md`。与实现代码在同一个 PR 里提交。
> 本文时间默认 Asia/Shanghai (UTC+8)。

## 0. 一页摘要 (TL;DR)

- **两层**：上层「提醒（Reminder）」是一种业务对象；下层「通知（Notification）」是通用投递层，提醒、Bot 主动消息、委派完成、插件 / MCP 事件、系统公告都走同一套：**通知记录 → 偏好 / 免打扰 / 限流判定 → 投递（站内收件箱 / 本地通知 / APNs）→ 投递状态**。
- **提醒状态机**（存储态）：`scheduled`（待提醒）→ `due`（已到时，界面显示「逾期」）→ `done` / `snoozed` / `missed` / `cancelled`。重复提醒在每次完成 / 错过后自动推进到下一次，保持 `scheduled`。
- **谁能做什么**：用户可以对自己的全部提醒做任何操作；Bot 只能管理**自己创建的**和**用户指派给它的**提醒；取消、批量、改重复规则、本轮读过外部（MCP）内容后的写操作，需要用户在确认卡片（HITL）上点确认；被委派的 Bot 不能读写提醒。服务器（system）只负责到时、错过、推进重复。
- **投递**：R1 只用 **iOS 本地通知（UNUserNotificationCenter）**，App 关着也会按时响，不依赖 APNs、不需要付费开发者账号。APNs 放到后面，并先用模拟器 `simctl push` 验证客户端处理。
- **分期**：R1 提醒 + 本地通知 + 站内通知中心（约 5 人日）→ R2 确认卡片、对话回流、委派完成通知、APNs 客户端预备（约 4 人日）→ R3 APNs 真推送（需 Boss 的付费开发者账号）→ R4 Bot 主动消息 / 定时任务、插件事件。
- **决定**：§15 D1–D18 已于 2026-10-03 由 Boss 全部按推荐批准。

---

## 1. 现状盘点 (As-is inventory)

| 位置 | 现状 | 问题 / 影响 |
|---|---|---|
| `db/schema.py` `reminders` 表 | `id, user_id, bot_id (ON DELETE SET NULL), content, due_at TEXT, done INTEGER, created_at` | 没有状态、时区、重复、备注、来源、更新时间；`done` 只有 0/1 |
| `tools/reminder.py` `create_reminder` | `content` + 可选 `due_at`；`_normalize_due` 解析失败时**原样保存模型给的文本** | `due_at` 可能不是 ISO 时间；不校验过去时间；不去重（模型重试会重复创建）；入库截断 500 字但返回未截断原文 |
| `tools/reminder.py` `list_reminders` | 列出**该用户全部**未完成提醒 | 任何有此工具的 Bot 都能看到其他 Bot 建的提醒，与多 Agent「上下文隔离」不一致 |
| 排序 | `ORDER BY COALESCE(due_at,'9999')`（字符串比较） | 带不同 UTC 偏移（`+08:00` / `+00:00`）或原文时排序错误 |
| `api/routers/reminders.py` | `GET /api/reminders`（含已完成，无分页）、`POST /api/reminders/{id}/done` | 用户不能新建、修改、删除、稍后、撤销完成 |
| `agents/prompts.py` | 系统提示已注入当前时间与时区 `TIMEZONE`；规则「用户要求提醒/待办时调用 create_reminder 或 list_reminders」 | 可继续用于解析「明天下午三点」 |
| 权限 | `allowed_tools` 白名单（`create_reminder`、`list_reminders` 各一个开关）；v2 迁移给存量 Bot 授予了这两个工具 | 没有「管理」类工具 |
| PR #7（插件 P1） | 内置插件 `builtin_reminder`（不可卸载），工具 `create_reminder`、`list_reminders`；`GET /api/tools` 加 `plugin_id` | 新工具 `manage_reminder` 需加入 `builtin_reminder.tools` 和 iOS 插件详情的工具清单 |
| `pending_actions` 表（v7 建，未使用） | `kind, payload_enc, payload_hash, status, expires_at…` | 可作为 Bot 危险操作的确认卡片（HITL）载体，与 MCP M3 共用 |
| `audit_log` | 工具越权等审计 | 提醒的操作历史需要单独的事件表 |
| iOS `RemindersView` | Tab 页；平铺列表；左滑「完成」；时间用字符串切片显示；空状态「在对话里说『提醒我…』即可创建」 | 无分组、无新建 / 编辑、无筛选；时间不按时区换算 |
| iOS `Reminder` 模型 | `id, content, dueAt, done: Int, botName` | 需扩展；`done` 保留兼容 |
| iOS 设置 › 通用 › 通知 | 开关只申请系统授权并存 `@AppStorage`，**不发任何通知** | 本方案让它真正生效 |
| 推送 | 无 APNs、无设备注册、无站内通知；后端无后台调度器（只在 `startup` 里 `init_db`） | 需新增调度器 |
| Keychain | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | 通知动作在后台执行时可读令牌，满足要求 |
| 后端依赖 | 无 `python-dateutil`；`httpx` 未开 HTTP/2 | RRULE 与 APNs 需要依赖决策（§15 D16、D17） |
| Web | 冻结 | 只保留旧接口兼容 |

## 2. 目标与非目标 (Goals / Non-goals)

**目标**
1. 用户和 Bot 都能创建提醒；用户可在 iOS 原生界面完整管理；Bot 在权限内管理。
2. 清晰的状态机，任何状态变化可追溯（谁、何时、从哪里）。
3. 提醒在 App 关闭时也能按时响（本地通知），通知上可直接「完成 / 稍后」。
4. 一个通用通知层，统一偏好、免打扰、限流、去重、收件箱、深链接、投递状态，为 APNs 和其他来源预留。
5. 账号隔离：通知、设备、离线队列都按用户隔离，退出即清除。
6. R1 不依赖 APNs 和付费开发者账号。

**非目标（本期不做）**
- 中国法定节假日 / 调休；位置提醒；与 iOS 系统「提醒事项」（EventKit）同步；共享提醒给他人。
- Bot 到点自动执行任务（如每天 8 点自动查天气后告诉我）——放到 R4，见 D12。
- 时间敏感通知（Time Sensitive）、通知服务扩展（Notification Service Extension）——都要改 entitlements / 新 target，即改 `project.pbxproj`，先不做。
- Web 推送；Web 端任何新界面（Web 冻结）。

## 3. 概念模型 (Concept model)

```
User ─┬─ Reminder (系列) ──< ReminderEvent (操作 / 发生记录)
      │       │ 到时
      │       ▼
      ├─ Notification (通用通知记录，收件箱一行) ──< NotificationDelivery (每个渠道 / 设备一条)
      ├─ NotificationPrefs (总开关、分类、按 Bot 静音、免打扰、预览)
      └─ PushDevice (设备 + APNs token，R3 才真正发送)
```

### 3.1 提醒字段 (Reminder)

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | int | |
| `user_id` | int | 所有查询必须带 |
| `title` | text ≤ 200 | 标题（原 `content` 迁移而来；旧字段 `content` 继续返回同值，兼容 Web） |
| `note` | text ≤ 2000，可空 | 备注 |
| `due_at` | ISO 8601 带偏移，可空 | 本次触发时间（本地墙钟 + 偏移，如 `2026-10-04T09:00+08:00`）。空 = 无日期待办 |
| `timezone` | IANA，默认 `Asia/Shanghai` | 重复提醒按此时区推算（墙钟不漂移） |
| `due_utc` | ISO UTC，可空 | 由 `due_at` 计算，**排序、调度只用它** |
| `all_day` | bool | 全天提醒（默认触发时间 09:00，见 D5） |
| `rrule` | text，可空 | RRULE 子集（§3.2） |
| `series_end` | 计数 / 截止 | 由 rrule 的 `COUNT` / `UNTIL` 决定，`occurrence_index` 记录第几次 |
| `status` | enum | §4 |
| `snoozed_until` | ISO，可空 | `snoozed` 时有值 |
| `priority` | 0 无 / 1 低 / 2 中 / 3 高 | 只影响排序和标识，不影响通知强度 |
| `created_by` | `user` / `bot` | 创建者类型 |
| `source_bot_id` | int，可空 | 创建它的 Bot（`created_by=bot`）；Bot 删除后为 NULL |
| `assignee_bot_id` | int，可空 | 「归属 Bot」：用户可把自己建的提醒指派给某个 Bot，让它可见 / 可管理（Bot 创建的默认指派给自己）。现有 `bot_id` 列即迁移为此含义 |
| `source_message_id` | int，可空 | 创建它的那条对话消息（`ON DELETE SET NULL`，清空对话后断链） |
| `client` | `ios` / `web` / `chat` / `notification` | 最后一次修改来源（审计用） |
| `notify` | bool，默认 true | 是否发通知（无日期待办总是 false） |
| `alert_offsets` | JSON 分钟数组，默认 `[0]` | 提前提醒（R2 开放，如 `[-10, 0]`） |
| `version` | int | 乐观锁；每次修改 +1，PATCH 带 `expected_version`，不符返回 409 |
| `completed_at` / `cancelled_at` / `updated_at` / `created_at` | ISO | |
| `done` | 0/1 | **兼容字段**，`status='done'` 时为 1（Web / 旧客户端） |
| 标签 tags | — | **不做**（D14）。需要时 R4 再加 |

### 3.2 重复规则 (RRULE 子集)

只支持 RFC 5545 的一个子集，服务端校验，不支持的直接 422：

| 用途 | RRULE |
|---|---|
| 每天 / 每 N 天 | `FREQ=DAILY;INTERVAL=N` |
| 工作日（周一至周五，不含调休） | `FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR` |
| 每周几 | `FREQ=WEEKLY;BYDAY=SA` / `INTERVAL=2` |
| 每月几号 | `FREQ=MONTHLY;BYMONTHDAY=15`（31 号在小月跳过，与 RFC 一致；界面提示） |
| 每年 | `FREQ=YEARLY` |
| 结束 | `COUNT=n` 或 `UNTIL=…`（二选一） |

- 下次时间只在**服务端**计算，接口返回 `next_fires`（未来 N 次），iOS 不实现 RRULE，避免前后端算法不一致。
- 实现：引入 `python-dateutil` 的 `rrulestr` 并加白名单校验（D16 已定，2026-10-03）。
- 界面 R1 提供预设（永不 / 每天 / 工作日 / 每周 / 每月 / 每年），R2 提供「自定义」。

### 3.3 通知字段 (Notification，通用)

| 字段 | 说明 |
|---|---|
| `id`, `user_id` | |
| `category` | `reminder` / `bot_message` / `delegation` / `plugin` / `system` |
| `title`, `body` | 已按隐私规则（§9.6）处理过的展示文本 |
| `sensitive` | bool；为真时任何推送载荷都不带正文 |
| `bot_id`, `reminder_id`, `message_id`, `plugin_id` | 来源引用，均可空 |
| `link` | 应用内深链接（§9.5），如 `reminder/12`、`bot/3/chat?message=55` |
| `dedupe_key` | 同一用户内唯一，如 `reminder:12:2026-10-04T01:00Z`（§9.4） |
| `thread_id` | 通知分组（iOS `threadIdentifier` / APNs `thread-id`），如 `bot-3`、`reminders` |
| `created_at`, `read_at`, `opened_at`, `expires_at` | 已读 / 打开 / 过期（默认保留 30 天，D11） |

### 3.4 投递记录 (NotificationDelivery)

每条通知 × 每个渠道 / 设备一行：`notification_id, channel (inbox / local / apns), device_id, state, attempts, last_error, apns_id, scheduled_for, sent_at, delivered_at, opened_at`。状态见 §9.3。

## 4. 提醒状态机 (Reminder state machine)

### 4.1 状态

| 存储状态 | 中文 | 含义 |
|---|---|---|
| `scheduled` | 待提醒 | 有 `due_at` 且未到；或无日期待办（`due_at` 为空，界面分组「无日期」） |
| `due` | 已到时 | 已到 `due_at` 但用户还没处理。**界面称「逾期」**（overdue 是 `due` 的显示，不另存） |
| `snoozed` | 稍后 | 用户 / Bot 推迟到 `snoozed_until` |
| `done` | 已完成 | 终态（一次性）；可「撤销完成」回到 `scheduled` / `due` |
| `missed` | 已错过 | 到时后超过宽限期仍未处理（系统判定）；仍可完成或改期 |
| `cancelled` | 已取消 | 软删除；保留 30 天可恢复，之后清理（D7） |

「响铃中 firing」不是状态，而是一次**事件**：`scheduled/snoozed → due` 的那一刻产生 `fired` 事件和一条 `reminder` 类通知。

### 4.2 转换表

| # | 从 → 到 | 触发 | 用户 | Bot | 系统 | 备注 |
|---|---|---|---|---|---|---|
| T1 | (新) → `scheduled` | 创建 | ✅ | ✅ `create_reminder` | — | 过去时间 → 422（容差 1 分钟） |
| T2 | `scheduled` → `due` | 到 `due_utc` | — | — | ✅ 调度器 | 产生 `fired` 事件 + 通知 |
| T3 | `snoozed` → `due` | 到 `snoozed_until` | — | — | ✅ | 同上 |
| T4 | `scheduled`/`due`/`missed` → `snoozed` | 稍后 | ✅ 列表 / 通知动作 | ✅ 自己的（`manage_reminder`） | — | 稍后时长见 D5；不改 `due_at` 本身 |
| T5 | `scheduled`/`due`/`snoozed`/`missed` → `done` | 完成 | ✅ | ✅ 自己的 | — | **重复提醒**：记录本次 `completed` 事件，推进到下次 → 仍为 `scheduled`；系列结束才是 `done` |
| T6 | `due`/`snoozed` → `missed` | 宽限期到 | — | — | ✅ | D4：一次性 24 小时；重复提醒到下一次或 24 小时取较早；重复提醒记录 `missed` 事件后推进 |
| T7 | 任意非 `cancelled` → `cancelled` | 取消 / 删除 | ✅（重复提醒问「仅这一次 / 整个系列」） | ✅ 自己的，**需确认卡片** | — | 「仅这一次」= `skipped` 事件 + 推进，不进入 cancelled |
| T8 | `done` → `scheduled`/`due` | 撤销完成 | ✅ | ✅ 自己的、24 小时内 | — | 按 `due_at` 与当前时间决定 |
| T9 | `missed` → `scheduled` | 改期 | ✅ | ✅ 自己的 | — | 改 `due_at` 即可 |
| T10 | `cancelled` → 原状态 | 恢复 | ✅（30 天内） | ❌ | — | |
| T11 | 任意 → 同状态 | 编辑标题 / 备注 / 优先级 / 时间 / 归属 | ✅ | ✅ 自己的（改重复规则需确认） | — | 改时间：`due`/`missed` 若新时间在未来 → `scheduled` |
| T12 | `scheduled` (重复) → `scheduled` | 跳过本次 | ✅ | ✅ 自己的 | — | `skipped` 事件 |
| T13 | 硬删除 | 清理 | — | — | ✅ cancelled 满 30 天 | 删除用户时级联 |

非法转换返回 409 `invalid_transition`（如对 `cancelled` 点完成）。所有转换在单个 SQLite 事务里用「比较后更新」（`UPDATE … WHERE id=? AND user_id=? AND status IN (…) AND version=?`），调度器和用户同时操作时只有一方成功。

### 4.3 状态图

```
              create
                │
                ▼
   ┌──────► scheduled ──到时──► due(逾期) ──宽限期──► missed
   │  撤销完成 │  ▲  │            │  │                 │
   │          │  │  └─稍后─► snoozed ◄─稍后─┘           │
   │          │  └──到时(snoozed_until)──┘ (回到 due)   │
   │          │              完成 │ 完成                │ 完成/改期
   └──────── done ◄──────────────┴────────────────────┘
   任意 ──取消──► cancelled ──恢复(30天)──► 原状态
   (重复提醒：完成/错过/跳过 → 推进 due_at → scheduled；系列结束 → done)
```

### 4.4 显示分组（iOS）

逾期（`due`）→ 今天（`scheduled`/`snoozed`，今天内）→ 即将（之后）→ 无日期 → 已错过（`missed`，最近 30 天）→ 已完成（最近 30 天，默认折叠）。组内按 `due_utc`、优先级、`id`。

## 5. Bot 权限模型 (Bot permissions)

### 5.1 工具

| 工具 | 说明 | 开关 |
|---|---|---|
| `list_reminders` | **改**：默认只返回本 Bot 可见的提醒（§5.2）；可选参数 `status`、`range`（today / week / all）、`limit ≤ 50` | 已有 |
| `create_reminder` | **扩展**：`title`（兼容旧参数 `content`）、`note`、`due_at`、`repeat`（预设名或 RRULE）、`priority`。时间无法解析 / 已过去 → 返回 `error` 让模型追问，**不再存原文**。同一轮同一 Bot 标题 + 时间相同的提醒去重（返回已有 id） | 已有 |
| `manage_reminder` | **新增**，一个开关：`action ∈ update / complete / snooze / reopen / skip / cancel`，`id` 或 `ids`（批量 ≤ 20） | 新增「管理提醒」 |

- 三个工具都属于内置插件 `builtin_reminder`（PR #7 的目录项 `tools` 追加 `manage_reminder`），在 Bot 详情「工具权限」里按工具开关，插件页提供跳转（与 Boss Q4 决定一致）。
- 新建 Bot：默认不授予（最小权限，与现有规则一致）。存量 Bot：**不自动授予** `manage_reminder`（D3）。

### 5.2 可见与可管理范围

| 提醒 | 该 Bot 可见 (`list`) | 该 Bot 可管理 |
|---|---|---|
| 本 Bot 创建的 | ✅ | ✅ |
| 用户指派给本 Bot 的（`assignee_bot_id = 本 Bot`） | ✅ | ✅ |
| 其他 Bot 创建 / 指派的 | ❌（D1；可选 R3 的「可查看全部提醒」开关） | ❌ |
| 用户自建且未指派 | ❌ | ❌ |
| 已取消 | ❌ | ❌ |

越权时工具返回统一的「提醒不存在」（不泄露他人数据），并写 `audit_log`（`tool_denied`，`reason=reminder_scope`）。

### 5.3 确认（HITL）规则

| 操作 | 是否需要用户确认 |
|---|---|
| 创建（单条） | 否；对话里显示提醒卡片，带「撤销」「编辑」（R2） |
| 完成 / 稍后 / 改时间 / 改标题（单条，自己的） | 否 |
| 取消（删除） | **是** |
| 批量（≥ 2 条的任何写操作，含一轮内连续创建超过 3 条） | **是** |
| 修改重复规则 / 取消整个系列 | **是** |
| 本轮已读过 MCP / 插件外部结果（`turn.untrusted_tainted`）后的任何写操作 | **是**（防提示注入替用户建 / 删提醒） |

- 实现：写入 `pending_actions`（`kind='reminder'`，载荷加密），工具返回 `{"status":"pending_confirmation","pending_id":…}`，iOS 在对话里显示确认卡片，用户点「确认」后 `POST /api/pending-actions/{id}/confirm` 才执行；10 分钟过期。与 MCP M3 的确认卡片共用同一套接口和卡片组件，提醒是首个使用者（R2）。
- R1 不实现确认卡片，因此 **R1 的 `manage_reminder` 只开放 `update / complete / snooze / reopen / skip` 的单条操作**，`cancel` 和批量在 R2 随确认卡片开放。

### 5.4 委派与其他规则

- 被委派的 Bot（`depth ≥ 1`）**不能读写提醒**（与记忆规则一致，D13）；需要时由发起委派的 Bot 拿到答复后自己创建。
- 每轮每个 Bot 最多 5 次提醒写操作；每个用户最多 500 条未结束提醒、每个 Bot 50 条，超过返回中文错误。
- Bot 删除：提醒保留，`source_bot_id` / `assignee_bot_id` 置空，显示「来自已删除的 Bot」，归用户管理。
- 清空对话：提醒保留，`source_message_id` 断链。
- 关闭 Bot 的提醒工具：不影响已有提醒和通知。
- 提示词规则更新：创建前确认时间；没有明确时间可建无日期待办；不要重复创建；修改 / 取消用 `manage_reminder`；需要确认时提示用户点卡片，确认前不要说「已删除」。

## 6. 数据结构与迁移 (Schema v11)

> 沿用 `_add_column` + `CREATE TABLE IF NOT EXISTS` 的幂等写法；迁移前自动备份 `verabot.db.bak-before-v11-<时间戳>`。不改其他表的数据。

### 6.1 `reminders` 补列

`title, note, timezone, due_utc, all_day, rrule, occurrence_index, status, snoozed_until, priority, created_by, assignee_bot_id, source_message_id (REFERENCES messages(id) ON DELETE SET NULL), client, notify, alert_offsets, version, completed_at, cancelled_at, updated_at`；索引 `(user_id, status, due_utc)`、`(user_id, assignee_bot_id)`。`bot_id` 列保留为「创建者 Bot」（即 `source_bot_id`，接口里两个名字同值）。

### 6.2 新表

```sql
CREATE TABLE IF NOT EXISTS reminder_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reminder_id INTEGER NOT NULL REFERENCES reminders(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,        -- created/updated/fired/completed/snoozed/missed/skipped/cancelled/restored/reopened/confirm_requested/confirm_rejected
  from_status TEXT, to_status TEXT,
  occurrence_due_utc TEXT,   -- 重复提醒的哪一次
  actor TEXT NOT NULL,       -- user / bot / system
  actor_bot_id INTEGER,
  client TEXT,               -- ios / web / chat / notification / scheduler
  detail TEXT,               -- JSON：改动的字段名与新旧时间；不存备注全文
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rev_rem ON reminder_events(user_id, reminder_id, id);

CREATE TABLE IF NOT EXISTS notifications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category TEXT NOT NULL CHECK (category IN ('reminder','bot_message','delegation','plugin','system')),
  title TEXT NOT NULL, body TEXT, sensitive INTEGER NOT NULL DEFAULT 0,
  bot_id INTEGER REFERENCES bots(id) ON DELETE SET NULL,
  reminder_id INTEGER REFERENCES reminders(id) ON DELETE SET NULL,
  message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL,
  plugin_id TEXT, link TEXT, thread_id TEXT,
  dedupe_key TEXT NOT NULL,
  created_at TEXT NOT NULL, read_at TEXT, opened_at TEXT, expires_at TEXT,
  UNIQUE(user_id, dedupe_key)
);
CREATE INDEX IF NOT EXISTS idx_ntf_user ON notifications(user_id, read_at, id);

CREATE TABLE IF NOT EXISTS notification_deliveries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  notification_id INTEGER NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  channel TEXT NOT NULL CHECK (channel IN ('inbox','local','apns')),
  device_id TEXT,
  state TEXT NOT NULL,       -- §9.3
  attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, apns_id TEXT,
  scheduled_for TEXT, sent_at TEXT, delivered_at TEXT, opened_at TEXT, updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ndl_state ON notification_deliveries(state, scheduled_for);

CREATE TABLE IF NOT EXISTS notification_prefs (
  user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  enabled INTEGER NOT NULL DEFAULT 1,            -- 服务端总开关（与 iOS「通知」开关同步）
  categories TEXT NOT NULL DEFAULT '{}',         -- {"reminder":true,"bot_message":true,...}，缺省按 §9.1 默认
  muted_bots TEXT NOT NULL DEFAULT '[]',         -- 静音的 Bot id
  quiet_enabled INTEGER NOT NULL DEFAULT 0,
  quiet_start TEXT NOT NULL DEFAULT '23:00', quiet_end TEXT NOT NULL DEFAULT '08:00',
  quiet_timezone TEXT NOT NULL DEFAULT 'Asia/Shanghai',
  preview TEXT NOT NULL DEFAULT 'title',         -- full / title / none
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS push_devices (       -- R1 就注册（记录本地通知能力），R3 才发 APNs
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,                       -- App 安装 + 账号维度的随机 UUID（Keychain 外的普通存储，退出即换）
  platform TEXT NOT NULL DEFAULT 'ios',
  apns_token TEXT,                               -- 可空：未授权 / 无开发者账号时没有
  apns_env TEXT,                                 -- sandbox / production
  app_version TEXT, os_version TEXT, timezone TEXT,
  local_reminders INTEGER NOT NULL DEFAULT 1,    -- 该设备自己排本地提醒通知
  disabled_at TEXT, last_seen_at TEXT NOT NULL, created_at TEXT NOT NULL,
  UNIQUE(user_id, device_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_push_token ON push_devices(apns_token) WHERE apns_token IS NOT NULL;
```

推送相关表在 v11 一次建好（与 v7 提前建 `pending_actions` 的做法一致），之后的分期只加代码不再迁移。

### 6.3 回填规则（存量数据）

| 存量 | 回填 |
|---|---|
| `title` | = `content`（截断 200，超出部分移入 `note`） |
| `due_at` 能解析 | 规范为带偏移的 ISO，算 `due_utc`；`timezone='Asia/Shanghai'` |
| `due_at` 是模型原文、无法解析 | `due_at=NULL`，原文写入 `note`「原时间：…」，成为无日期待办 |
| `done=1` | `status='done'`，`completed_at=NULL`（未知） |
| `done=0`，未来 | `scheduled`；过去 ≤ 24 小时 → `due`；更早 → `missed` |
| 无时间 | `scheduled`（无日期） |
| `created_by` | `bot`（存量都由工具创建）；`assignee_bot_id = bot_id`；Bot 已删除则都为 NULL |
| `version=1`，`updated_at=created_at`，每行写一条 `created` 事件（`actor=system`，`detail={"migrated":true}`） |
| `notification_prefs` | 不预先插行，读取时按默认值；首个 PATCH 时写入 |

## 7. API 设计

所有接口需 `Authorization: Bearer`，按 `user_id` 隔离，他人或不存在的资源一律 404；全部带 `Cache-Control: no-store`（现有中间件已覆盖 `/api/*`）。写接口支持 `Idempotency-Key` 头（同用户 24 小时内相同 key 返回首次结果），供通知动作和离线队列重放使用。

### 7.1 提醒

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/reminders` | 参数：`status`（逗号分隔，默认未取消的全部）、`bot_id`（创建者或归属）、`created_by`、`from`/`to`（`due_utc` 范围）、`updated_since`（增量同步）、`limit`（默认 200）、`before_id`。返回 `{reminders, server_time, counts:{due, today, upcoming, undated, missed, done}}` |
| POST | `/api/reminders` | 用户创建 → 201 `Reminder`。字段：`title`、`note`、`due_at`、`timezone`、`all_day`、`rrule`、`priority`、`assignee_bot_id`、`notify`、`alert_offsets`（R2） |
| GET | `/api/reminders/{id}` | 单条，含 `next_fires`（最多 10 次） |
| PATCH | `/api/reminders/{id}` | 部分修改 + 必填 `expected_version`；冲突 409 `version_conflict` 并返回最新对象 |
| POST | `/api/reminders/{id}/complete` | `{occurrence_due_utc?}`；旧的 `/done` 保留为别名（Web 用） |
| POST | `/api/reminders/{id}/snooze` | `{minutes}` 或 `{until}` |
| POST | `/api/reminders/{id}/reopen`、`/skip`、`/restore` | 撤销完成 / 跳过本次 / 从已取消恢复 |
| DELETE | `/api/reminders/{id}` | 取消（软删除）；`?scope=occurrence` 对重复提醒只跳过本次 |
| POST | `/api/reminders/batch` | `{ids, action: complete/cancel/snooze}`，≤ 50（R2） |
| GET | `/api/reminders/{id}/events` | 操作历史（R2 界面） |

错误：422（时间无效 / 过去 / RRULE 不支持 / 字段超长，中文消息）、409（`invalid_transition` / `version_conflict`）、404。

### 7.2 通知

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/notifications` | `unread=true`、`category`、`before_id`、`limit` → `{notifications, unread_count}` |
| GET | `/api/notifications/summary` | `{unread_count, by_category}`（角标用，轻量） |
| POST | `/api/notifications/{id}/read`、`/api/notifications/read-all` | 已读；`read-all` 可带 `category`、`before_id` |
| DELETE | `/api/notifications/{id}` | 从收件箱删除 |
| POST | `/api/notifications/{id}/events` | 客户端回报投递：`{event: delivered/opened/dismissed, channel, device_id, at}` |
| GET / PATCH | `/api/notification-settings` | 偏好（§9.1）；PATCH 只改传入字段 |

### 7.3 设备

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/devices` | 注册 / 刷新：`{device_id, platform, apns_token?, apns_env?, app_version, os_version, timezone, local_reminders}` → 200。同一 `apns_token` 已绑在别的账号 → 从旧账号解绑后绑到当前账号 |
| DELETE | `/api/devices/{device_id}` | 退出登录时调用；服务端在 logout / logout-all / 邮箱认领吊销（PR #8）时也一并禁用该用户的设备 |

### 7.4 SSE / 工具结果

- `create_reminder` / `manage_reminder` 的 `tool_result.result` 带 `reminder`（与 GET 同结构）或 `pending_id`。iOS 收到后即时刷新本地通知（不等下拉刷新）。
- 新增可选 SSE 事件 `event: notification data: {id, category, title, link}`：对话进行中产生的通知（如委派完成）让 App 当场显示应用内横幅；旧客户端忽略。

## 8. 前后端字段对照 (iOS ↔ backend)

> 契约测试（Contract test）`reminder_test.py` REM-CONTRACT / `notify_test.py` NTF-CONTRACT 读取 Swift 源码里的 CodingKeys 断言键名一致（做法同 STAT-08）。所有新字段在 iOS 端 `decodeIfPresent`，旧后端缺键不崩。

### 8.1 Reminder

| 后端 JSON | iOS `VeraBotCore.Reminder` | 说明 |
|---|---|---|
| `id` | `id: Int` | |
| `title` | `title: String` | 缺失时回退 `content` |
| `content` | `content: String` | 兼容（= title） |
| `note` | `note: String?` | |
| `due_at` | `dueAt: String?` | 展示时用 `Date` 解析后按设备时区格式化，不再字符串切片 |
| `due_utc` | `dueUTC: Date?` | 排序 / 排通知 |
| `timezone` | `timeZone: String` | |
| `all_day` | `allDay: Bool` | |
| `rrule` | `rrule: String?` | iOS 只做预设 ↔ 文本映射，不计算 |
| `repeat_label` | `repeatLabel: String?` | 服务端生成的中文，如「工作日 09:00」 |
| `next_fires` | `nextFires: [Date]` | 本地通知排程用 |
| `status` | `status: ReminderStatus` | `scheduled/due/snoozed/done/missed/cancelled`，未知值 → `.unknown` |
| `snoozed_until` | `snoozedUntil: Date?` | |
| `priority` | `priority: Int` | |
| `created_by` | `createdBy: String` | `user` / `bot` |
| `bot_id` / `source_bot_id` | `sourceBotId: Int?` | 同值 |
| `bot_name` | `botName: String?` | 兼容；= 来源 Bot 名 |
| `assignee_bot_id` / `assignee_bot_name` | `assigneeBotId: Int?` / `assigneeBotName: String?` | |
| `source_message_id` | `sourceMessageId: Int?` | 「查看对话」 |
| `notify` / `alert_offsets` | `notify: Bool` / `alertOffsets: [Int]` | |
| `version` | `version: Int` | PATCH 回传 `expected_version` |
| `done` | `done: Int` | 兼容 |
| `completed_at` / `cancelled_at` / `created_at` / `updated_at` | 同名 camelCase `String?` | |

### 8.2 Notification / Settings / Device

| 后端 JSON | iOS 属性 |
|---|---|
| `id`, `category`, `title`, `body`, `sensitive`, `link`, `thread_id` | `id`, `category: NotificationCategory`, `title`, `body`, `sensitive`, `link`, `threadId` |
| `bot_id`, `reminder_id`, `message_id`, `plugin_id` | `botId`, `reminderId`, `messageId`, `pluginId` |
| `created_at`, `read_at`, `opened_at` | `createdAt`, `readAt`, `openedAt`（`isUnread = readAt == nil`） |
| `unread_count` | `NotificationsResponse.unreadCount` |
| settings：`enabled`, `categories`, `muted_bots`, `quiet_enabled`, `quiet_start`, `quiet_end`, `quiet_timezone`, `preview` | `NotificationSettings.enabled`, `categories: [String: Bool]`, `mutedBots: [Int]`, `quietEnabled`, `quietStart`, `quietEnd`, `quietTimeZone`, `preview` |
| device：`device_id`, `platform`, `apns_token`, `apns_env`, `app_version`, `os_version`, `timezone`, `local_reminders` | `DeviceRegistration` 同名 camelCase |

## 9. 通用通知层 (Notification layer)

### 9.1 来源与默认偏好

| 分类 `category` | 来源 | 默认 | 受免打扰影响 | 渠道（R1 → R3） |
|---|---|---|---|---|
| `reminder` 提醒 | 提醒到时（T2 / T3） | 开 | **否**（用户自己定的时间，D8） | 本地通知 + 收件箱 → 不变（APNs 只做静默同步） |
| `bot_message` Bot 消息 | 提醒回流消息（R2）；Bot 主动消息 / 定时任务（R4） | 开 | 是 | 收件箱 + 前台横幅 → APNs |
| `delegation` 协作完成 | 用户离开对话后才完成的回复 / 委派（R2，见 §11.5） | 开 | 是 | 收件箱 → APNs |
| `plugin` 插件事件 | MCP / 插件通知（如 Gmail 新邮件，随插件 P2 之后） | **关** | 是 | 收件箱 → APNs |
| `system` 系统 | 账号安全（新设备登录、邮箱被认领、密码清空）、版本公告 | 开（安全类不可关） | 安全类否 | 收件箱 → APNs |

偏好三层，**全部为「与」关系**：iOS 系统授权 ∧ 用户总开关 ∧ 分类开关 ∧ 该 Bot 未静音。任何一层关闭 → 只进收件箱（投递状态 `suppressed`，原因记 `last_error`），不弹通知。提醒的「静音 Bot」不影响用户自己建的提醒。

### 9.2 免打扰 (Quiet hours)

- 用户级：开关 + 开始 / 结束时间（可跨午夜）+ 时区，默认关闭（D9）。
- 时段内：受影响的分类只进收件箱，不弹；时段结束后**不补发**横幅，角标与收件箱可见（避免早上一次弹一串）。
- 本地通知：iOS 在排程时同样跳过受影响分类（R1 只有提醒，不受影响）；iOS 系统的「专注模式」由系统处理，App 不干预。

### 9.3 投递状态 (Delivery states)

| 状态 | 含义 | 由谁写 |
|---|---|---|
| `queued` | 已建，待发 | 服务端 |
| `scheduled_local` | 已交给设备自己排程（本地提醒） | 客户端回报 / 服务端预置 |
| `sent` | APNs 返回 200（已被苹果接受） | 服务端 |
| `delivered` | 设备确认收到（前台 `willPresent`；后台在下次启动时从 `getDeliveredNotifications` 补报） | 客户端 |
| `opened` | 用户点开 | 客户端 |
| `dismissed` | 用户在通知上划掉（`UNNotificationDismissActionIdentifier`，需 category 带 `.customDismissAction`） | 客户端 |
| `suppressed` | 偏好 / 免打扰 / 限流 / 去重未发出 | 服务端 |
| `failed` | APNs 最终失败（重试用尽，或 400 / 403） | 服务端 |
| `expired` | 超过 TTL 未发出（如服务停机太久） | 服务端 |
| `cancelled` | 来源已失效（提醒已完成 / 取消，本地通知被撤下） | 任一方 |

`inbox` 渠道没有状态流转，只有通知本身的 `read_at` / `opened_at`。本地通知的 `delivered` 只能尽力回报（App 被杀且用户没再打开时无从得知），文档和看板如实标「未知」。

### 9.4 去重与限流 (Dedupe / rate limits)

- **去重键**：`reminder:{id}:{occurrence_due_utc}`、`bot_message:{message_id}`、`delegation:{delegation_id}`、`plugin:{plugin_id}:{外部事件 id}`、`system:{kind}:{日期}`。`UNIQUE(user_id, dedupe_key)`，重复写入直接返回已有行。
- 本地通知 identifier = `vb.{user_id}.rem.{reminder_id}.{occurrence_epoch}`，APNs `apns-collapse-id` 用同一键的哈希；服务端在提醒到时写收件箱时**不再**向开了 `local_reminders` 的设备发 APNs，避免同一提醒响两次。
- **限流**（超过 → `suppressed`，仍进收件箱）：

| 范围 | 上限（默认） |
|---|---|
| 每个 Bot 的 `bot_message` | 每天 3 条（D10） |
| 每用户所有 `bot_message` | 每天 10 条 |
| `plugin` | 每个插件每小时 5 条、每天 20 条 |
| 每用户全部 APNs 横幅 | 每小时 30 条 |
| 提醒 | 不限流（用户自己设的），但单个提醒的提前提醒最多 3 个 |

计数存 SQLite（按 `notifications.created_at` 统计），不用内存——避免后端重启清零（账号隔离审计时发现登录限流在内存里，这里不重复该问题）。

### 9.5 深链接 (Deep links)

应用内路由，格式 `path?query`，放在通知 `userInfo["link"]` 和收件箱 `link` 字段：

| link | 打开 |
|---|---|
| `reminder/{id}` | 提醒 Tab → 该提醒编辑页 |
| `reminders?bucket=due` | 提醒 Tab「逾期」 |
| `bot/{id}/chat?message={mid}` | 该 Bot 对话，滚动到该消息 |
| `plugin/{plugin_id}` | 设置 › 插件 › 详情 |
| `inbox` | 通知收件箱 |
| `settings/notifications` | 设置 › 通知 |

- **点按通知本体的路由规则**：提醒通知 (`reminder/{id}`) → 打开「提醒」Tab → 该提醒页；对话从该页「来源」里的「查看对话」进入。只有 Bot 消息通知 (`bot/{id}/chat?message={mid}`) 直接打开对话。Boss 于 2026-10-04 按此设计验收。
- 不注册自定义 URL Scheme（R1 不需要外部唤起，也就不用改 Info.plist / pbxproj）；路由由 App 内 `DeepLinkRouter` 解析，未知路径落到收件箱。
- 打开前校验：通知所属 `user_id` 必须等于当前登录用户；目标不存在（已删除）→ 提示「内容已不存在」。

### 9.6 隐私 (Privacy)

- 通知展示模式 `preview`：`full`（标题 + 正文）/ `title`（默认：提醒显示标题，Bot 消息只显示「『研究助手』有新消息」）/ `none`（统一「你有一条新通知」）。
- **APNs 载荷默认不带任何业务正文**：只放 `notification_id`、`category`、`link`、`uid_hash`（用户 id 的 HMAC，用来校验账号）和按 `preview` 生成的通用标题；需要正文时 App 打开后再从 API 取。理由：载荷经过苹果服务器并会出现在锁屏。
- `sensitive=1`（关联健康 / 财务记忆、或插件标记为敏感）的通知在任何模式下都不带正文。
- 本地提醒通知的标题由设备本地生成，按 `preview` 处理；备注从不进通知。
- 服务端日志不打印通知正文和 APNs token（只打 token 后 6 位）。

### 9.7 服务端调度 / 分发 (Scheduler & dispatcher)

新模块 `services/notify/`（`dispatcher.py`、`apns.py`、`prefs.py`）与 `services/reminders/`（`service.py`、`rrule.py`、`scheduler.py`）。

- **单个后台任务**：FastAPI 启动时创建一个 asyncio 任务（与现有 `startup` 同处注册，关闭时取消），每 30 秒一次：
  1. 提醒：`scheduled/snoozed` 且 `due_utc/snoozed_until ≤ now` → `due` + `fired` 事件 + `notify(category=reminder)`；`due` 超过宽限期 → `missed`；重复提醒推进下一次；`cancelled` 满 30 天 → 硬删除。
  2. 通知：处理 `queued` 的 APNs 投递（R3），失败指数退避（30 秒、2 分钟、10 分钟，共 3 次）；APNs 410 `Unregistered` / 400 `BadDeviceToken` → 禁用该设备；超过 TTL（提醒 1 小时、其他 24 小时）→ `expired`。
  3. 清理：超过 30 天的已读通知、过期的 `pending_actions`、24 小时外的幂等记录。
- **补跑（Catch-up）**：后端在 Mac 上运行，会睡眠 / 关机。启动和每次唤醒后的第一轮会处理所有积压：一次性提醒按规则进入 `due` / `missed`；重复提醒只记一条「错过 N 次」事件并推进到下一个未来时间，**不补发**多条通知。
- 并发：只跑一个 uvicorn 进程（现状）；每条状态转换都是带条件的 `UPDATE`，即使将来多进程也不会重复触发。
- `notify(user_id, category, …)` 是唯一入口：写 `notifications`（去重）→ 判定偏好 / 免打扰 / 限流 → 写 `notification_deliveries`（inbox 总是写；local / apns 按设备）→ 若该用户有活跃 SSE 连接，推 `notification` 事件。

## 10. iOS 界面 (Native iOS)

> 只用系统默认样式和 Theme 语义色，不加自定义动画；文案中文，无英文。

### 10.1 提醒 Tab

- 导航标题「提醒」；顶部系统分段控件 **「提醒 | 通知」**（D15）；Tab 图标角标 = 未读通知数（提醒到时会生成通知，所以逾期提醒也计入）。
- 「提醒」页：系统 `List` 分组（§4.4）。行：左侧圆形勾选按钮（点按即完成，触感反馈沿用现有开关），标题（已完成删除线），副标题「今天 09:00 · 工作日 · 来自 研究助手」，高优先级显示 `exclamationmark` 系统图标，逾期时间用红色语义色。
- 工具栏：右上 ＋（新建）；左上筛选 `Menu`：全部 / 我创建的 / Bot 创建的 / 按 Bot（列出 Bot）；「显示已完成」开关。
- 左滑（trailing）：完成（绿色）、删除（destructive；重复提醒弹系统确认框「仅删除这一次 / 删除整个系列」）。右滑（leading）：稍后（`Menu`：10 分钟 / 1 小时 / 今晚 20:00 / 明天 09:00）。长按 `contextMenu`：编辑、稍后、归属 Bot、复制、删除。
- 点行 → 编辑 sheet；下拉刷新；空状态沿用 `ContentUnavailableView`，加「新建提醒」按钮。

### 10.2 新建 / 编辑 sheet

系统 `Form`：标题（必填）· 备注（多行）· 「日期」开关 + `DatePicker`（日期）· 「时间」开关 + `DatePicker`（时间，关闭 = 全天）· 重复 `Picker`（永不 / 每天 / 工作日 / 每周 / 每月 / 每年；R2 加「自定义…」）· 提前提醒（R2）· 优先级 `Picker`（无 / 低 / 中 / 高）· 归属 Bot `Picker`（无 / 各 Bot，说明「归属的 Bot 可以查看和管理这条提醒」）· 来源分组（只读）：「由『研究助手』在对话中创建」+「查看对话」（深链接到消息）· 编辑页底部「删除提醒」。工具栏圆形 X 取消、「保存」。保存时 409 冲突 → 提示「这条提醒已在别处修改」并载入最新内容。开关用全 App 统一的 `CompactToggle`；两个 `DatePicker` 用 `.labelsHidden()` 只显示所选值（含义由上方开关行提供，不再重复「日期」「时间」标签），并设区分开的 `accessibilityLabel`「提醒日期」「提醒时间」（Boss 2026-10-04 验收发现的重复行已修，PR #27）。

### 10.3 通知收件箱（「通知」分段）

系统 `List`，按时间倒序，未读行前有品牌色圆点；行：分类图标（`alarm` / Bot 头像 / `person.2` / `puzzlepiece` / `gearshape`）、标题、正文一行、相对时间。点按 → 标记已读并按深链接跳转。左滑：删除；右滑：标为已读 / 未读。工具栏「全部已读」。分类筛选 `Menu`。

### 10.4 设置 › 通知

原「通用 › 通知」开关改为 `NavigationLink`「通知」进入独立页：
- 允许通知（系统授权状态 + 开关，被拒绝时「前往设置」——沿用现有逻辑）。
- 分类：提醒 / Bot 消息 / 协作完成 / 插件 / 系统（安全通知不可关，说明文字）。
- 免打扰：开关 + 开始 / 结束 `DatePicker(.hourAndMinute)`；说明「提醒不受免打扰影响」。
- 通知显示内容：`Picker` 显示完整内容 / 仅标题（默认）/ 不显示内容。
- 已静音的 Bot 列表。
- Bot 详情页新增一行「通知」开关（静音该 Bot 的 Bot 消息与协作通知）。

### 10.5 对话里

- R1：工具卡片沿用现有样式，结果中文化（「已创建提醒：明天 09:00 交周报」）。
- R2：提醒卡片（标题、时间、重复、「编辑」「撤销」）；确认卡片（「研究助手想删除 3 条提醒：… [确认] [取消]」），与 MCP M3 共用组件。
- 前台收到 `notification` SSE 事件或本地通知 `willPresent`：用系统横幅（`.banner, .sound, .list`）展示，当前正在看的对话不重复弹。

## 11. 投递与同步 (Delivery & sync)

### 11.1 本地通知（R1 的主路径）

- `UNUserNotificationCenter`；注册 category `VB_REMINDER`，动作：**完成**（`VB_DONE`）、**稍后 10 分钟**（`VB_SNOOZE_10`），选项 `.customDismissAction`；不需要解锁即可执行（只改提醒状态，风险低）。
- `NotificationScheduler.reconcile(reminders)`：期望集合 = 所有 `notify=true`、未结束提醒在未来 14 天内的 `next_fires`（含提前提醒），按时间取最近 **60** 条（系统上限 64，预留 4 条）；与 `getPendingNotificationRequests()` 对比，删多余、补缺失、改已变的。identifier 见 §9.4。
- 简单重复（每天 / 每周某一天 / 工作日拆成 5 个，`INTERVAL=1` 且无 `COUNT/UNTIL`）额外使用 `UNCalendarNotificationTrigger(repeats: true)`，保证用户 14 天不开 App 也照常响；复杂规则用一次性触发，打开 App 时补齐。
- 触发 reconcile：启动、回到前台、`GET /api/reminders` 后、本地增删改后、对话 `done` 事件里有提醒工具结果时、通知动作执行后、通知设置变化后；R2 起 APNs 静默推送（`content-available`）也触发。
- `willPresent`（App 在前台）：显示横幅并回报 `delivered`；`didReceive`（点按或动作）：回报 `opened` 或执行动作。

### 11.2 通知动作在后台执行

1. 系统在后台唤起 App 执行 `didReceive`（约 30 秒）。
2. 先校验 `userInfo.uid` == 当前登录用户；不符（已换账号）→ 丢弃并撤下该通知。
3. **先本地生效**：完成 → 撤下该提醒后续通知；稍后 → 立刻排一条 10 分钟后的本地通知。
4. 再调 API（`Idempotency-Key = 通知 identifier + 动作`）；失败（后端在 Mac 上、手机不在局域网很常见）→ 写入**按用户隔离的离线队列**（App 沙盒文件 `outbox-{user_id}.json`），下次回到前台按顺序重放；服务端 409 `invalid_transition` 视为已处理。
5. 服务端以 `client=notification` 记录事件。

### 11.3 同步策略

- 服务端是唯一事实来源（source of truth）；iOS 不缓存提醒到磁盘（与缓存隔离修复一致，内存 + 离线队列）。
- 增量：`GET /api/reminders?updated_since=<上次 server_time>`；R1 先做全量（数据量小），接口预留参数。
- 冲突：`version` 乐观锁；离线队列重放遇到 409 冲突 → 丢弃该操作并提示一次「有 N 项操作因提醒已在别处修改而未生效」。
- 其他客户端（Web / 另一台设备 / Bot 在 Web 对话里）建的提醒，要等本机下次打开 App 才排上本地通知——R1 已知限制；R3 用 APNs 静默推送解决。

### 11.4 APNs（远程推送，R3；R2 先做客户端预备）

- **前提**：需要 Apple Developer Program 付费账号（个人 99 美元 / 年）才能给 App ID 开 Push Notifications、生成 `.p8` 鉴权密钥；工程需加 `aps-environment` entitlement（即改 `project.pbxproj`，按规则须 Boss 同意）。**目前不假设 Boss 有付费账号，也未核实**（D17）。
- **模拟器**：`xcrun simctl push <UDID> <Bundle ID> payload.apns`（或把 `.apns` 文件拖到模拟器，文件内含 `"Simulator Target Bundle"`）可以在**不连 APNs、不需要账号**的情况下把载荷直接送进 App，用来验证通知展示、分类动作、深链接、账号校验、静默同步。R2 用这种方式完成客户端开发和测试，fixture 放 `frontend/scripts/push/*.apns`。模拟器上能否拿到真实 sandbox device token（理论上需 T2 / Apple 芯片的 Mac + 账号），需在 Boss 的 Mac 上验证后再定。
- 注册：系统授权后调用 `registerForRemoteNotifications()`；拿到 token → `POST /api/devices`；拿不到（无 entitlement）→ 照样注册设备（`apns_token=null`），本地通知不受影响。
- 发送（服务端）：HTTP/2 到 `api.sandbox.push.apple.com` / `api.push.apple.com`，JWT（ES256，`.p8`）鉴权，每小时内复用；需要 `httpx[http2]`（新依赖 `h2`，D16）。密钥放 `.env`（`VERABOT_APNS_KEY_PATH`、`KEY_ID`、`TEAM_ID`、`TOPIC`），不进仓库。
- 载荷示例：

```json
{"aps":{"alert":{"title":"Vera Bot","body":"「研究助手」有新消息"},"sound":"default","thread-id":"bot-3","category":"VB_GENERIC"},
 "nid":1234,"cat":"bot_message","link":"bot/3/chat?message=55","uid":"<HMAC>"}
```

- 静默同步：`{"aps":{"content-available":1},"cat":"sync","what":"reminders"}`，App 收到后 reconcile；需要 Background Modes › Remote notifications（同样改 pbxproj）。

### 11.5 其他来源何时能用

| 来源 | R1 | R2 | R3（APNs） | R4 |
|---|---|---|---|---|
| 提醒 | 本地通知 + 收件箱 | + 提前提醒 + 对话回流 | + 跨设备静默同步 | |
| 协作完成 / 离开对话后的回复 | — | 收件箱 + 前台横幅（需确认 `runtime` 在 SSE 断开后是否继续执行；若不继续，此项移到 R4 与异步任务一起做） | + 锁屏推送 | |
| 系统安全通知 | 收件箱（邮箱认领、新设备登录） | | + 推送 | |
| 插件 / MCP 事件 | — | — | 收件箱 + 推送（依赖插件 P2） | |
| Bot 主动消息 / 定时任务 | — | 提醒回流（不调用模型） | | 定时让 Bot 执行（D12） |

**提醒回流到对话（R2，D6）**：Bot 创建 / 归属的提醒到时，在该 Bot 对话里插入一条 `assistant` 消息「⏰ 提醒：交周报（09:00）」，`traces` 标记 `{"kind":"reminder_fired","reminder_id":…}`，不调用模型、不计用量；通知深链接到这条消息。用户自建且未归属的提醒不回流。

## 12. 账号隔离、审计与安全 (Isolation / audit / security)

- **服务端**：所有表带 `user_id`，所有查询带 `user_id`；创建 / 修改时 `assignee_bot_id`、`source_message_id` 必须属于当前用户（否则 404）；工具层只用 `ctx.user_id` 和 `ctx.bot`，不接受模型传来的 user / bot id；`/api/*` `no-store`。
- **设备**：`push_devices` 绑定 `(user_id, device_id)`；同一 APNs token 只能属于一个账号；logout → 客户端 `DELETE /api/devices/{id}`，服务端在 `logout`、`logout-all`、`token_version` 变化、邮箱认领吊销（PR #8）时禁用该用户全部设备；发送前再次校验设备未禁用。
- **iOS 退出 / 换账号**（接入现有退出流程，与 `Cache.db` 清理同处）：`removeAllPendingNotificationRequests()`、`removeAllDeliveredNotifications()`、角标清零、删除该用户离线队列、换新 `device_id`；登录后重新注册设备并 reconcile。所有通知 `userInfo` 带 `uid`，处理前比对。
- **审计**：提醒每次状态变化写 `reminder_events`（actor / client / Bot）；Bot 越权和确认卡片拒绝写 `audit_log`；通知投递写 `notification_deliveries`。事件 `detail` 只存字段名和时间，不存备注全文。
- **防注入**：Bot 写提醒的标题 / 备注当作普通文本；本轮读过外部内容后写操作需确认（§5.3）；提醒标题里的链接在通知里不可点。
- **限额**：§5.4、§9.4。

## 13. Web（冻结）

不做任何 Web 界面。兼容：`GET /api/reminders` 仍返回 `content`、`done`、`bot_name`、`due_at`；`POST /api/reminders/{id}/done` 保留。Web 看不到新状态（只显示未完成 / 已完成），不显示通知。在 STATUS「Web 落后」登记。

## 14. 分期 (Phasing)

| 期 | 范围 | 前置 | 估算 |
|---|---|---|---|
| **R1 提醒 + 本地通知 + 收件箱**（不需要 APNs 和付费账号） | schema v11（全部表）；提醒状态机与调度器（到时 / 错过 / 推进 / 补跑）；预设重复；用户 CRUD / 完成 / 稍后 / 撤销 / 跳过 / 恢复 API；`list_reminders` 改为可见范围、`create_reminder` 增强、`manage_reminder`（单条 update / complete / snooze / reopen / skip，**不含 cancel**）；`notify()` 入口 + 收件箱 + 偏好 + 免打扰 + 去重 / 限流（DB 计数）；设备注册（无 token）；iOS：提醒 Tab 重做、编辑 sheet、左右滑、筛选、本地通知 + 完成 / 稍后动作、reconcile、离线队列、收件箱分段、设置 › 通知页、深链接、退出清理；契约测试与文档 | PR #7 合并（v10 + `builtin_reminder`） | 约 5 人日（后端 2、iOS 2.5、测试文档 0.5） |
| **R2 确认卡片 + 对话联动 + APNs 客户端预备** | `pending_actions` 确认卡片（与 MCP M3 共用）；Bot `cancel` 与批量；提醒卡片 + 撤销；提醒回流对话；自定义重复；提前提醒；操作历史页；批量选择；协作完成通知；Bot 静音；系统安全通知；`simctl push` fixture 与客户端远程通知处理（展示 / 动作 / 深链接 / uid 校验） | R1 | 约 4 人日 |
| **R3 APNs 真推送** | entitlement（改 pbxproj）、`.p8` 配置、HTTP/2 发送器、重试 / 410 处理、投递状态看板（调试页）、跨设备静默同步、锁屏推送其他分类 | Boss 付费开发者账号 + 同意改 pbxproj（D17） | 约 3 人日 + 账号准备 |
| **R4 主动能力** | Bot 定时任务（到点让 Bot 跑一轮，计入用量，结果作为 `bot_message`）；插件 / MCP 事件订阅；时间敏感通知 / 通知服务扩展；标签 / 智能列表；可选 EventKit | R3；插件 P2 | 另行评估 |

R1 是一个 PR；前后端同一提交更新 CHANGELOG / FEATURES / TEST_CASES / STATUS；Web 冻结。

## 15. 已定决策 (Decisions, 2026-10-03)

> Boss 于 2026-10-03 批准全部 18 项，均采用推荐方案。备选列仅留作记录，不实施。

| # | 问题 | 决定（2026-10-03） | 未采用的备选 |
|---|---|---|---|
| D1 | Bot 能看到哪些提醒 | ✅ 已定：只看自己建的 + 用户指派给它的 | 能看到全部（现状） |
| D2 | Bot 哪些操作要确认 | ✅ 已定：取消、批量、改重复规则、读过外部内容后的写操作要确认；单条完成 / 稍后 / 改时间不用 | 所有写操作都确认 |
| D3 | 存量 Bot 是否自动获得「管理提醒」 | ✅ 已定：不自动授予，用户在工具权限里打开 | 有「创建提醒」的自动获得 |
| D4 | 何时算「错过」 | ✅ 已定：一次性：到时 24 小时后；重复：到下一次或 24 小时，取较早 | 不设错过，一直逾期 |
| D5 | 稍后默认时长 / 全天提醒时间 | ✅ 已定：通知上「稍后 10 分钟」；列表可选 10 分钟 / 1 小时 / 今晚 20:00 / 明天 09:00；全天提醒 09:00 响 | 通知上给两个稍后选项 |
| D6 | 提醒到时是否在 Bot 对话里插一条消息 | ✅ 已定：Bot 创建 / 归属的插入（不调用模型），用户自建的不插（R2） | 都不插 |
| D7 | 删除是否可恢复 | ✅ 已定：软删除，30 天内可恢复 | 直接删除 |
| D8 | 免打扰是否拦截提醒 | ✅ 已定：不拦截（用户自己定的时间） | 也拦截 |
| D9 | 免打扰默认 | ✅ 已定：关闭，开启后默认 23:00–08:00 | 默认开启 |
| D10 | Bot 消息通知上限 | ✅ 已定：每个 Bot 每天 3 条，每人每天 10 条 | 不限 |
| D11 | 通知收件箱保留多久 | ✅ 已定：30 天 | 90 天 |
| D12 | Bot 到点自动执行任务（会消耗用量、无人在场） | ✅ 已定：本期不做，R4 再议 | R2 就做 |
| D13 | 被委派的 Bot 能否读写提醒 | ✅ 已定：禁止 | 只读 |
| D14 | 提醒标签 | ✅ 已定：不做（已有 Bot 筛选和优先级） | R2 加 |
| D15 | 通知收件箱放哪 | ✅ 已定：提醒 Tab 顶部分段「提醒 / 通知」，Tab 角标 = 未读通知数 | 首页工具栏加铃铛 |
| D16 | 新增后端依赖 | ✅ 已定：R1 加 `python-dateutil`（RRULE）；R3 加 `httpx[http2]`（APNs） | 手写 RRULE 子集，不加依赖 |
| D17 | APNs | ✅ 已定：R1 / R2 不依赖；R3 前 Boss 确认是否开通付费开发者账号，并同意为推送改 `project.pbxproj`（entitlement、后台模式） | 长期只用本地通知 |
| D18 | 锁屏显示内容默认 | ✅ 已定：仅标题（提醒显示标题，Bot 消息不显示内容；备注从不显示） | 显示完整内容 |

## 16. 验收用例 (Acceptance tests)

> 后端在 `backend/` 下 `uv run python scripts/test/reminder_test.py`、`notify_test.py`（确定性，模拟时钟，不连外网）；iOS Kit `swift test` 新增 `ReminderTests`、`NotificationSchedulerTests`、`DeepLinkTests`；模拟器手工用例由 Veronica 在 Boss 的 Mac 上验收。

### 16.1 后端 · 提醒

| 编号 | 场景 | 预期 |
|---|---|---|
| REM-01 | v10 → v11 迁移（含原文时间、已完成、过去未完成、已删除 Bot 的行） | 按 §6.3 回填；版本 11；备份文件存在；再次启动幂等 |
| REM-02 | 用户创建 / 读取 / 修改 / 删除 | 201 / 200；`version` 递增；`done` 兼容字段正确 |
| REM-03 | 过去时间、非法时区、不支持的 RRULE、超长标题 | 422 中文消息 |
| REM-04 | 调度：`scheduled` 到时 → `due`，产生 1 条 `fired` 事件和 1 条通知 | 重复跑调度器不重复 |
| REM-05 | 宽限期 → `missed`；`missed` 后完成 | 状态正确，事件齐全 |
| REM-06 | 稍后 → `snoozed` → 到时 `due` | `snoozed_until` 生效 |
| REM-07 | 重复提醒完成 / 错过 / 跳过 | 推进到下一次；`COUNT` 用尽 → `done` |
| REM-08 | 工作日、每月 31 号、跨时区设备 | `next_fires` 正确；墙钟不漂移 |
| REM-09 | 补跑：模拟停机 3 天的每日提醒 | 只记 1 条「错过 3 次」，推进到未来，只发 0 条补发通知 |
| REM-10 | 非法转换（取消后完成） | 409 `invalid_transition` |
| REM-11 | 并发：调度器与用户同时完成 | 只有一方成功，状态一致 |
| REM-12 | 乐观锁 | 旧 `expected_version` → 409 带最新对象 |
| REM-13 | 幂等：同一 `Idempotency-Key` 完成两次 | 第二次返回同结果，只 1 条事件 |
| REM-14 | 软删除与恢复；30 天后清理 | 符合 D7 |
| REM-15 | 旧接口 `/done`、旧字段 | Web 兼容 |

### 16.2 后端 · Bot 权限

| 编号 | 场景 | 预期 |
|---|---|---|
| REM-BOT-01 | Bot A `list_reminders` | 只含 A 创建 / 归属的（D1） |
| REM-BOT-02 | Bot A 管理 Bot B 的提醒 | 「提醒不存在」+ `audit_log` |
| REM-BOT-03 | 无 `manage_reminder` 权限调用 | `tool_not_allowed` |
| REM-BOT-04 | 被委派 Bot 调用提醒工具 | 拒绝（D13） |
| REM-BOT-05 | `create_reminder` 时间无法解析 / 已过去 | 返回错误，不入库 |
| REM-BOT-06 | 同轮重复创建同标题同时间 | 返回已有 id |
| REM-BOT-07 | 每轮写操作超过 5 次 | 第 6 次被拒 |
| REM-BOT-08（R2） | Bot 取消 / 批量 / 读过 MCP 后写 | 返回 `pending_confirmation`；确认后才生效；拒绝 / 过期不生效 |
| REM-BOT-09 | Bot 删除后 | 提醒保留，归用户，显示「已删除的 Bot」 |
| REM-BOT-10 | `GET /api/tools` | `manage_reminder` 的 `plugin_id=builtin_reminder` |

### 16.3 后端 · 通知

| 编号 | 场景 | 预期 |
|---|---|---|
| NTF-01 | `notify()` 去重 | 相同 `dedupe_key` 只有 1 行 |
| NTF-02 | 总开关 / 分类 / Bot 静音关闭 | 进收件箱，投递 `suppressed` |
| NTF-03 | 免打扰时段（跨午夜） | Bot 消息 `suppressed`；提醒照常（D8） |
| NTF-04 | 限流 | 每 Bot 第 4 条 `suppressed`；重启后计数仍在 |
| NTF-05 | 收件箱列表 / 已读 / 全部已读 / 删除 / 未读数 | 正确 |
| NTF-06 | 客户端回报 delivered / opened | 状态推进，不能回退 |
| NTF-07 | 设备注册：同一 APNs token 换账号 | 只属于新账号 |
| NTF-08 | logout / logout-all / 邮箱认领吊销 | 该用户设备全部禁用 |
| NTF-09（R3） | APNs 410 / 400 / 5xx | 禁用设备 / 失败 / 退避重试 |
| NTF-10 | 载荷隐私 | 默认无正文；`sensitive` 永远无正文；日志无 token 全文 |
| NTF-11 | 提醒到时，设备 `local_reminders=1` | 不生成 APNs 投递 |

### 16.4 隔离与契约

| 编号 | 场景 | 预期 |
|---|---|---|
| ISO-REM-01 | 用户 B 访问 A 的提醒 / 通知 / 设备 / 事件（全部接口） | 404 |
| ISO-REM-02 | 创建时 `assignee_bot_id` / `source_message_id` 为他人的 | 404 |
| ISO-REM-03 | 响应头 | `Cache-Control: no-store` |
| REM-CONTRACT / NTF-CONTRACT | Swift CodingKeys 与后端键名 | 完全一致；新字段缺失时可解码 |

### 16.5 iOS（Kit 单测 + 模拟器手工）

| 编号 | 场景 | 预期 |
|---|---|---|
| REM-UI-01 | 分组（逾期 / 今天 / 即将 / 无日期 / 已错过 / 已完成）与筛选 | 与 §4.4 一致，时间按设备时区显示 |
| REM-UI-02 | 新建 / 编辑 sheet（预设重复、归属 Bot、查看对话） | 保存成功；409 冲突提示 |
| REM-UI-03 | 左滑完成 / 删除（重复提醒二选一），右滑稍后 | 正确；触感反馈受开关控制 |
| REM-UI-04 | 本地通知：建 1 分钟后的提醒，App 退到后台 / 杀掉 | 按时响；通知上「完成」「稍后 10 分钟」生效。模拟器：通知中心 → 通知左滑 → 「查看」→ 选动作；真机：长按通知 |
| REM-UI-05 | 后端停掉时点通知「完成」 | 本地立即生效；后端恢复、App 回前台后同步 |
| REM-UI-06 | reconcile：上限 60、修改 / 删除后通知随之变化、简单重复用 repeats | `NotificationSchedulerTests` 覆盖 |
| REM-UI-07 | 对话里「明天 9 点提醒我交周报」 | 工具卡片中文；提醒 Tab 出现；本地通知已排 |
| NTF-UI-01 | 通知分段：未读圆点、点按跳转、已读 / 全部已读、角标 | 正确 |
| NTF-UI-02 | 设置 › 通知：分类、免打扰、显示内容、被拒授权回退 | 与服务端同步 |
| NTF-UI-03 | 深链接（各 link，目标已删除） | 跳转正确 / 提示「内容已不存在」 |
| NTF-UI-05 | 点按通知本体（提醒通知 / Bot 消息通知） | 提醒通知 → 「提醒」Tab → 该提醒页，「来源」的「查看对话」跳到对话；只有 Bot 消息通知直接打开对话（§9.5） |
| NTF-UI-04 | 退出登录 / 换账号 | 本地待发与已送达通知、角标、离线队列清空；新账号看不到旧账号通知 |
| PUSH-SIM-01（R2） | `xcrun simctl push` 发送 fixture（前台 / 后台 / 带动作 / 错误 uid） | 展示、动作、深链接正确；错误 uid 被丢弃 |
| REM-UI-08 | 深色模式、动态字体 | 原生样式正常 |

验收：上表 R1 用例（不含 R2 的 PUSH-SIM-01）Boss 于 2026-10-04 在模拟器上验收通过；Kit `swift test` 于 main 6800822 上运行，148/148 通过。

## 17. 改动范围与风险 (Files & risks)

- **后端**：`db/schema.py`（v11）、`tools/reminder.py`（改 + 新 `manage_reminder`）、`api/routers/reminders.py`（扩展）、新增 `api/routers/{notifications,devices}.py`、`services/reminders/*`、`services/notify/*`、`main.py`（注册路由 + 启动 / 停止调度任务）、`agents/prompts.py`（规则）、`services/plugins/catalog.py`（`builtin_reminder.tools`，PR #7 之后）、`services/auth.py`（logout 时禁用设备）、`pyproject.toml` / `uv.lock`（D16）。
- **iOS**：`VeraBotCore/Models.swift`（Reminder 扩展）、新 `Reminders.swift` / `Notifications.swift`（模型、分组、reconcile 纯逻辑，便于 `swift test`）、`VeraBotAPI.swift`、`Features/Reminders/*`（列表、编辑、收件箱）、`Features/Settings/NotificationSettingsView.swift`、`GeneralSettingsSection.swift`（改为入口）、`AppState`（通知代理、深链接、退出清理）、`BotEditView`（通知开关、`manage_reminder` 中文名）。**不改** `project.pbxproj`、`InfoPlist.xcstrings`、`.env`（R3 前）。新建 Swift 文件若需加入工程，按现有 `project.yml` 方式处理，由 Veronica 在 Mac 上确认。
- **风险**：后端跑在 Mac 上、手机不在同一网络时 API 不通 → 本地优先 + 离线队列；iOS 64 条待发上限 → 只排 60 条最近的；调度器与 Mac 睡眠 → 补跑；`list_reminders` 收窄可见范围是**行为变化**，需在 CHANGELOG 写明；与 PR #7、#8 的文档冲突在合并时处理。


## 18. 变更记录 (Changelog)

| 版本 | 日期 | 说明 |
|---|---|---|
| v0.1 | 2026-10-03 | 草案：提醒模块与通用通知 / 推送层合并设计 |
| v1.0 | 2026-10-03 | 定稿：Boss 批准 D1–D18 全部按推荐；R1 范围不变（schema v11，接在 PR #7 的 v10 之后） |

## 19. R1 实现注记 (Implementation notes，2026-10-03)

上文 §0–§18 为已批准正文，此处只记录落地时相对正文的补充，不改已定规则。

- **数据层**：提醒、提醒事件、收件箱、投递、通知偏好、设备、幂等键，以及调度器对 `reminders` / `idempotency_keys` / 过期 `pending_actions` 的查询，全部在 `backend/verabot/db/reminder_store.py`。`api/` 与 `services/` 只调用这些函数，并在需要时传入同一条连接以保持事务。迁移 SQL 仍在 `db/schema.py`。本次没有搬动提醒以外的既有 SQL。
- **字段对照**仍以 §8 为准。`source_bot_id` 与 `bot_id` 是同一列的两个 JSON 键。公开 JSON 不含 `client`、`occurrence_index`。契约：`reminder_test.py` REM-CONTRACT、`notify_test.py` NTF-CONTRACT。
- **相对 §6.2 / §7 的增补**：表 `idempotency_keys`（写接口 `Idempotency-Key`，按用户保留 24 小时）；`POST /api/notifications/{id}/unread`（收件箱标为未读）。
- **Bot 删除**：从 v10 迁上来的 `reminders` 表没有 `bot_id` 外键。启动时重建触发器 `reminders_clear_assignee`，删除 Bot 时同时把 `bot_id` 与 `assignee_bot_id` 置空。新库的建表语句另有 `ON DELETE SET NULL`。
- **R1 的 `manage_reminder`**：取消、批量、修改重复规则返回中文错误，不进入确认卡片（确认卡片是 R2）。
- **邮箱认领**：PR #8 已在 main。`_claim_unverified_email` 在同一事务里调用 `_disable_push_devices`（不调用 `logout_all`，避免嵌套事务和二次增加 `token_version`）。对外的 `revoke_for_email_claim` 仍走 `logout_all`。已验证邮箱的验证码登录不禁用设备。
- **主题**：main（`7201049`）没有薰衣草主色 + 青绿点缀的 Theme C，仍是 Vera 深海青绿。提醒界面只用 main 已有语义色：未读圆点 `Color.brand`，错误与逾期用系统红 `.red`。未改 `Theme.swift`。
- **Web** 仍冻结。`POST /api/reminders/{id}/done` 与列表里的 `content` / `done` / `bot_name` / `due_at` 保持可用。
- **iOS** 本环境未编译、未跑模拟器。APNs 不在 R1。
