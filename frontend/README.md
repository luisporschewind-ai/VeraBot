# VeraBot Frontend (前端) — v0.1.0

2026-10-16：堆叠缩略图填满并裁切，点击查看后完整等比显示（静态图和 GIF 一致），见 [修正记录](../docs/tasks/2026-10-16-image-fill-fit.md)。

2026-10-16：多图各层可点击打开对应图片，堆叠再缩小 10%，查看页扩大图片区并固定底部页码，见 [细化记录](../docs/tasks/2026-10-16-image-stack-gallery-details.md)。

2026-10-16：多图堆叠缩小至 75%，下层展示真实图片并填满卡片，见 [调整记录](../docs/tasks/2026-10-16-image-stack-refinement.md)。

2026-10-16：修复短 Bot 回复误折叠；500 个非空白字素以内完整显示，较长回复继续按原规则折叠，见 [修复记录](../docs/tasks/2026-10-16-short-reply-collapse.md)。

2026-10-16：私聊、群聊附件选完自动发送，移除发送前预览；相册最多 9 张合为一条堆叠消息，保留文字草稿。交互和验证见 [修改记录](../docs/tasks/2026-10-16-direct-multi-image-send.md)。

2026-10-12：iOS 主线接入 VeraBotPersistence（SQLite）与 VeraBotData（Repository/群模型），列表、历史和草稿按账号/服务器隔离。最新构建安装证据见 [Main 集成交付](../docs/testing/2026-10-12-main-integration.md)。

两个客户端，通过 HTTP / SSE 调用后端 API (见 [backend/README.md](../backend/README.md))，不依赖后端源码。

```
frontend/
├── ios/                          # SwiftUI iOS App
│   ├── VeraBot.xcodeproj         # Xcode 工程 (文件夹同步组，VeraBot/ 下新增文件自动加入编译)
│   ├── project.yml               # 备用：xcodegen 重新生成工程
│   ├── Config/Info.plist
│   ├── VeraBot/                  # App 源码 (按功能分目录)
│   │   ├── App/                  #   入口 VeraBotApp、AppState、AppConfig (默认服务器地址)
│   │   ├── Core/UI/              #   Theme (语义色 / Liquid Glass)、CircleAvatar、BotAvatar、UserAvatar、AvatarPicker、AvatarImage、LiveBotAvatar、
│   │   │                         #   DismissToolbarButton、Haptics、MessageContentView (富文本)、InAppBrowser (SFSafariViewController)
│   │   ├── Features/             #   Auth、BotList、BotInfo、Chat、Settings (含 DebugView)、Reminders、Quota (设置 › 用量)
│   │   ├── Services/             #   Keyboard、Speech (语音输入)、Avatar (AvatarStore)
│   │   └── Assets.xcassets
│   └── Packages/VeraBotKit/      # 本地 Swift Package (SPM)
│       ├── Sources/VeraBotCore        # 共享模型 (Codable，含 HealthStatus) + SettingsKeys + ListTimestamp + MessageMarkdown
│       ├── Sources/VeraBotNetworking  # VeraBotAPI 协议 + APIClient (REST + SSE)
│       ├── Sources/VeraBotPersistence # SQLite / 本地快照 / 草稿
│       ├── Sources/VeraBotData        # 账号作用域 Repository / 群会话模型
│       ├── Sources/VeraBotTTS         # TTSEngine 协议 + 本机 / 云端引擎 + SpeechPlayer
│       └── Tests/VeraBotKitTests      # swift-testing 单元测试 (ModelsTests 11 + MessageMarkdownTests 10)
├── web/                          # Web SPA (index.html / app.js / style.css)，由后端托管在 /
└── scripts/
    ├── run_ios.sh                # 命令行编译 + 安装 + 启动到模拟器
    ├── sim/                      # 模拟器 UI 自动化辅助 (ui.sh + click / drag 源码，首次使用自动编译)
    └── web/                      # Playwright 截图、Web 语音输入测试 (+ fixtures)
```

## 1. iOS App

**要求**：macOS + Xcode 26 (Swift 6.2)；部署目标 iOS 17.0；Swift 6 语言模式、`SWIFT_STRICT_CONCURRENCY = complete`。

1. 先启动后端 (`backend/start.sh`)。
2. 打开 `frontend/ios/VeraBot.xcodeproj`，Xcode 会自动解析本地包 VeraBotKit (无需联网)。
3. Target VeraBot → Signing & Capabilities 选择 Team (模拟器可不签名)；Bundle ID `com.verabot.app`。
4. 选择 iPhone 模拟器 (测试用 iPhone 17 / iOS 26)，⌘R。或者命令行：`frontend/scripts/run_ios.sh "iPhone 17"`。
5. 登录：演示账号 `demo` / `verabot2026` (由 `backend/scripts/dev/seed_demo.py` 创建)。

**显示名称 / 图标**：主屏显示「Vera Bot」，图标见 `Assets.xcassets/AppIcon.appiconset`。

**服务器地址**：默认 `http://127.0.0.1:8000` (`App/AppConfig.swift`)，登录后可在 设置 › 🐞 调试 查看。模拟器直接使用；真机在登录页「服务器地址」填 Mac 的局域网 IP，如 `http://192.168.1.10:8000`。`Info.plist` 允许本地 HTTP (ATS 例外)，生产需改 HTTPS。

**模拟器键盘**：若键盘不弹出，在 Simulator 菜单 I/O → Keyboard 取消「Connect Hardware Keyboard」，或按 ⌘K (Toggle Software Keyboard)。

### 依赖管理 (SPM)

- 只使用 **Swift Package Manager**，不使用 CocoaPods / Carthage。
- 可复用、与 UI 无关的代码放在本地包 `Packages/VeraBotKit`：App 通过 `import VeraBotCore / VeraBotNetworking / VeraBotPersistence / VeraBotData / VeraBotTTS` 使用；App 依赖协议 `VeraBotAPI`、`TTSEngine`，便于测试替身 (mock) 和替换实现。
- 目前**没有第三方依赖**。以后添加时：
  - 被 Kit 使用：在 `Package.swift` 的 `dependencies` 加 `.package(url:..., from:...)`，并加到对应 target。
  - 只被 App 使用：Xcode → Project → Package Dependencies → ＋。
  - 两种方式都会生成 / 更新 `Package.resolved`，需要一并提交。
- 包测试：`cd frontend/ios/Packages/VeraBotKit && swift test` (包同时声明 macOS 14，只为在 Mac 上跑测试)。

## 2. Web SPA

纯静态文件，无构建步骤。后端启动时，只要 `frontend/web/index.html` 存在就托管在 <http://127.0.0.1:8000/>；单独部署时可以放在任意静态服务器上，与后端同源即可 (或给后端设置 `VERABOT_WEB_DIR`)。
说明：Web 端只作为 API 验收客户端，**落后于 iOS**：没有 v0.1.0 迭代 2 的 iOS UI (权限编辑、协作记录、设置页、TTS)，也没有 2026-10-01 之后的改动 (昵称编辑、照片头像、调试页、通用设置、列表时间 / 搜索、白底 + Liquid Glass 风格、浮动输入栏、消息富文本与 App 内网页)。后端 API 对 Web 保持兼容。

## 3. 测试脚本

```bash
# Web 截图 / 语音输入测试（需要 Chrome；截图输出到 assets/screenshots/web）
cd backend && uv run --with playwright python ../frontend/scripts/web/screenshots.py
cd backend && uv run --with playwright python ../frontend/scripts/web/voice_ui_test.py

# iOS 模拟器 UI 自动化（需给终端开启「辅助功能」权限）
source frontend/scripts/sim/ui.sh
tap 240 245; shot home      # 坐标为 471×1024 截图像素；截图输出到 assets/screenshots/scratch (已 gitignore)
```

UI 用例与结果见 [docs/testing/TEST_CASES_v0.1.md](../docs/testing/TEST_CASES_v0.1.md)。

## 4. 许可证 (License)

[MIT License](../LICENSE)，Copyright (c) 2026 Luis Porsche。

## 2026-10-17：个人 Feed /「发现」

新增原生底部「发现」（tag=5），保留现有助理、提醒、游乐场和探索入口及 tag。
在发现右上角「关注计划」选择供稿 Bot、主题和排除主题，可显式关闭记忆建议，
从真实来源目录或自定义公开 HTTPS RSS / Atom 地址添加订阅，再启用计划。
来源页显示暂停/恢复、最近成功、下次检查和真实采集错误。目录添加与计划保存分别生效，
关闭计划不会删除已订阅来源；没有自动启用、伪造内容或测试账号。

列表支持新闻/短帖/视频/音频、供稿 Bot、仅收藏、明确刷新和稳定游标加载更多；
反馈失败保留内容和表单输入。普通列表为空或计划/来源暂停时仍可进入收藏。
详情把订阅提供的 description 标为「来源简介」、body 标为「订阅正文节选」，展示推荐依据；
不声称已读原文或生成 AI 摘要，不自动下载图片/媒体。阅读/播放打开现有 App 内浏览器的原站链接。
「问 Bot」先校验当前账号 Bot，获取有界服务器引用草稿，再进入已有私聊，
将引用追加到未发送草稿后，仅用户显式发送。发现内私聊沿用原有消息可见/已读与通知抑制规则。

Core `Feed.swift`、独立 `FeedAPI` / `APIClient+Feed.swift` 和可观察 `FeedViewModel`
与聊天协议分离。账号、登录会话或服务器切换重建导航并清空 Feed 作用域；
代次检查拒绝过期列表、分页、反馈和提问草稿，刷新失败保留已有内容。
源文件由 `xcodegen generate` 注册，构建号为 `2026101701`。
包级验证：`swift test --package-path frontend/ios/Packages/VeraBotKit --jobs 2`；
FeedTests 覆盖 JSON null/蛇形字段、认证请求/筛选/稀疏反馈、memory=false、分页去重、
取消/过期响应、账号切换、已有草稿保留及发现内私聊可见性策略。
完整联调、独立预览安装与人工验收由任务交付记录单列，包测试不代表界面验收。

2026-10-17 审阅修复：关注计划表单只在已保存计划成功读取后创建，避免慢网时以默认值覆盖设置；
来源/计划写入确认后会使较早的元数据读取失效并重新获取，暂停、添加和保存不会被旧响应回退。
列表加载错误与修改失败独立保存，成功刷新不会抹去未保存反馈的提示。
关闭或下滑取消「问 Bot」时取消上下文任务，并校验当前弹窗仍展示，迟到结果不再跳转。
对应的可控延迟回归覆盖暂停/添加/保存三种交错、列表与反馈失败交错、计划加载门槛及上下文取消。

2026-10-17 草稿复核修复：同一 Bot 从助理和发现进入私聊时，每次重新显示页面都读取共享草稿；
Feed 引用只在该页面实例首次成功加载时追加一次，重复出现不会重复引用。
PrivateChatDraftSession 区分加载、用户编辑与离开：异步读取期间输入会保留并与已存草稿合并，
未激活或尚未完成读取的旧页面不再在消失时写回旧输入，过期读取和延迟保存被当前进入代次拒绝。
新增五项状态回归覆盖双入口、重复显示、加载中输入、加载完成前离开和旧保存任务。
