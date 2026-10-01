# 项目状态 (STATUS) — 2026-10-01

## v0.1.0 · 原型验证完成 (Prototype validated, feasible)

| 项 | 状态 |
|---|---|
| 结论 | ✅ 原型验证完成，方案可行：多 Bot 私聊 + 多 Agent 协作 (权限 / 隔离 / 护栏 / 审计) + SSE 流式 + 工具调用在 iOS 模拟器 + 本机后端上端到端跑通 |
| 版本 | git tag `v0.1.0`；后端 `verabot 0.1.0`。已发布包为 schema v2；当前未发布改动在启动时迁到 **schema v3**（昵称 + 照片头像）。iOS `0.1.0 (1)` |
| 测试 | v0.1.0：**91 条用例：通过 90 / 失败 0 / 跳过 1** (TC-31 语音输入按要求跳过)，见 [TEST_CASES_v0.1.md](testing/TEST_CASES_v0.1.md)；重构后回归见同文档末尾。之后新增：AV / NK 21/21 (API)、`swift test` 21 条；UI-* / MSG-* 大多待 Boss 验收 (见下节) |
| 交付 | 后端 `dist/VeraBot-backend-v0.1.0.zip` (一键启动)；iOS Xcode 工程 + SPM 本地包；见 [DELIVERY.md](ops/DELIVERY.md) |
| 运行环境 | macOS Intel (MacBook Pro 13" 2018)、Xcode 26.0.1、iPhone 17 模拟器 (iOS 26)、Python 3.12 (uv)、DeepSeek `deepseek-chat` |

## 📍 当前进度 (Current progress) — 截至 commit `4f4cd49` (2026-10-01 14:44 UTC+8)

v0.1.0 之后的改动都在 `main` 上，尚未发版 (见 [CHANGELOG.md](CHANGELOG.md) [Unreleased])。数据库已到 **schema v3**；iOS 版本号仍为 `0.1.0 (1)`。

### 已完成，待 Boss 验收 (Done, pending Boss verification)

| 项 | Commit | 验证情况 | 对应用例 |
|---|---|---|---|
| 浮动 Liquid Glass 输入栏 (圆形 ＋、胶囊输入框「向 {Bot 名} 提问」、🎙，无发送按钮、return 发送) | `46cb977` | 已构建、安装、启动；按 Boss 要求未做模拟器点测 | UI-20 |
| 消息富文本 (Markdown：标题 / 列表 / 代码块 / 引用 / 表格等，`~` 原文显示) | `4f4cd49` | `swift test` 通过 (`MessageMarkdownTests` 10 条)；界面未点测 | MSG-01、MSG-02 |
| 链接：网址在 App 内 `SFSafariViewController` 打开，电话 / 邮箱交给系统；长按复制全文 / 复制链接 | `4f4cd49` | 同上 | MSG-03、MSG-04 |
| 白底 + Liquid Glass 视觉风格、沉浸式助理列表、主题语义色 (theme tokens，`Core/UI/Theme.swift`)、深色模式 | `c94e26b` | 模拟器目视：首页 / 设置 / 对话 / Bot 详情 (浅色 + 深色)；其余页面待验收 | UI-16~19 |
| 对话标题胶囊按钮 | `b59bf7a` | 模拟器目视 | UI-15 |
| 正圆头像、圆形 X 取消 / 关闭、列表行时间、首页按需搜索 (范围暂定) | `36d96a7`、`8e0c585`、`3139826` | 模拟器构建 / 截图；待验收 | UI-11~14 |
| 设置页重排 (账号 → 用量 → 通用 → 语音 → 关于 → 退出登录)、调试页 🐞、用量移入设置、通用 (外观 / 通知 / 触感反馈 / 语言) | `15cfbe8` | 待验收 | UI-04~09、SET-10 |
| 用户 / Bot 照片头像 + 可编辑昵称 (Stuart 实现，schema v3) | `07d0716` | 后端 `avatar_profile_test.py` 21/21；iOS 待 Mac 模拟器点测 | AV-*、NK-*、UI-AV-01/03、UI-NK-01 |
| App 图标、主屏显示名「Vera Bot」 | `b5eccd9`、`d824796` | 已构建 | — |
| 去掉列表数量页脚、账号信息并入设置、移除「恢复默认头像」入口 | `8794552` 等 | 待验收 | UI-01~03、UI-10 |

### 暂停 / 延期 (Paused / deferred)

| 项 | 状态 |
|---|---|
| MCP 能力、Gmail 接入 | 📝 设计稿完成，**等待 Boss 评审**，未写实现代码 (见下一节) |
| 首页搜索扩展 (完整聊天历史搜索、搜索历史) | ⏸ 延期到后续迭代；当前只过滤已加载列表 |

### 已知遗留 (Known leftovers，仅列出，未处理)

- **Web 客户端落后于 iOS**：没有迭代 2 的 iOS UI，也没有 2026-10-01 之后的全部 iOS 改动 (见 §2 第一条)。
- **截图过时**：`assets/screenshots/ios/` 下全部截图早于 2026-10-01 的界面改动；其中 `R34_form_keyboard`、`R11_settings` 与当时的界面也已不符。新 UI 用例 (UI-*、MSG-*) 尚无截图。
- **`frontend/ios/VeraBot/File.txt`** 仍在仓库中 (8 字节，内容「QA回归」，NEW-03)，待确认是否删除。
- **新建 Bot 表单页脚文案过时**：仍写「在对话页右上角「Bot 设置」中开启」(`CreateBotSheet.swift`)，实际入口是「对话页点标题 → Bot 详情」。
- **设计稿中的 schema 版本号**：MCP / Gmail 设计稿撰写时以「v3」为目标，现在 v3 已被头像 / 昵称占用，实施时顺延 (已在两份设计稿中注明)。

## ⏸ 设计评审：开发暂停，等待 Boss 评审 (Development paused pending Boss review)

Boss 决定把 MCP (Model Context Protocol) 作为 VeraBot 的一等能力，Gmail 优先通过 MCP 接入。以下两份设计稿已完成，**尚未编写任何实现代码**；在 Boss 评审并回答开放问题之前，不开始开发。

| 能力 | 设计文档 | 状态 | 需要 Boss 做的事 |
|---|---|---|---|
| MCP 能力 (MCP Client、OAuth 2.1、工具映射、权限、HITL、防注入) | [MCP_CAPABILITY.md](design/MCP_CAPABILITY.md) | 📝 设计稿 v0.1 | 评审；回答 §16 开放问题 Q1~Q11 |
| Gmail (主路径：Google 官方 Gmail MCP；备用：直连 Gmail API) | [GMAIL_CAPABILITY.md](design/GMAIL_CAPABILITY.md) | 📝 设计稿 v0.2 | 评审；回答 §16 开放问题 Q1~Q12；创建 Google Cloud 项目并加入 Google Workspace Developer Preview Program (§14) |

评审通过后的第一步是 M0 / G0 技术验证 (1~2 天)，见 MCP 文档 §15。

## 1. 已完成功能 (Features done)

| 模块 | 状态 | 说明 |
|---|---|---|
| 账号 Accounts | ✅ | 注册 / 登录 (bcrypt + JWT)，Token 持久化，失效自动退出，设置页底部退出登录 (二次确认)。昵称 `PATCH /api/me`（设置页可编辑；首页与对话读同一 `AppState`） |
| 租户隔离 Isolation | ✅ | 所有查询带 `user_id`，越权 (IDOR) 返回 404 |
| Bot 管理 | ✅ | 创建 (＋)、编辑 (Bot 详情 / 长按「编辑与权限」)、左滑删除；软上限 20 (`MAX_BOTS_PER_USER`，达到上限 ＋ 置灰)；列表不显示数量页脚；行右上角显示最后消息时间；右上角 🔍 搜索入口保留但范围暂定：当前只过滤屏幕上已加载的列表（Bot 名称 + 最后一条消息预览）；完整聊天历史搜索、搜索历史等移至后续迭代 |
| 流式对话 SSE | ✅ | 逐 token 渲染、工具卡片、交接 Trace 卡片、错误气泡 |
| 记忆 Memory | ✅ | 每 Bot 独立，最近 20 条；清空对话 (二次确认) |
| 工具 Tools | ✅ | 天气 (Open-Meteo)、创建 / 查询提醒、`ask_bot` |
| 多 Agent 协作 | ✅ | 工具白名单、委派白名单、接受委派、上下文隔离、深度 / 环路 / 单轮上限 / Token 预算、审计日志、协作记录页 |
| 每日 Token 预算 | ✅ | 超额 429，委派也被拒 |
| 提醒 Reminders / 用量 Quota | ✅ | 提醒为 Tab 页，只落库、不推送；用量看板从设置页「用量」进入 (不再是 Tab)，不显示账号分组 |
| 语音输入 Voice input | ✅ (未实测) | Web `/api/transcribe`；iOS Speech 框架 |
| 语音播放 TTS | ✅ | 用户 + Bot 气泡 🔊，本机 TTS；设置里可关闭 |
| 设置页 Settings | ✅ | 首页头像入口；账号 → 用量 → 通用 (外观 / 通知 / 触感反馈 / 语言) → 语音 → 关于 → 退出登录 (最底部)。右上角 🐞 进入「调试」页：服务器地址、健康检查、版本 / 构建信息 |
| 照片头像 Avatars | ✅ (API) / 🟡 (iOS 待 Mac 模拟器点测) | 用户与每个 Bot：相册设置、更换（iOS 不再提供「恢复默认」入口，后端 DELETE 保留）；服务端 512 JPEG、按用户隔离。iOS 用 PhotosPicker；Linux 上未做 Xcode / 模拟器点测 |
| 导航 Navigation | ✅ | 二级页面隐藏 Tab 栏；对话标题 → Bot 详情 sheet；首页原生圆形按钮；头像统一正圆 (`CircleAvatar`)；工具栏取消 / 关闭为系统圆形 X (`DismissToolbarButton`) |
| 键盘 Keyboard | ✅ | 输入栏随键盘上移、点空白 / 下拉收起、表单 next、多行人设 / 指令、sheet 保存后布局正常 |
| 视觉风格 Visual style | 🟡 待验收 | 白底 + 灰分组、iOS 26 Liquid Glass (旧系统回退)、主题语义色集中在 `Core/UI/Theme.swift`、深色模式 |
| 输入栏 Composer | 🟡 待验收 | 浮动玻璃：圆形 ＋ (附件占位菜单) + 胶囊输入框 + 🎙；无发送按钮，return 发送 |
| 消息富文本 Rich messages | 🟡 待验收 | Markdown 排版、自动识别网址 / 电话 / 邮箱、网页在 App 内打开、长按复制；解析有单元测试 |
| App 图标 / 名称 | ✅ | 主屏「Vera Bot」；AppIcon 1024 单尺寸 |
| 附件 Attachments | 🟡 占位 | ＋ 菜单：图片 / 相机 / 文件「即将支持」(禁用) |

## 2. 已知限制 (Known limits)

- **iOS 与 Web 不对等**：Web SPA 没有迭代 2 的 iOS UI 改动 (权限编辑、协作记录、设置页、TTS)，也没有 2026-10-01 之后的改动 (昵称编辑、照片头像、调试页、通用设置、列表时间 / 搜索、Liquid Glass 视觉、浮动输入栏、富文本 / App 内网页)，只作为 API 验收客户端。
- **HEIC**：服务端能认出 HEIC 文件头；未安装 `pillow-heif` 时返回 415。iOS 在上传前把相册图片转成 JPEG，不依赖服务端解 HEIC。
- **头像存在 SQLite `avatars.data`**：512 JPEG，单张大约几 KB 到几十 KB。备份数据库即包含头像。
- **提醒不推送**：没有 APNs / 本地通知。设置里的「通知」开关只申请系统授权并保存偏好，目前不会发出任何通知。
- **语言**：App 声明了 zh-Hans 与 en 本地化（仅 `InfoPlist.xcstrings`：显示名与权限文案），系统设置中可按 App 切换语言；但界面文案仍是中文硬编码，切到英文后 App 内界面仍为中文。
- **列表时间不会自动跨天刷新**：停留在首页跨过午夜时，「HH:mm」不会自己变成「昨天」；回到首页或下拉刷新后更新。「本周」按系统日历的周（中文地区周一开始）计算。
- **首页搜索暂延期扩展**：搜索入口保留；当前只过滤屏幕上已加载的列表（Bot 名称 + 最后一条消息预览），完整聊天历史搜索、搜索历史等移至后续迭代。
- **记忆**：滑动窗口 (最近 N 条)，没有摘要 / 向量检索。
- **安全**：Token 存 UserDefaults / localStorage (生产应改 Keychain / HttpOnly Cookie)，没有刷新 Token、没有速率限制 (Rate limit)，CORS `*`，ATS 允许本地 HTTP。
- **云端 TTS**：只是占位 (stub)，设置里置灰。
- **后端不会开机自启**：Mac 重启后需要重新运行 `backend/start.sh --detach` (或双击 `start.command`)；日志在 `backend/data/server.log`。
- **Docker 未实测**：`Dockerfile` / `docker-compose.yml` 已提供，`docker compose config` 校验通过；但测试机的 Docker daemon 未运行，镜像没有实际构建 / 运行过。
- **Bot 详情 sheet 内没有键盘「完成」按钮** (KB-12 修复所致)：用 下拉表单 / 保存 / 关闭 收起键盘。
- **文案过时**：新建 Bot 表单页脚仍写「创建后可在对话页右上角「Bot 设置」中开启」，现在的入口是「对话页点标题 → Bot 详情」(待改，重构时按「不改行为」原则未动)。
- **截图过时**：全部 iOS 截图早于 2026-10-01 的界面改动；`R34_form_keyboard` 仍显示已移除的键盘工具栏「完成」；`R11_settings` 是旧的分组顺序 (语音在前)。
- **来源不明的文件**：`frontend/ios/VeraBot/File.txt` (8 字节，内容「QA回归」)，重构时原样保留，待确认是否删除 (NEW-03)。

## 3. 未测 / 仅代码审查 (Untested / code review only)

| 项目 | 状态 |
|---|---|
| TC-31 语音输入 (`/api/transcribe`、iOS 麦克风) | 跳过 (按要求) |
| KB-04 交互式下拉收起键盘 | 代码审查 (模拟器鼠标拖动难以复现) |
| KB-08 进入后台收起键盘 | 代码审查 |
| KB-09 登录 / 新建 Bot 表单键盘行为 | 代码审查 |
| TC-07 Token 失效、TC-29 ＋ 菜单、TC-30 断网气泡 | 沿用迭代 1 结果，迭代 2 未重新点测 |
| 真机 (Real device) | 未测，只在 iPhone 17 模拟器 (iOS 26) 上测试 |
| 昵称 / 照片头像的 iOS 界面 | 代码已接上 API；本环境没有 Xcode，模拟器点测留到 Mac（步骤见 [RUN_LOCAL.md](ops/RUN_LOCAL.md)） |
| 首页正圆头像、圆形 X 取消 / 关闭、行时间、首页搜索 (UI-11~14) | 已在 iPhone 17 模拟器 (iOS 26) 构建、安装、启动；界面效果待 Boss 验收 |
| iOS 17 / 18 旧系统 | 未测 (`defaultScrollAnchor` 等 iOS 18+ API 已做版本判断) |
| 白底 + Liquid Glass、深色模式 (UI-16~19) | 已在 iPhone 17 模拟器 (iOS 26) 构建、安装，浅色 / 深色目视检查首页、设置、对话、Bot 详情；新建 Bot / 提醒 / 登录 / 调试页待 Boss 验收 |
| 浮动玻璃输入栏 (UI-20)、return 发送 | 已构建、安装、启动；按 Boss 要求本轮不做模拟器点测，待 Boss 验收 |
| 消息富文本 / App 内网页 / 长按复制 (MSG-01~04) | 解析 `swift test` 通过；App 已构建、安装、启动；按 Boss 要求本轮不做模拟器点测，界面待 Boss 验收 |
| 动态字体 (Dynamic Type)、iPad | 未测 |

## 4. 下一步 (Next steps)

0. **(暂停中)** Boss 评审 [MCP_CAPABILITY.md](design/MCP_CAPABILITY.md) 与 [GMAIL_CAPABILITY.md](design/GMAIL_CAPABILITY.md)；通过后按 M0 → M1 … 实施 MCP 能力与 Gmail。
1. Boss 验收 2026-10-01 的界面改动 (UI-04~20、MSG-01~04、UI-AV / UI-NK)；修正新建 Bot 表单页脚的过时文案；按新界面重新截图 (至少 R11、R34 与新 UI 用例)。
2. 补测 TC-07 / TC-29 / TC-30、KB-04 / 08 / 09，以及真机测试 (语音输入、TTS、键盘)。
3. 提醒推送：本地通知 (UNUserNotificationCenter) 或 APNs。
4. 附件：图片上传 + 多模态模型。
5. 云端 TTS：后端 `/api/tts` + 实现 `CloudTTSEngine`。
6. 安全加固：Keychain、刷新 Token、Rate limit、HTTPS / 移除 ATS 例外、收紧 CORS。
7. 后端常驻：launchd plist (开机自启 + 崩溃重启)；实测 Docker 镜像。
8. 记忆：长对话摘要压缩 (summarization) 与长期记忆。
9. Web SPA 跟进 iOS 的权限编辑 / 协作记录 UI (如果还需要 Web)。
10. 确认 `frontend/ios/VeraBot/File.txt` 是否删除 (NEW-03)。
11. 配置 CI (后端 mock 测试 + `swift test` + xcodebuild)。远程仓库已配置 (GitHub `luisporschewind-ai/VeraBot`)。
