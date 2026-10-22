# 对话页回复时自动上滑（贴底跟随）修复

日期：2026-10-22。用户反馈：Bot 对话页发送内容后，Bot 回答时页面不会自动上滑，需要手动向上滑才能看到新内容。

## 现象与复现

- 复现环境：iPhone 17 / iOS 26.0 模拟器 + 本机测试后端（端口 8001，使用 `backend/data` 的数据库副本，不接触正式库）。
- 打开已有对话（底部），触发一条长回复；回复逐段到达时页面停在原地，最新文字被输入栏挡住，同时右下角出现「回到最新」按钮。
  复现截图：[01-before-during-reply-no-follow](../../assets/screenshots/ios/2026-10-22-chat-auto-scroll/01-before-during-reply-no-follow.png)。
- 该现象与键盘是否弹出无关；在 Bot 列表进入有未读的对话、或停在底部后发送，都会出现。

## 根因

`ChatView` / `GroupChatView` 用「底部锚点是否还在视口内」判断 `followsBottom`，并在内容 tick 时只在 `followsBottom == true` 才滚到底部。问题在于：

1. 回复流式变长、图片加载、LazyVStack 行高修正都会把底部锚点推出视口；
2. 这些几何变化发生在滚动回调之前，把 `followsBottom` 误判成「用户已经滚离底部」；
3. 之后的每个内容 tick 都因为 `followsBottom == false` 跳过滚动，页面就再也不跟了，直到用户点「回到最新」。

日志实证（临时 `Logger` 观测，已移除）：

```
23:19:50.162 MEASURE tick=20 anchor=(16,778) viewport.maxY=779 follows=true  next=true
23:19:51.117 MEASURE tick=20 anchor=(16,872) viewport.maxY=779 follows=true  next=false   ← 内容变长，先于 tick 21 到达
23:19:51.265 TICK tick=21 ... follows=false                                               ← 回调看到 false，跳过滚动
```

另有 `scrollTo("bottom")` 之后 LazyVStack 行高修正（锚点又下移约 94pt）的情况，所以只在 tick 时滚一次也不够。

## 修复

- 贴底意图（`followsBottom`）只由**用户主动滚动**改变，内容增长/布局修正一律不再取消跟随：
  - iOS 18+：新增 `ChatScrollInteraction`，用 `onScrollPhaseChange` 的 `.tracking / .interacting / .decelerating` 标记用户滚动，`.idle` 时用最终位置结算；`.animating`（回到最新、键盘调整、初始定位等程序化滚动）不参与判定。
  - iOS 17：同一 modifier 用 `simultaneousGesture(DragGesture)` 兜底，松手后延迟 500ms、等惯性减速结束再结算。
- 用户正在滚动时，内容 tick 不抢位置（`!userScrolling`）；滚动停稳后再判定是否恢复跟随。
- 内容增长导致锚点跑到视口下方时，补一次贴底滚动（`anchorMoved`，每次布局稳定最多补一次），覆盖 LazyVStack 行高修正造成的「只滚到旧底部」。
- 从通知/搜索定位到旧消息时显式置 `followsBottom = false`（保持阅读位置）；点「回到最新」时立即置 `true`。
- 文件：
  - `frontend/ios/VeraBot/Services/Keyboard/Keyboard.swift`：新增 `ChatScrollInteraction`（与既有的 `bottomAnchoredScrolling` 同处滚动/键盘基础设施）。
  - `frontend/ios/VeraBot/Features/Chat/ChatView.swift`：私聊接入。
  - `frontend/ios/VeraBot/Features/GroupChat/GroupChatView.swift`：群聊按同样的模式接入（同一套跟随判定）。
- 不新增后端接口、不改数据；`ScrollBottomDetector` 的 40pt 容差语义不变。

## 验证

命令：

```sh
cd frontend/ios && xcodebuild -project VeraBot.xcodeproj -scheme VeraBot -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/verabot_dd build
```

- Debug 构建通过（`** BUILD SUCCEEDED **`），已安装并启动到 iPhone 17 模拟器（`com.verabot.app`，测试后端端口 8001）。
- 模拟器实测（截图见 `assets/screenshots/ios/2026-10-22-chat-auto-scroll/`）：
  - 回复流式到达时，页面持续贴底；键盘弹出时同样贴底且不出现「回到最新」：[02-after-during-reply-follow](../../assets/screenshots/ios/2026-10-22-chat-auto-scroll/02-after-during-reply-follow.png)。
  - 回复完成、长回复折叠后仍在底部，按钮不出现：[03-after-reply-complete-at-bottom](../../assets/screenshots/ios/2026-10-22-chat-auto-scroll/03-after-reply-complete-at-bottom.png)。
  - 用户向下滑动查看旧消息：立即出现「回到最新」按钮：[04-scroll-away-shows-jump](../../assets/screenshots/ios/2026-10-22-chat-auto-scroll/04-scroll-away-shows-jump.png)。
  - 滑回底部后按钮自动隐藏：[05-scroll-back-hides-jump](../../assets/screenshots/ios/2026-10-22-chat-auto-scroll/05-scroll-back-hides-jump.png)。
- Swift 包：`cd frontend/ios/Packages/VeraBotKit && swift test`，504 项测试 / 18 个套件通过（首次运行有 1 项与本轮无关的并发计时用例偶发失败，重跑通过；本轮未修改该包）。
- `git diff --check` 通过。

## 未验证 / 边界

- 群聊没有可用的队伍测试数据，本轮只做到编译通过和按同一逻辑接入，未做群聊界面实测。
- 本机只有 iOS 26 运行时，iOS 17 的拖拽手势兜底分支没有实机验证。
- 测试后端与模拟器数据来自正式库副本（`/tmp/vb_test/data`），未改动正式数据库；正式 App 与本机后端（8000）未重启或替换。
- 自动截图/点击使用 AppleScript + CGEvent 脚本；期间另一会话在同一模拟器启动了其他 App，最后一次「键盘弹出时上滑」操作被抢占，未计入验证证据，核心场景均已单独截图确认。

安装与自动检查不等于用户验收。

人工入口：打开任一 Bot 对话，发送一个需要长回答的问题；观察回复流式出现时页面是否持续贴在最新内容处、输入栏上方是否始终是最新文字；再下滑查看旧消息，确认「回到最新」按钮出现与点击回到底部。
