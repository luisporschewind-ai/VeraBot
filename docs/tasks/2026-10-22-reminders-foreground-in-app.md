# 安排到点：App 前台改 App 内提示

日期：2026-10-22。用户要求「安排里，如果当前在 App 里，就不用给通知了」；确认方案为「系统通知不弹，改 App 内小提示」。

## 行为

- App 在前台（`UIApplication.applicationState == .active`）时，提醒类本地通知（`VB_REMINDER`，或带 `reminder_id` 的旧排程）不再显示系统横幅、不播放系统提示音。
- 改为在 App 内顶部显示既有 BotNotice：标题为提醒标题（「不显示内容」预览在排程时已替换为通用文案），副标题「到提醒时间了」，动作「查看」跳转 `reminder/<id>`。
- App 不在前台时保持原系统通知；Bot 消息、任务结果等非提醒通知不受影响。
- 若 App 内提示宿主尚未就绪（例如刚启动的瞬间），退回系统横幅，避免提醒彻底丢失。
- 是否前台由 `NotificationCoordinator` 在 `willPresent` 中判断；纯逻辑抽到 `VeraBotCore.LocalNotificationPolicy` 并做单元测试。

## 文件

- `frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/LocalNotificationPolicy.swift`：新增前台提醒展示策略。
- `frontend/ios/Packages/VeraBotKit/Tests/VeraBotKitTests/LocalNotificationPolicyTests.swift`：前台 / 后台、提醒 / 非提醒用例。
- `frontend/ios/VeraBot/Services/Notifications/NotificationCoordinator.swift`：`willPresent` 识别提醒并抑制系统展示，改叫 App 内提示。
- `frontend/ios/VeraBot/Services/Notifications/NotificationEventSync.swift`：`showReminderDue(reminderID:title:)` 复用 BotNoticeCenter。
- `docs/design/REMINDER_PUSH_DESIGN.md`：更新 §10.5、§11.1 的前台展示说明。

## 验证

- `swift test`（VeraBotKit）：504 项 Swift Testing 通过。首轮与并行构建争用时出现 1 项既有用例失败，重跑全绿。
- `xcodebuild` Debug（iPhone 17 / iOS 26.0 模拟器）构建通过；未安装、未推送、未部署。
- 未做真机 / 模拟器到点实测，人工验收待用户。

## 人工验收

1. App 保持在前台，等一条安排到点：应无系统横幅和声音，App 顶部出现 Bot 小提示；点「查看」进入该安排详情。
2. 把 App 退到后台，再等一条安排到点：仍应收到系统通知。
3. 对照 Bot 消息 / 任务结果通知：前台行为不变。
