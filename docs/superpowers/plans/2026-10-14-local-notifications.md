# Local Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 在隔离分支交付提醒、Bot 新消息和任务结果的本地通知闭环。

**Architecture:** 复用提醒规划器与通知收件箱，新增数据库持久通知事件和 App 全局同步。提醒预排程，消息／任务按页面可见性显示 BotNotice 或系统通知；事件与业务事务一致，历史同步静默。

**Tech Stack:** Python/FastAPI/SQLite，Swift 6/SwiftUI/UserNotifications，iOS 17+。

**Spec:** docs/design/2026-10-14-local-notification-proposal.md

## Global Constraints

- 本地通知优先；不接 APNs、不改普通私聊执行器、不合并或推送主分支。
- 主工作区现有修改保持原样；开发仅在新工作树。直接“开始推进”作为实施授权，采用当前会话直接实施。
- 最近 60 条提醒，复杂排程未来 14 天；App 前台每 5 秒同步，失败按 5/15/30/60 秒退避。
- 默认仅标题；系统权限属于设备、业务偏好属于账号；提醒不受 App 自设免打扰影响。
- 事件先落本机再推进游标；首次启用／长离线静默同步；新鲜消息窗口 5 分钟；同会话 30 秒聚合。
- 投递失败不重新执行模型；后台／关闭后的新远程事件即时触达不在本地阶段承诺内。

## Review Focus

- 账号切换发生在通知注册 await 中：旧结果不得重新排程或进入新账号。
- 简单重复带提前提醒、固定时区和 DST：不能丢提前项或漂移时间。
- 独立 Worker 与 API 分进程、事务回滚、通知删除：不能丢事件或读取未提交事件。
- 已读／失效／删除事件与消息可见性：取消旧提示，屏幕外不当作已读。
- 通知动作离线后收到服务端旧排程：本机覆盖保持到动作确认或失效，不反复响。

### Task 1: 提醒规划、权限与动作正确性

**Files:** Modify Notifications.swift, NotificationCoordinator.swift, AppState+Reminders.swift, NotificationSettingsView.swift; create VeraBotCore/LocalNotificationPolicy.swift; test NotificationSchedulerTests.swift.

**Interfaces:** Produces NotificationPlanner.plan(userID:reminders:now:preview:settings:overrides:), full trigger signature on PlannedNotification and ScheduledLocalNotification, ReminderLocalOverride, and NotificationSettings-based filtering. Consumes existing Reminder and ReminderOutbox.

- [ ] 写失败测试：总开关与分类关闭产生空集合；Bot 静音排除 Bot 创建提醒但用户创建仍保留；改日历时刻签名需替换；固定时区／提前提醒保持；完成覆盖排除目标；稍后覆盖只替换目标且到期不重复。
- [ ] Run: swift test --package-path frontend/ios/Packages/VeraBotKit --filter Notification. Expected: new behavioral assertions fail or new interface missing.
- [ ] 实现纯规划与覆盖规则；系统适配器串行注册、账号代次检查、定向稍后；设置分离系统授权与账号开关，设备能力按真实授权上报。
- [ ] Run same command. Expected: all notification tests pass.
- [ ] Commit focused Task 1 files.

### Task 2: 服务端持久通知事件与发布入口

**Files:** Create db/migrations/v030_notification_events.py, db/notification_event_store.py, services/notify/events.py, scripts/test/notification_events_test.py; modify migrations/__init__.py, services/notify/dispatcher.py, prefs.py, db/reminder_store.py, api/routers/notifications.py, agents/runtime.py, scheduled_tasks/delivery.py, owned_tasks/delivery.py.

**Interfaces:** GET /api/notification-events?after=&limit=100&through= returns events, next_cursor, has_more, upper_bound, server_time, reset_required. Events carry event_id, operation, notification_id and optional notification. First request with no cursor returns current upper bound for silent bootstrap. notify gains kind/source fields, task_result is independent public category while legacy clients retain compatibility via stored base category.

- [ ] 写失败集成测试：事件账号隔离、分页冻结上界、提交后可见／回滚无事件、独立进程写入、已读／删除事件、未知游标要求重建；消息发布一次、任务结果独立偏好与路由，敏感内容脱敏。
- [ ] Run: /Users/admin/Desktop/VeraBot-v0.1/backend/.venv/bin/python backend/scripts/test/notification_events_test.py. Expected: new endpoint 404 or assertions fail.
- [ ] 实现 migration/store/service/router；数据库触发器覆盖通知创建／更新／删除，跨进程回读。业务完成保存消息后发布一次，任务复用结果投递并禁止步骤洪水；保留主动消息旧限流，普通回复独立识别。
- [ ] Run new test plus notify_test.py, reminder_test.py, scheduled_tasks and owned tasks focused suites. Expected: pass without external provider calls.
- [ ] Commit focused Task 2 files.

### Task 3: App 全局事件同步、提示与路由

**Files:** Create VeraBotCore/NotificationEvents.swift, VeraBotNetworking/APIClient+NotificationEvents.swift, VeraBot/Services/Notifications/NotificationEventSync.swift, VeraBot/Features/Reminders/ReminderDetailView.swift; modify VeraBotAPI.swift, AppState.swift, VeraBotApp.swift, ChatView.swift, NotificationCoordinator.swift, RemindersView.swift, InboxView.swift, BotNotice.swift/BotNoticeCard.swift and tests/NotificationEventTests.swift.

**Interfaces:** APIClient.notificationEvents(after:through:) -> NotificationEventPage. NotificationEventLedger records cursor and handled logical keys; NotificationEventPolicy.decision(notification:settings:visibleMessageIDs:now:isForeground:) chooses silent/banner/system. App shell owns sync lifecycle; ChatView reports actually visible published message IDs, without adding conversation read cursors.

- [ ] 写失败测试：payload 解码、首次／长离线静默、过期／已读／重复静默、可见回复静默、同会话 30 秒合并、变更事件清理、本机 ledger 原子编码与失败重试。
- [ ] Run: swift test --package-path frontend/ios/Packages/VeraBotKit --filter Notification. Expected: new types absent / assertions fail.
- [ ] 实现账号作用域 ledger 原子写入和增量分页，前后台生命周期及退避、BotNotice 可操作入口、消息可见性和通知清理。代理启动早期注册，点按登录恢复后处理；提醒先只读详情。设置任务结果分类与排程覆盖状态。
- [ ] Run same command plus full swift test. Expected: all pass.
- [ ] Build isolated iOS Simulator app. Expected: BUILD SUCCEEDED.
- [ ] Commit focused Task 3 files.

### Task 4: 验证、记录与分支审查

**Files:** Create docs/testing/2026-10-14-local-notifications.md; update STATUS.md, CHANGELOG.md, FEATURES.md, README.md and design implementation notes only within worktree.

**Interfaces:** Consumes Tasks 1–3 verification output; produces accurate implementation / remaining acceptance record.

- [ ] Run notification/backend related suites, full Swift tests, iOS simulator build, compileall and git diff --check. Expected: pass; known baseline warnings recorded.
- [ ] 核对设置与冷启动路由源代码／构建证据；设备锁屏、系统声音、Focus、实际消息／任务交互明确保留用户验收。
- [ ] 同步文档，提交本分支；由技能要求安排一次独立分支审查，修复重要问题并重跑相关验证。
- [ ] 保留工作树供验收；不合并、不推送、不操作真实模型或用户账号。
