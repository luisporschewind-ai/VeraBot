# 项目状态 (STATUS) — 2026-10-03

## v0.1.0 · 原型验证完成 (Prototype validated, feasible)

| 项 | 状态 |
|---|---|
| 结论 | ✅ 原型验证完成，方案可行：多 Bot 私聊 + 多 Agent 协作 (权限 / 隔离 / 护栏 / 审计) + SSE 流式 + 工具调用在 iOS 模拟器 + 本机后端上端到端跑通 |
| 版本 | git tag `v0.1.0`；后端 `verabot 0.1.0`。已发布包为 schema v2；当前未发布改动在启动时迁到 **schema v6**（v3 昵称 + 照片头像；v4 长期记忆；v5 Bot 标签；v6 Bot 置顶）。iOS `0.1.0 (1)` |
| 测试 | v0.1.0 原始回归快照：**91 条用例：通过 90 / 失败 0 / 跳过 1** (当时 TC-31 按要求跳过)，见 [TEST_CASES_v0.1.md](testing/TEST_CASES_v0.1.md)；2026-10-01 后续手工验收结果见该文档「后续手工验收」。之后新增：AV / NK 21/21 (API)、MEM 36/36 (记忆，mock)、MA 25/25 (含 MA-25 用量契约)、TAG 8/8 (Bot 标签)；UI 剩余验收已列为延期项。|
| 交付 | 后端 `dist/VeraBot-backend-v0.1.0.zip` (一键启动)；iOS Xcode 工程 + SPM 本地包；见 [DELIVERY.md](ops/DELIVERY.md) |
| 运行环境 | macOS Intel (MacBook Pro 13" 2018)、Xcode 26.0.1、iPhone 17 模拟器 (iOS 26)、Python 3.12 (uv)、DeepSeek `deepseek-chat` |

## 🔁 交接 (Handoff for the next agent) — 2026-10-03 UTC+8

- **HEAD**：功能与文档均已提交并推送 (置顶 `c5529ce`、首页头像正圆 `3504fef`、App 图标亮 / 暗色 `832cdb0`，及本次文档对齐)，分支 `main`，仓库 `/Users/admin/Desktop/VeraBot-v0.1` (Mac)，origin `github.com/luisporschewind-ai/VeraBot`。
- **不要提交的本地改动**：`frontend/ios/VeraBot.xcodeproj/project.pbxproj` (`DEVELOPMENT_TEAM = 4M4EACBGAJ`，Boss 签名) 与 `frontend/ios/VeraBot/InfoPlist.xcstrings`。只 `git add` 自己的文件。不动 tag `v0.1.0`。
- **规则**：前后端同步 (字段 / 文案 / 上限改动要有契约测试并写对照表)；Web 冻结 (只在 STATUS 记落后项)；iOS 只用原生默认样式、无自定义动画、Theme 语义色、头像正圆 (照片或表情 + 底色)；代码、测试、文档 (CHANGELOG / FEATURES / TEST_CASES / STATUS) 同一提交；作者 `Luis <luisporschewind@gmail.com>`；不做 UI 自动化 / 点按 / 截图；只装 **iPhone 17 模拟器** (UDID `6FD1E62D-DA65-42B1-81F5-554042006671`)，不装真机；不用 Homebrew。
- **构建 / 测试**：`frontend/ios`：`xcodebuild -project VeraBot.xcodeproj -scheme VeraBot -sdk iphonesimulator -destination "id=<UDID>" -derivedDataPath /tmp/verabot_dd build`；Kit `swift test` (当前 88 条)；后端置顶/标签用例：`uv run python scripts/test/{bot_pin_test,bot_tags_test}.py`。
- **后端启动**：`backend/stop.sh` 后 `backend/start.sh --detach` (默认 `0.0.0.0:8000`，日志 `data/server.log`)；健康检查 `curl http://192.168.0.104:8000/api/health`；demo / verabot2026。
- **近期更新**：Bot 置顶已实现 (schema v6；见 [BOT_PIN.md](design/BOT_PIN.md))，本机数据库迁移前备份 `backend/data/verabot.db.bak-before-v6`。
- **验收记录 (2026-10-01)**：Boss 确认 Bot 置顶功能无问题；TC-07 无效 token 返回 401 后自动回登录页；TC-29/30、设置、首页与导航、主要列表、消息、头像/昵称，以及触感反馈、语音、键盘相关验收通过。余下详情/创建页、长期记忆、用量、标签细节、删除流程及部分视觉页验收由 Boss 同意延期，不阻塞当前任务。详见测试用例记录。
- **2026-10-03**：首页左上角头像外的 iOS 26 玻璃胶囊底已关掉 (`.sharedBackgroundVisibility(.hidden)`)，头像 44pt 正圆，与右侧按钮等大；Boss 已验收 (UI-11b)。
- **2026-10-03**：iOS 界面残留英文 tokens 已改为「用量」(委派 Trace 行、用量看板、额度用完提示)；待 Boss 验收 (UI-EN-01)。
- **2026-10-03**：VeraBotCore 新增执行状态机 `ExecutionStateMachine` (8 种状态，由现有 SSE 事件推导，`ChatViewModel` 只读暴露，界面未改，后端未改)；`swift test` 74/74 (EXEC-01~19)。
- **2026-10-03**：执行状态机 v1.1：后端新增 SSE `status` 事件 (`recalling` / 委派内部 `thinking` / `tool`，`{phase, depth, bot_name, tool, parent_id}`)，`status_event_test.py` 8/8 (含契约)；Core 新增 `recalling`、`delegating.progress`、短暂受阻 `blocked` (1.2 s 自动回到原流程)；头像实验室新增「回复中」「委派中」、持续状态可见时循环、按状态机演示。`swift test` 88/88；回归 MA 25/25、MEM 36/36、AV/NK 21/21、TAG 10/10、PIN 8/8。**Web 落后**：不处理 `status` 事件 (冻结，忽略即可，无报错)。
- **待办**：
  1. **执行状态机**：v1.1 已完成 (后端 `status` 事件 + Core 新状态 + 头像实验室映射，见 [EXECUTION_STATE.md](design/EXECUTION_STATE.md))；对话页尚未显示状态，界面方案待 Boss 决定；实验室角色色仍为固定色值，正式使用前需换 Theme 语义色、支持深色模式。
  2. **头像动画** (Boss 桌面的 `LiveBotAvatar.swift` 卡通头像)：**未决定**；与项目同名类 / `Color(hex:)` 冲突，且是自定义动画，违反现有规则，需 Boss 拍板是否例外。
  3. **仓库清理记录**：`frontend/ios/VeraBot/File.txt` (QA 遗留，内容「QA回归」) 已在 `c5529ce` 删除，工作区无残留 (见 TEST_CASES NEW-03)。

## 📍 当前进度 (Current progress) — main 工作区 (2026-10-01)

v0.1.0 之后的改动都在 `main` 上，尚未发版 (见 [CHANGELOG.md](CHANGELOG.md) [Unreleased])。数据库已到 **schema v6** (v4 长期记忆；v5 Bot 标签；v6 Bot 置顶，迁移前备份 `backend/data/verabot.db.bak-before-v6`)；iOS 版本号仍为 `0.1.0 (1)`.

### 功能实现与验收状态 (Implementation and acceptance status)

| 项 | Commit | 验证情况 | 对应用例 |
|---|---|---|---|
| 浮动 Liquid Glass 输入栏 (圆形 ＋、胶囊输入框「向 {Bot 名} 提问」、🎙，无发送按钮、return 发送) | `46cb977` | Boss 手工验收通过 | UI-20 |
| 消息富文本 (Markdown：标题 / 列表 / 代码块 / 引用 / 表格等，`~` 原文显示) | `4f4cd49` | `swift test` 通过；Boss 手工验收通过 | MSG-01、MSG-02 |
| 链接：网址在 App 内 `SFSafariViewController` 打开，电话 / 邮箱交给系统；长按复制全文 / 复制链接 | `4f4cd49` | Boss 手工验收通过 | MSG-03、MSG-04 |
| 白底 + Liquid Glass 视觉风格、沉浸式助理列表、主题语义色 (theme tokens，`Core/UI/Theme.swift`)、深色模式 | `c94e26b` | 首页、设置、对话和主要列表已验收；登录、提醒、调试等其他页面验收延期 | UI-16~19 |
| 对话标题胶囊按钮 | `b59bf7a` | Boss 手工验收通过 | UI-15 |
| 正圆头像、圆形 X 取消 / 关闭、列表行时间、首页按需搜索 (范围暂定) | `36d96a7`、`8e0c585`、`3139826` | Boss 手工验收通过 | UI-11~14 |
| 设置页重排 (账号 → 用量 → 通用 → 语音 → 关于 → 退出登录)、调试页 🐞、用量移入设置、通用 (外观 / 通知 / 触感反馈 / 语言) | `15cfbe8` | Boss 手工验收通过 | UI-04~09、SET-10 |
| 用户 / Bot 照片头像 + 可编辑昵称 (Stuart 实现，schema v3) | `07d0716` | 后端 `avatar_profile_test.py` 21/21；Boss 手工验收通过 | AV-*、NK-*、UI-AV-01/03、UI-NK-01 |
| **长期记忆 M1** (先确认后保存的记忆、确认卡片、「Vera 了解的你」、Bot 详情记忆分组、健康 / 财务加密、清空对话可选删记忆；schema v4) | 见 CHANGELOG | 后端 `memory_test.py` 36/36、MA 24/24、AV/NK 21/21；`swift test` 34/34；模拟器已构建 / 安装 / 启动；UI 验收延期 | MEM-*、MEM-UI-01~12、[MEMORY_GROWTH.md](design/MEMORY_GROWTH.md) §5.8 |
| 设置 › 用量 行右侧「已用 N%」(今日 Token / 今日额度，iOS 计算，后端未改) | 见 CHANGELOG | MA-25 契约 25/25、`QuotaTests` 4 个；模拟器已构建 / 安装 / 启动；UI 验收延期 | QUOTA-03、QUOTA-04、UI-21 |
| **Bot 标签** (schema v5；同日重新设计：3 个 / 4 字，首页一个浅灰圆角矩形、详情卡片一行、对话标题不显示、「基本信息」内单输入框) | 见 CHANGELOG | 后端 `bot_tags_test.py` 10/10 (含存量收敛与前后端契约)；回归 MA 25/25、AV/NK 21/21、MEM 36/36；Kit 已测；iOS 标签 UI 验收延期 | TAG-01~10、TAG-UI-01~04 |
| **Bot 置顶** (schema v6；列表排序、名称旁 pin 标识、左滑 / 长按入口、置顶行浅灰底) | `c5529ce` | 后端 `bot_pin_test.py` PIN-01~08 通过；回归 MA 25/25、AV/NK 21/21、MEM 36/36、TAG 10/10；`swift test` 55 项通过；Boss 确认功能无问题 | PIN-01~08、PIN-UI-01~03 |
| **Bot 详情 / 创建页改版** (顶部卡片弹窗编辑头像 / 昵称 / 标签且「保存」才提交、「默认形象」分组、人设 / 指令独立分组、界面去英文、协作记录本地时间；仅 iOS) | 见 CHANGELOG | `swift test` 53/53；AV/NK 21/21；模拟器已构建 / 安装 / 启动；详情/创建 UI 验收延期 | DETAIL-UI-01~09 |
| **头像实验室** (独立页面；五款角色、六种状态、三种尺寸；不写入 Bot 资料) | `codex/avatar-lab-experiment`，未提交 | iPhone 17 模拟器构建 / 安装 / 启动通过；视觉手工验收待进行 | AVLAB-01 |
| App 图标、主屏显示名「Vera Bot」 | `b5eccd9`、`d824796` | 已构建 | — |
| 去掉列表数量页脚、账号信息并入设置、移除「恢复默认头像」入口 | `8794552` 等 | 对应 UI 验收延期 | UI-01~03、UI-10 |

### 暂停 / 延期 (Paused / deferred)

| 项 | 状态 |
|---|---|
| MCP 能力、Gmail 接入 | ✅ 设计 v1.0 已批准 (2026-10-01，决定 D1~D10)；**开发等待额度重置后从 M1 开始**，未写实现代码 (见下一节) |
| 以记忆为核心的 Bot 成长体系 M2~M5 (摘要、风格校准、隐式候选、成长界面、向量检索) | 📝 方案 v1.0 已批准，M1 已实现；M2 起未开始 |
| 首页搜索扩展 (完整聊天历史搜索、搜索历史) | ⏸ 延期到后续迭代；当前只过滤已加载列表 |

### 已知遗留 (Known leftovers，仅列出，未处理)

- **Web 客户端落后于 iOS**：没有迭代 2 的 iOS UI，也没有 2026-10-01 之后的全部 iOS 改动 (见 §2 第一条)。**设置 › 用量「已用 N%」没有 Web 对应** (Web 冻结；Web 用量页仍是原有额度进度条，`/api/quota` 未变，不受影响)。**Bot 标签与置顶没有 Web UI** (Web 冻结；后端字段向后兼容)。**Bot 详情改版 (卡片弹窗编辑、默认形象分组、去英文、协作记录本地时间) 没有 Web 对应** (Web 冻结；未改 API)。**记忆 M1 没有 Web UI**：Web 不显示确认卡片 (记忆工具结果显示为普通工具卡片，无法在 Web 确认)，没有记忆页与 `memory_access` 设置；后端接口向后兼容，Web 现有功能不受影响。
- **截图过时**：`assets/screenshots/ios/` 下全部截图早于 2026-10-01 的界面改动；其中 `R34_form_keyboard`、`R11_settings` 与当时的界面也已不符。新 UI 用例 (UI-*、MSG-*) 尚无截图。
- **设计稿中的 schema 版本号**：v3 = 头像 / 昵称、v4 = 记忆、**v5 = Bot 标签**、**v6 = Bot 置顶**、MCP / Gmail 设计稿 (v1.0) 使用 **v7**。

## ⏸ 设计已定稿：MCP 开发等待额度重置 (Design approved, development waits for quota reset)

Boss 决定把 MCP (Model Context Protocol) 作为 VeraBot 的一等能力，Gmail 优先通过 MCP 接入。两份设计稿已于 2026-10-01 由 Boss 批准为 **v1.0** (全部开放问题已决定)；以记忆为核心的 Bot 成长体系方案 v1.0 已批准，M1 已实现 (见上)。

| 能力 | 设计文档 | 状态 | 需要 Boss 做的事 |
|---|---|---|---|
| MCP 能力 (MCP Client、OAuth 2.1、工具映射、权限、HITL、防注入) | [MCP_CAPABILITY.md](design/MCP_CAPABILITY.md) | ✅ v1.0 已批准 (§16 决定 D1~D10) | 额度重置后开始 M1 |
| Gmail (主路径：Google 官方 Gmail MCP；备用：直连 Gmail API) | [GMAIL_CAPABILITY.md](design/GMAIL_CAPABILITY.md) | ✅ v1.0 已批准 (§16 Q1~Q12 已决定) | M4 之前：创建 Google Cloud 项目 (Testing 模式) 并加入 Google Workspace Developer Preview Program (§14) |
| 以记忆为核心的 Bot 成长体系 (显式记忆 + 记忆页 → 摘要 / 风格校准 → 隐式候选 / 主动建议 / 快捷提问 → 成长界面 / 月度回顾 → 向量检索 / 协作优化) | [MEMORY_GROWTH.md](design/MEMORY_GROWTH.md) | ✅ v1.0 已批准，M1 已实现 (决定见 §17.1) | 按 MEM-UI-01~12 与 §5.8 验收 M1；决定是否开始 M2 |

**MCP / Gmail 设计已于 2026-10-01 由 Boss 批准为 v1.0，尚未写任何实现代码；开发等待额度重置后按 MCP 文档 §15 的 M1~M7 进行** (M1 = MCP Client 核心 + 公网免授权只读服务；Gmail 在 M4~M6)。原 M0 / G0 技术验证已取消，Google 相关验证在 M4 开始时进行。记忆 M1 占用 schema v4，Bot 标签占用 v5，Bot 置顶占用 v6；MCP / Gmail 使用 **v7**。

## 1. 已完成功能 (Features done)

| 模块 | 状态 | 说明 |
|---|---|---|
| 账号 Accounts | ✅ | 注册 / 登录 (bcrypt + JWT)，Token 持久化，失效自动退出，设置页底部退出登录 (二次确认)。昵称 `PATCH /api/me`（设置页可编辑；首页与对话读同一 `AppState`） |
| 租户隔离 Isolation | ✅ | 所有查询带 `user_id`，越权 (IDOR) 返回 404 |
| Bot 管理 | ✅ (API) / 🟡 (标签部分 UI 延期) | 创建 (＋)、编辑 (Bot 详情 / 长按「编辑与权限」)、左滑删除；置顶支持左滑 / 长按，置顶项优先排序且 Boss 已验收；标签 UI 与 Bot 详情/删除流程验收延期；软上限 20 (`MAX_BOTS_PER_USER`)；名称右侧显示标签，行右上角显示最后消息时间；搜索只过滤已加载的 Bot 名称与最后消息预览，完整聊天历史搜索、搜索历史等延期 |
| 流式对话 SSE | ✅ | 逐 token 渲染、工具卡片、交接 Trace 卡片、错误气泡 |
| 记忆 Memory | ✅ | 显式长期记忆 M1、每 Bot 记忆分组、最近 20 条对话窗口；M1 UI 验收延期，M2+ 摘要 / 向量检索尚未开始 |
| 工具 Tools | ✅ | 天气 (Open-Meteo)、创建 / 查询提醒、`ask_bot` |
| 多 Agent 协作 | ✅ | 工具白名单、委派白名单、接受委派、上下文隔离、深度 / 环路 / 单轮上限 / Token 预算、审计日志、协作记录页 |
| 每日 Token 预算 | ✅ | 超额 429，委派也被拒 |
| 提醒 Reminders / 用量 Quota | ✅ | 提醒为 Tab 页，只落库、不推送；用量看板从设置页「用量」进入 (不再是 Tab)，不显示账号分组 |
| 语音输入 Voice input | ✅ (Boss 手工验收通过) | Web `/api/transcribe`；iOS Speech 框架 |
| 语音播放 TTS | ✅ | 用户 + Bot 气泡 🔊，本机 TTS；设置里可关闭 |
| 设置页 Settings | ✅ | 首页头像入口；账号 → 用量 → 通用 (外观 / 通知 / 触感反馈 / 语言) → 语音 → 关于 → 退出登录 (最底部)。右上角 🐞 进入「调试」页：服务器地址、健康检查、版本 / 构建信息 |
| 照片头像 Avatars | ✅ | 用户与每个 Bot：相册设置、更换（iOS 不再提供「恢复默认」入口，后端 DELETE 保留）；服务端 512 JPEG、按用户隔离。Boss 已验收头像与昵称相关 iOS 流程 |
| 导航 Navigation | ✅ | 二级页面隐藏 Tab 栏；对话标题 → Bot 详情 sheet；首页原生圆形按钮；头像统一正圆 (`CircleAvatar`)；工具栏取消 / 关闭为系统圆形 X (`DismissToolbarButton`) |
| 键盘 Keyboard | ✅ | 输入栏随键盘上移、点空白 / 下拉收起、表单 next、多行人设 / 指令、sheet 保存后布局正常 |
| 视觉风格 Visual style | 🟡 部分验收 | 白底 + 灰分组、iOS 26 Liquid Glass (旧系统回退)、主题语义色集中在 `Core/UI/Theme.swift`、深色模式；未覆盖页面验收延期 |
| 输入栏 Composer | ✅ | 浮动玻璃：圆形 ＋ (附件占位菜单) + 胶囊输入框 + 🎙；无发送按钮，return 发送；Boss 已验收 |
| 消息富文本 Rich messages | ✅ | Markdown 排版、自动识别网址 / 电话 / 邮箱、网页在 App 内打开、长按复制；解析有单元测试，Boss 已验收 |
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
- **记忆**：长期记忆 M1 已实现但 UI 验收延期；摘要 / 向量检索属于 M2+，尚未开始 (方案见 [MEMORY_GROWTH.md](design/MEMORY_GROWTH.md))。
- **安全**：Token 存 UserDefaults / localStorage (生产应改 Keychain / HttpOnly Cookie)，没有刷新 Token、没有速率限制 (Rate limit)，CORS `*`，ATS 允许本地 HTTP。
- **云端 TTS**：只是占位 (stub)，设置里置灰。
- **后端不会开机自启**：Mac 重启后需要重新运行 `backend/start.sh --detach` (或双击 `start.command`)；日志在 `backend/data/server.log`。
- **Docker 未实测**：`Dockerfile` / `docker-compose.yml` 已提供，`docker compose config` 校验通过；但测试机的 Docker daemon 未运行，镜像没有实际构建 / 运行过。
- **Bot 详情 sheet 内没有键盘「完成」按钮** (KB-12 修复所致)：用 下拉表单 / 保存 / 关闭 收起键盘。
- **截图过时**：全部 iOS 截图早于 2026-10-01 的界面改动；`R34_form_keyboard` 仍显示已移除的键盘工具栏「完成」；`R11_settings` 是旧的分组顺序 (语音在前)。

## 3. 未测 / 仅代码审查 (Untested / code review only)

| 项目 | 状态 |
|---|---|
| TC-07 Token 失效处理 | 通过：无效 token 时 `/api/me` 返回 401，App 自动跳转登录页 (iPhone 17 模拟器，2026-10-01) |
| 真机 (Real device) | 设备型号 / 环境未记录；不要据此推断 iPhone 17 模拟器之外的平台都已覆盖 |
| 真机 (Real device) | 未测，只在 iPhone 17 模拟器 (iOS 26) 上测试 |
| 昵称 / 照片头像的 iOS 界面 | Boss 手工验收通过 (2026-10-01) |
| 首页正圆头像、圆形 X 取消 / 关闭、行时间、首页搜索 (UI-11~14) | Boss 手工验收通过 |
| iOS 17 / 18 旧系统 | 未测 (`defaultScrollAnchor` 等 iOS 18+ API 已做版本判断) |
| 白底 + Liquid Glass、深色模式 (UI-16~19) | 首页、设置、对话、主要列表已验收；新建 Bot / 提醒 / 登录 / 调试页验收延期 |
| 浮动玻璃输入栏 (UI-20)、return 发送 | Boss 手工验收通过 |
| 消息富文本 / App 内网页 / 长按复制 (MSG-01~04) | 解析 `swift test` 通过；Boss 手工验收通过 |
| 动态字体 (Dynamic Type)、iPad | 未测 |

## 4. 下一步 (Next steps)

1. **执行状态提示**：Core 状态机已完成 ([EXECUTION_STATE.md](design/EXECUTION_STATE.md))；界面显示方式 (文案 / 头像动画) 待 Boss 决定。
2. **遗留英文**：已修 (2026-10-03)，对话 Trace 行与用量看板的 tokens 改为「用量」，见 UI-EN-01。
3. **(等待额度重置)** 按 [MCP_CAPABILITY.md](design/MCP_CAPABILITY.md) §15 的 M1 → M7 实施 MCP 能力与 Gmail (设计 v1.0 已批准；Gmail 在 M4~M6，M4 前 Boss 需完成 Google Cloud 准备)。
4. 记忆 M1 UI 验收延期；完成后再决定是否开始 M2。
5. 其余 UI 验收、过时截图更新及提醒通知、图片附件 / 多模态、云端 TTS、安全与部署、CI、Web 方向暂缓；规划见 [ROADMAP_NEXT.md](ROADMAP_NEXT.md)。
