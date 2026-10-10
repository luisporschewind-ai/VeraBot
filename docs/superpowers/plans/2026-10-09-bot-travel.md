# Bot 旅行第一版 Implementation Plan

> 状态：第一版已实现并在 iOS Simulator 构建运行。阶段揭晓的完整 5 分钟等待、跨账号恢复和旅行中聊天限制尚未逐项手动验收。

**Goal:** 在 VeraBot iOS「探索」入口实现可交互的五分钟 Bot 旅行原型，包含真实 Bot 选择、六个目的地、分阶段揭晓、旅行中聊天限制和本机旅行相册。

**Architecture:** 新增独立的 SwiftUI 旅行视图、静态地点内容模型和按用户隔离的本机旅行状态存储。入口从现有旅行想法详情进入；Bot 旅行状态注入全局环境，由聊天页读取以暂停输入。旅程阶段只根据开始时间推导，不使用后台定时任务或服务端接口。

**Tech Stack:** Swift 6、SwiftUI、Observation、Foundation、现有 `AppState` / `VeraBotAPI` / `Bot` 模型；不增加依赖、不修改后端数据库。

**Spec:** `docs/superpowers/specs/2026-10-09-bot-travel-design.md`

## Global Constraints

- 首发地点固定为北京、苏州、成都、京都、巴黎、伊斯坦布尔。
- 测试旅程时长为 300 秒；节点偏移为 0、60、180、300 秒。
- 地点事实显示来源；Bot 旅途感受明确标记为想象内容。
- 单个 Bot 同时最多一趟未完成旅行；其他 Bot 可照常使用。
- 旅行记录使用 `AppState.userID` 隔离存入 UserDefaults；不上传旅行数据。
- 只修改旅行新文件和明确列出的入口/聊天文件；保留所有现有工作区改动。
- 不实现推送、后台定时任务、地图、预订、模型生成或服务端接口。

## Review Focus

- 登出或切换账号：旅程列表不能串号；重登同账号后恢复。
- 应用在旅程期间被杀：重开后根据 `startedAt` 恢复阶段，不能从零计时。
- 旅行恰好完成时聊天重新启用；其他 Bot 不受影响。
- 同一 Bot 已旅行时不能重复派出；记录删除后相册不再展示。
- 来源链接失败或缺失不能阻止旅程主流程；想象文案不能冒充地点事实。

---

### Task 1: 旅行模型与本机状态

**Files:**
- Create: `frontend/ios/VeraBot/Features/Playground/BotTravelStore.swift`

**Interfaces:**
- `BotTravelDestination`: 固定地点 id、名称、地区、主题、事实、来源 URL、线索文案与纪念卡数据。
- `BotTravelTrip`: Codable 记录，包含 UUID、user Bot id/name/avatar/color、地点 id、主题、留言、开始时间和时长。
- `BotTravelStore`: `configure(userID:)`、`activeTrip(botID:at:)`、`startTrip(...)`、`deleteTrip(id:)`、`stage(for:at:)`。
- 阶段偏移精确为 0 / 60 / 180 / 300 秒；状态从 `startedAt` 推导。

- [x] 建立六个地点内容包及官方来源 URL。
- [x] 按 userID 编码、读回、追加和删除旅行记录。
- [x] 为一位 Bot 阻止重复未完成旅程；旅程完成立即解除活动状态。
- [x] 源码核对：旅行记录按 userID 隔离；用户留言不上传，也不写入 Bot 长期记忆。

### Task 2: 出发流程、旅程进度与旅行相册

**Files:**
- Create: `frontend/ios/VeraBot/Features/Playground/BotTravelViews.swift`
- Modify: `frontend/ios/VeraBot/Features/Playground/WorldViews.swift:768-856`
- Modify: `frontend/ios/VeraBot/App/VeraBotApp.swift:7-75`

**Interfaces:**
- `BotTravelStartView`: 加载现有 Bots，选择 Bot / 地点 / 主题，输入可选留言并开始旅程。
- `BotTravelJourneyView`: 按当前时间呈现阶段卡片；可打开事实来源；归来后显示旅札与纪念卡。
- `BotTravelAlbumView`: 回看已完成旅行；可删除单次相册记录。进行中的旅程从出发页续看。
- 全局注入同一个 `BotTravelStore`，账号资料加载后调用 `configure(userID:)`。

- [x] 在 travel idea 详情中加入旅行入口；其他探索想法保持现状。
- [x] 实现出发、地点主题选择和可选留言。
- [x] 实现 0/60/180/300 秒阶段揭晓和完成后的旅札/收藏卡。
- [x] 实现旅行相册的空状态、旅程卡片、详情和删除确认。
- [ ] 模拟器手动走通全部阶段、归来和相册回看；本轮手动确认了选择 Bot、地点并出发。

### Task 3: Bot 旅行期间暂停普通聊天

**Files:**
- Modify: `frontend/ios/VeraBot/Features/Chat/ChatView.swift:1-240`

**Interfaces:**
- `ChatView` 从环境读取全局 `BotTravelStore`。
- 若该 Bot 有未完成旅程，则不展示普通 composer，显示「正在旅行」状态和查看旅程入口。
- 其他 Bot 不受影响；旅程结束时 composer 恢复。

- [x] 在活动旅程期间替换输入栏为旅行状态卡，提供返回旅程的 sheet。
- [ ] 手动确认时间跨过 300 秒后聊天恢复；代码已在前台时刷新旅程阶段。
- [ ] 手动核对从助理列表、小岛进入 ChatView 都受到同一状态约束。

### Task 4: 文档同步与成品核对

**Files:**
- Modify: `docs/product/2026-10-08-playful-world-discussion.md`
- Modify: `docs/README.md`

- [x] 在产品讨论稿记录已确认的旅程决策，并指向本设计文档。
- [x] 在文档索引登记 Bot 旅行设计与实现计划。
- [x] `git diff --check` 并检查旅行功能改动边界。
- [x] 构建并运行 iOS Simulator 原型。
