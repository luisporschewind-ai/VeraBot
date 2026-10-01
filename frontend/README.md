# VeraBot Frontend (前端) — v0.1.0

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
- 可复用、与 UI 无关的代码放在本地包 `Packages/VeraBotKit`：App 通过 `import VeraBotCore / VeraBotNetworking / VeraBotTTS` 使用；App 依赖协议 `VeraBotAPI`、`TTSEngine`，便于测试替身 (mock) 和替换实现。
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
