# 更新日志 (CHANGELOG)

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/)，版本号遵循 [SemVer](https://semver.org/lang/zh-CN/) (见 [CONTRIBUTING.md](../CONTRIBUTING.md))。时间为北京时间 (UTC+8)。

## [Unreleased]

### 新增 (Added)

- **Bot 置顶 (schema v6)**：新增 nullable `bots.pinned_at`，v5 → v6 幂等迁移且迁移前备份本地数据库。PATCH `/api/bots/{id}` 接受严格布尔 `pinned`，重复置顶保留原时间，取消置顶置空；Bot JSON 返回 `pinned_at`，仅列表 API 按置顶时间倒序、同时间 id 升序，其余 id 升序。iOS 首页支持左滑和长按置顶 / 取消置顶，置顶行使用主题浅灰底；搜索结果保持同序。Web 冻结。PIN-01~08、Kit 解码 / 编码 / 排序用例覆盖。
- **Bot 标签 (tags，schema v5，启动时自动迁移)**：每个 Bot 有一组短标签。最新 main 上长期记忆已占用 schema v4，因此本迁移是 **v4 → v5**（任务描述里的 v3 → v4 对应的是记忆落地之前的库）。
  - 后端：`bots.tags`（JSON 字符串数组，默认 `[]`）。`init_db()` 幂等加列，不改写已有权限、记忆授权、头像或已写入的标签。`GET /api/bots`、`GET /api/bots/{id}` 的 Bot JSON 增加 `tags`。`POST /api/bots`、`PATCH /api/bots/{id}` 接受 `tags`；省略时创建为 `[]`、更新表示不修改；`[]` 清空。校验：trim，丢掉空白和重复（保留首次出现的顺序），最多 5 个，每个最多 12 个字，拒绝控制字符；422 中文（`标签必须是列表` / `标签必须是文字` / `标签不能包含控制字符` / `每个标签最多 12 个字` / `每个 Bot 最多 5 个标签`），不带 pydantic 的 `Value error` 前缀。仍按 `user_id` 隔离，他人访问 404。无新依赖、不改 `.env`。
  - iOS：`VeraBotCore` 的 `Bot.tags`（旧 JSON 缺字段或 null 时为 `[]`）、`BotCreate` / `BotPatch`，以及与后端一致的 `BotTagRules`。首页列表在名称右侧显示小胶囊（最多 2 个，其余 `+N`，过长截断）；对话页胶囊标题在名称右侧同样显示（最多 1 个）。创建 Bot、Bot 设置 / 详情用系统 Form「标签」分组添加、修改、左滑删除。对话页只改标题按钮，未改消息列表、记忆卡片或设置页。Web 未改。
  - 测试：`backend/scripts/test/bot_tags_test.py` TAG-01~08（8/8）；回归 MA 25/25、AV/NK 21/21、MEM 36/36（MEM-01 的版本断言改为当前 `SCHEMA_VERSION`，记忆列与存量数据断言不变）。Kit 增加 `BotTagTests`。Linux Swift 6.2 能类型检查 `BotTags` / `Models` / `Memory` 等 Core 源文件，并用独立程序跑通规则与解码；完整 `swift test` 编不过既有的 `MessageMarkdown.swift`（swift-corelibs-foundation 没有 Apple 的 Markdown / `NSDataDetector`），模拟器点测留到 Mac。
- **iOS · 设置 › 用量 显示已用百分比**：「用量」行右侧用系统 `LabeledContent` 次要文字显示「已用 N%」(NavigationLink 默认 value 样式，无自定义动画)。N = round(`today.total_tokens` / `daily_token_quota` × 100)，即今日 Token 占今日额度 (个人 `users.token_budget`，否则 `VERABOT_DAILY_TOKEN_QUOTA`，默认 200000) 的比例，与后端 429 拦截用的是同一对数值；超额时如实显示 > 100%。加载中 / 请求失败 / 额度 ≤ 0 时不显示数字。每次回到设置页重新拉取 `GET /api/quota`。
  - **后端未改动**：`/api/quota` 早已返回 `daily_token_quota` 与 `today.total_tokens`，不新增字段；百分比只在 iOS 计算 (`VeraBotCore` `Quota.usedPercent` / `usedPercentText`)。
  - 测试：`multi_agent_test.py` 新增 MA-25 (前后端契约：`/api/quota` 键 ⊇ iOS `Quota` / `UsageStats` CodingKeys，分子分母与 `db.token_budget` 一致)，25/25；`swift test` 新增 `QuotaTests` 4 个 (取整、0% / 100% / 超额、无额度、分子用今日而非累计)。用例 QUOTA-03 / QUOTA-04 / UI-21 见 TEST_CASES。
  - Web 冻结，未加此显示 (见 STATUS)。
- **长期记忆 M1 (Memory，schema v4，启动时自动迁移)** — 方案 [design/MEMORY_GROWTH.md](design/MEMORY_GROWTH.md) 升为 v1.0 (Boss 已批准，决定见 §17.1，实现说明见 §19)：
  - 后端：新表 `memories` 与 `bots.memory_access` (默认 `bot_and_global`，存量 Bot 同)、`users.memory_enabled` (默认开)、`messages.memory_ids`。新模块 `services/memory/` (策略检查、召回、确认流程、SQL)、`core/crypto.py` (Fernet；密钥 `VERABOT_MEMORY_ENC_KEY` 或自动生成的 `data/.memory_key`，与数据库分离)、`agents/memory_tools.py` (`remember` / `forget_memory` 只生成待确认提议；不进 `allowed_tools`；被委派时拒绝)。depth 0 的 system prompt 注入 `<user_memory>` (≤ 12 条 / 1000 字，带来源标签，声明是数据不是指令)。密码 / 验证码 / 密钥 / 证件号 / 卡号永不保存；健康 / 财务加密保存并标记敏感；trace 不含敏感正文；审计不写正文。新接口 `/api/memories*`、`/api/memory/settings`；`DELETE /api/bots/{id}/messages` 新增可选 `include_memories`；`done` 事件新增 `memory_ids`；`/api/tools` 新增 `memory`。全部向后兼容。新依赖 `cryptography` 50.0.2 (+ `cffi`、`pycparser`，共 48 个包)。
  - iOS：Kit `VeraBotCore/Memory.swift` (模型，未知枚举回退) 与 `VeraBotAPI` 记忆方法、`APIError.code`；`Features/Memory/`：对话内确认卡片 (记住 / 不用 / 编辑后记住，已记住可跳转)、「Vera 了解的你」(待确认 / 关于你 / 仅某 Bot 分组，左滑删除、编辑、＋ 添加、清空，首次打开说明会发送给 DeepSeek)、编辑页、设置 › 记忆 分组 (位于用量之后，含「允许 Bot 记住」总开关)。Bot 详情新增「记忆」分组 (`memory_access` Picker +「{Bot} 记住的内容」)；「清空对话」确认框改为「仅清空对话」/「清空对话和「X」的记忆」两个选项。全部原生控件 + Theme 现有样式，无自定义动画。
  - 测试：`backend/scripts/test/memory_test.py` MEM-01~36 (36/36，含前后端字段契约)；`MemoryTests` 14 个 (`swift test` 共 34/34)；MA 24/24、AV/NK 21/21 回归通过 (AV-01 改为断言当前 `SCHEMA_VERSION`)。
  - 文档：ARCHITECTURE、MULTI_AGENT_DESIGN、FEATURES、TEST_CASES、RUN_LOCAL、STATUS、backend README / `.env.example` 同步；MCP / Gmail 设计稿注明其迁移改用 schema v5。**Web 前端未改动** (无记忆 UI，见 STATUS)。
- **iOS · Bot 消息富文本 + App 内网页**：
  - Bot 回复气泡支持 Markdown：标题、段落（保留单换行）、粗体 / 斜体、行内代码、代码块（含语言标记，横向滚动，流式输出中未闭合也按代码块显示）、引用、有序 / 无序列表（含缩进）、表格（横向滚动）、分隔线；自动识别网址、电话、邮箱为可点链接。BUG-01 保持修复：行内代码以外的 `~` 一律按原文显示，不会变成删除线。
  - 解析在 `VeraBotCore/MessageMarkdown.swift`（纯 Foundation：块级解析自写，行内交给 `AttributedString(markdown:)`，自动链接用 `NSDataDetector`；无第三方依赖），新增 10 个 `swift test` 用例（`MessageMarkdownTests`）。排版在 `Core/UI/MessageContentView.swift`（原生 Text / Grid / ScrollView），替代原 `MessageRow.swift` 里的全局 `markdown()`；交接 Trace 的回答也改用 `MessageMarkdown.inline`。
  - 链接点按：`Core/UI/InAppBrowser.swift` 的 `.inAppBrowser()` 通过 `OpenURLAction`（`environment(\.openURL)`）接管对话页内所有 Text 链接：http / https 全屏打开 `SFSafariViewController`（`UIViewControllerRepresentable` 包装，品牌色控件，「完成」关闭）；`tel:` / `mailto:` 等交给系统。
  - 长按 Bot 气泡：系统上下文菜单「复制」全文 + 每个链接「复制链接 …」（电话 / 邮箱复制时去掉 `tel:` / `mailto:`）。原气泡上的 `.textSelection(.enabled)` 由该菜单取代。
- **iOS · 助理列表行时间**：每行右上角显示最后一条消息时间（没有消息时回退 Bot 创建时间），`footnote` + `secondary`：今天 `HH:mm`、昨天「昨天」、本周内「星期几」、更早 `M/d`、非今年 `yyyy/M/d`。格式逻辑在 `VeraBotCore/ListTimestamp.swift`（含单元测试）。后端 `GET /api/bots` 早已返回 `last_message.created_at` 与 `created_at`，**后端未改动**。
- **iOS · 首页搜索（范围暂定）**：导航栏右上角 ＋ 左边新增放大镜按钮，点按打开系统 `.searchable`（`navigationBarDrawer`），当前只按 Bot 名称和最后一条消息预览过滤屏幕上已加载的列表（`localizedStandardContains`），无结果显示系统 `ContentUnavailableView.search`；完整聊天历史搜索、搜索历史等移至后续迭代。
- **iOS · 设置页「通用」分组**（外观 / 通知 / 触感反馈 / 语言，均为系统原生控件，偏好存 `@AppStorage`，key 见 `SettingsKeys`）：
  - 外观：`Picker` 跟随系统 / 浅色 / 深色（`vb_appearance`），在 App 根视图用 `preferredColorScheme` 应用。
  - 通知：`Toggle`（`vb_notifications_enabled`，默认关）。打开时调用 `UNUserNotificationCenter.requestAuthorization`；被拒绝或系统里已关闭时开关回退，并弹窗提供「前往设置」（`openNotificationSettingsURLString`）。回到前台时与系统授权状态同步。目前 App 还不发送任何通知（提醒仍只落库），此开关只负责授权与偏好。
  - 触感反馈：`Toggle`（`vb_haptics_enabled`，默认开）。新增 `View.hapticFeedback(_:trigger:)`（`Core/UI/Haptics.swift`），包装系统 `sensoryFeedback` 并受开关控制；接入发送消息（轻触）、开始 / 结束语音输入（selection）、完成提醒（success）。
  - 语言：显示当前界面语言，点按打开系统「设置」中本 App 的页面（`UIApplication.openSettingsURLString`）按 App 切换语言。新增 `InfoPlist.xcstrings`（zh-Hans + en：显示名与麦克风 / 语音识别 / 局域网权限文案），App 包内有 `zh-Hans.lproj` 与 `en.lproj`，系统设置中才会出现「语言」选项。界面文案仍为中文硬编码，选英文后只有系统权限弹窗等为英文。
- **iOS · 调试页**：设置页导航栏右上角 `ladybug` 按钮（原生 toolbar item，NavigationLink push）进入「调试」：服务器地址、后端健康检查（`GET /api/health`，状态 + 模型，可重新检查）、版本 / 构建号 / Bundle ID / 系统版本 / 构建配置。`VeraBotAPI` 增加 `health()`，`VeraBotCore` 增加 `HealthStatus`。
- **iOS · 主屏显示名称**：应用在 iPhone 主屏显示为「Vera Bot」。
- **用户与 Bot 照片头像，以及可编辑昵称**（schema v3，启动时自动迁移）：
  - 后端：`POST/GET/DELETE /api/me/avatar` 与 `/api/bots/{id}/avatar`（multipart 字段 `file`）。校验 JPEG / PNG / WebP（HEIC 识别文件头；本环境未装 HEIC 解码器时返回 415，iOS 上传前会转成 JPEG）。超过 8MB → 413。服务端按 EXIF 转正、居中裁成正方形、压成 512×512 JPEG，按用户隔离写入 `avatars` 表。`DELETE` 恢复默认（用户回到昵称首字，Bot 回到 emoji）。`PATCH /api/me` 修改昵称（trim、1–32 字、拒绝空白和控制字符）。`GET /api/me`、登录 / 注册的 `user`，以及 Bot JSON 增加 `nickname` / `display_name` / `has_avatar` / `avatar_updated_at`。新依赖 Pillow 11.3.0（HPND，与 MIT 兼容）。
  - iOS：设置页账号区可改昵称、用系统 PhotosPicker 选图并圆形预览后上传、恢复默认 (「恢复默认」入口后已移除，见「变更」中的「iOS · 头像」)。首页左上角、设置、Bot 列表、对话标题、消息气泡、用量页读取同一份 `AppState` / `AvatarStore`（昵称和照片改完立即反映，不在每个页面单独重拉）。客户端上传前把图收成最长边 1024 的 JPEG。
  - 测试：`backend/scripts/test/avatar_profile_test.py`（AV-01–17、NK-01–04，21/21，含 v2→v3 迁移与租户隔离）。`multi_agent_test.py` 仍为 24/24。
- **iOS · App 图标**：新增 `Assets.xcassets/AppIcon.appiconset` (Xcode 26 单尺寸 1024×1024 universal，不透明白底，图案居中留白)，源图保存在 `assets/brand/app-icon-source.png`；工程设置 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` (pbxproj 与 project.yml 同步)。
- 设计文档 (未实现)：[design/MCP_CAPABILITY.md](design/MCP_CAPABILITY.md) — MCP 作为一等能力：后端作为 MCP Client (官方 Python SDK `mcp` v2，MCP 规范 2026-07-28)、Streamable HTTP (生产) / stdio (仅本地开发)、三层服务器注册表、远程服务器 OAuth 2.1 (PRM / PKCE / `resource` / `iss` 校验)、工具发现与 `mcp__{server}__{tool}` 命名空间、MCP 工具默认关闭且委派中禁用、按风险分级的人工确认 (HITL)、不可信结果包裹与污染标记、审计 / 超时 / 重试 / 熔断、Token 加密且不下发 App、iOS「连接的账号 / MCP 服务」、API 与 schema v3、MCP-01~30 测试、里程碑 M0~M5 与开放问题。
- 设计文档 (未实现，等待 Boss 评审)：[design/MEMORY_GROWTH.md](design/MEMORY_GROWTH.md) — 以记忆为核心的 Bot 成长体系实施方案 v0.1：`memories` 表与 schema v4 迁移、`bots.memory_access` (none / bot / bot_and_global) 与用户总开关、内置记忆工具 `remember` / `forget_memory` 只生成待确认提议 + 对话内确认卡片 (先确认后保存)、规则 + 关键词召回与 `<user_memory>` 包裹注入 (≤ 12 条 / 1000 字，带来源标签)、被委派 Bot 不读写记忆、敏感信息默认不存、`/api/memories*` 接口、iOS「Vera 了解的你」记忆页与 Bot 详情记忆分组、MEM-xx 测试、M1~M5 里程碑与工作量估算、风险与 12 个开放问题。
- 设计文档 (未实现)：[design/GMAIL_CAPABILITY.md](design/GMAIL_CAPABILITY.md) — Gmail 能力方案 (v0.2)，含 HITL 发送确认、权限与委派集成、测试计划和待 Boss 决策的开放问题。

### 变更 (Changed)

- **iOS · 首页左上角头像恢复正圆**：iOS 26 会给工具栏项套一层 Liquid Glass 共享底（按内容计算的胶囊，比 30pt 头像大），头像外面看起来不是圆的。`BotListView` 左上角 `ToolbarItem(.topBarLeading)` 在 `if #available(iOS 26.0, *)` 内加系统 `.sharedBackgroundVisibility(.hidden)`，只显示正圆头像，尺寸改为 44pt，与右侧搜索 / ＋ 圆形玻璃按钮等大；iOS 17~18 不变 (30pt)。`HomeAvatarLabel` 新增 `size` 参数。仅 iOS，后端未改，无自定义动画。用例 UI-11b。
- **文档 · Bot 置顶规格与交接**：新增 [design/BOT_PIN.md](design/BOT_PIN.md) (Boss 批准，未实现，预留 schema v6)；MCP / Gmail 设计稿迁移版本改为 **schema v7**；STATUS 新增交接一节 (HEAD、勿提交文件、规则、待办、启动命令)。仅文档。
- **iOS · 删除 Bot 需二次确认**：唯一的删除入口（首页列表左滑；长按菜单、Bot 详情没有删除）由 `.onDelete` 改为 `.swipeActions` 的「删除」按钮（`tint(.red)`，不用 destructive role，行不会先被移走），点按后弹出系统 `confirmationDialog`：标题「删除「名称」？」，说明删除 / 保留的内容（与后端 `DELETE /api/bots/{id}` 实际行为核对过），按钮「删除」(destructive) /「取消」。确认后才调用 API；失败时列表下方显示错误（原来静默忽略）。文案在 `VeraBotCore/BotDeletion.swift`。后端未改；遗留数据见 TEST_CASES BOTDEL-03。
- **iOS · Bot 详情 / 编辑与权限 / 创建 Bot 不能下滑关闭**：三个 sheet 都加系统 `.interactiveDismissDisabled()`（始终开启，无确认弹窗），只能点「关闭」/「取消」或「保存」/「创建」退出，避免未保存的改动被误丢。仅 iOS；用例 DETAIL-UI-09。
- **iOS · Bot 详情 / 创建页改版 (Boss 批准，仅 iOS，后端与 API 未改)**：
  - 顶部卡片 (Bot 详情与长按「编辑与权限」都显示)：点头像弹出系统 `confirmationDialog`「从相册选择」(系统 `photosPicker`) /「使用默认形象」(仅有照片时出现，保存时调用已有的 `DELETE /api/bots/{id}/avatar`)；点昵称、标签弹出系统 `alert` + TextField 修改，昵称不能为空 (最多 20 字，与后端一致)，标签与创建页同一套 `BotTagRules` (3 个 / 4 字)，不合法时确认后弹出错误并保留原值；无标签显示灰色「添加标签」。**所有改动 (含照片上传 / 删除) 只在点「保存」时提交**，「取消」/「关闭」全部丢弃；未保存的新照片先在卡片里预览。状态模型在 `VeraBotCore/BotProfileDraft.swift` (`PendingBotPhoto`：unchanged / replace / remove)。保存顺序：先 `PATCH /api/bots/{id}`，再上传或删除照片；照片失败时提示「其他修改已保存，头像未更新」并留在本页。
  - 「基本信息」改为「默认形象」：表情横排 + 与创建页相同的 8 色 (`BotLook`)，页脚「设置了相册照片时，优先显示照片。」；详情页 PATCH 现在会发送 `color`。去掉头像 + 昵称行、标签行和「从相册设置头像」按钮 (`BotAvatarPhotoControls` 删除)。
  - 人设 / 自定义指令在详情页和创建页都是独立分组 (标题「人设」「自定义指令」，占位用创建页例句，页脚「对其他 Bot 公开，协作时用来介绍自己。」「仅本 Bot 使用，不对其他 Bot 公开。」)。
  - 去掉英文：分组标题「工具权限」「委派」「协作记录」(入口行「查看协作记录」)；工具行不再显示原始工具名，名称取后端 `label`，缺失 / 为空 / 等于原始名时显示「未命名工具」(`ToolInfo.displayName`)；委派页脚「（ask_bot）」→「委派其他 Bot」；创建页最小权限说明改为「新 Bot 默认不开启工具、不参与委派。」(同时修掉了过时的「右上角 Bot 设置」入口描述)；协作记录时间改为本机时区 `yyyy/M/d HH:mm` (`ListTimestamp.fullLabel`)，「N tokens」→「用量 N」，拒绝原因「Token 额度已用完」→「今日额度已用完」。
  - 全部系统默认控件 / 弹窗，无自定义动画。测试：`swift test` 53/53 (新增 `BotProfileDraftTests` 7 个)；后端 AV/NK 21/21 回归。Web 冻结，未跟进 (见 STATUS)。
- **Bot 标签重新设计 (Boss 批准)**：上限改为**每个 Bot 最多 3 个、每个最多 4 个字** (后端 `core/tags.py` 的 `MAX_BOT_TAGS=3` / `MAX_TAG_CHARS=4`，`clean_tags` 与 iOS `BotTagRules` 同一套规则，422 文案「每个 Bot 最多 3 个标签」「每个标签最多 4 个字」)。字段仍是 `tags: string[]`，schema 仍为 v5，结构不变。
  - 存量数据：超限的旧标签按「去控制字符 → trim → 每个截到前 4 个字 → 去重 → 只留前 3 个」收敛 (`coerce_stored_tags`)；`init_db()` 每次启动幂等改写超限行，读取 Bot 时也再收敛一次，所以旧 Bot 带原标签 PATCH 不会 422。
  - iOS 首页行：名称后跟**一个**浅灰小圆角矩形 (`Color.sectionFill` #EFEFEE，圆角 5，不是胶囊)，文字为「搜索, 查询, 调研」，`.caption` 次要灰字、单行、尾部截断；名称优先；不再显示 `+N`；右侧时间不变 (`BotTagChip`)。
  - 对话页标题胶囊：只显示头像 + 名称，去掉标签。
  - Bot 详情头像卡片：名称下方显示「搜索, 查询, 调研」(footnote、次要灰字；无标签时不显示)。
  - 编辑：去掉单独的「标签」分组；Bot 详情「基本信息」与创建 Bot 的首个分组内新增一行原生「标签」输入框 (`BotTagsField`，占位「如：搜索, 查询, 调研」)，用英文 / 中文逗号、顿号或空格分隔；输入时即时校验，超限时下方红色 footnote 提示；保存用 `BotTagRules.parse` 的规范化结果。无自定义动画。
  - 测试：`bot_tags_test.py` 10/10 (TAG-06 改为 3 个 / 4 字；新增 TAG-09 存量收敛、TAG-10 前后端规则契约，读取 `BotTags.swift` 断言上限与文案)；`BotTagTests` 改为新上限并新增分隔符解析、展示往返 (`swift test` 46/46)；MA 25/25、AV/NK 21/21、MEM 36/36 回归通过。Web 冻结，未跟进 (见 STATUS)。
- **设计 · MCP / Gmail 定稿 (仅文档)**：[design/MCP_CAPABILITY.md](design/MCP_CAPABILITY.md) 与 [design/GMAIL_CAPABILITY.md](design/GMAIL_CAPABILITY.md) 升为 **v1.0 (Boss 已批准，2026-10-01)**：全部开放问题标为已决定 (决定 D1~D10：M1 先做 MCP Client 核心 + 公网免授权只读服务；schema v6 (批准时写 v5，同日 v5 已被 Bot 标签占用)；仅内置目录 / 运维配置；所有写操作 HITL 确认，含 `create_draft`；委派禁用 + taint；MCP 服务即能力包，分组开关 +「开启全部只读」；Face ID 推到 M6；本地部署 + iOS PKCE；里程碑改为 M1~M7，Gmail 在 M4~M6)；文中 schema v3 / v5 改为 v6。未写代码，MCP 开发等待额度重置 (见 STATUS)。
- **iOS · 登录页标题**：登录页大标题由「VeraBot」改为「Vera Bot」，与主屏显示名一致。
- **iOS · 分组灰与开关尺寸 (Boss 要求)**：
  - 主题色 `Color.sectionFill` (分组 Section / 卡片 / Bot 气泡 / 输入框底) 浅色由 `#F2F2F7` 改为 `#EFEFEE` (RGB 239, 239, 238)；深色仍为 `secondarySystemBackground` (sheet 内 elevated)。只改 `Core/UI/Theme.swift` 一处，所有引用该语义色的页面同步变化。用 `simctl io screenshot` 读模拟器帧缓冲，设置页 / Form 行 / sheet / 纯色块均为 (239, 239, 238)。Boss 测到的 (234, 234, 233) 不是 App 绘制造成的：在 Mac 屏幕上对 Simulator 窗口取色时，数值经过了 macOS 色彩管理 (Digital Color Meter 的显示色彩空间 / 显示器配置文件)，所以代码未改 (见 TEST_CASES UI-22)。
  - 开关缩小：新增 `CompactToggle` (`Core/UI/Theme.swift`)，内部仍是系统 `Toggle` (labelsHidden)，只把开关本体 `scaleEffect(0.85, anchor: .trailing)`；标题用 `LabeledContent` 放在左侧，禁用时变淡，VoiceOver 合并为一个元素。不自定义 ToggleStyle、无动画；scaleEffect 不改变布局尺寸，行高不变、不裁切。全部 7 个开关统一替换：设置 (通知、触感反馈、语音播放)、设置 › 记忆 (允许 Bot 记住)、Bot 详情 (工具权限、委派目标、接受委派)。
- **iOS · 对话标题与用户气泡**：导航栏胶囊标题去掉右侧下箭头，仍为头像 + 名称，点按仍打开 Bot 详情。用户自己的消息气泡上方不再显示昵称；Bot 一侧展示不变。
- **文档同步 (docs: sync progress and docs with code)**，对照 commit `4f4cd49` 的代码逐项核对：
  - [STATUS.md](STATUS.md)：新增「当前进度」一节 (已完成待 Boss 验收：浮动输入栏、富文本、链接 / App 内网页、视觉风格、设置页重排、头像 / 昵称等，附 commit 与用例；暂停：MCP / Gmail 设计待评审、首页搜索延期；已知遗留清单)；功能表补充视觉风格 / 输入栏 / 富文本 / App 图标与名称；测试行补充 v0.1.0 之后的用例。
  - [design/ARCHITECTURE.md](design/ARCHITECTURE.md)：`db` 模块改为 schema v3；iOS 模块树补 `Haptics`、`AvatarImage`、`HealthStatus`、DebugView、用量入口；主题表补 `brandLight` / `brandDark` / `codeFill` / `quoteBar`；章节编号按出现顺序修正 (§5 资料与头像、§6 关键设计决策)；记忆决策注明只有滑动窗口。
  - [design/MCP_CAPABILITY.md](design/MCP_CAPABILITY.md)：§11 设置页顺序更新为 账号 → 用量 → 连接的账号 / MCP 服务 → 通用 → 语音 → 关于 → 退出登录 (原文为过时的 账号 → MCP → 语音 → 关于)；注明 schema v3 已被头像 / 昵称占用，MCP 迁移实施时顺延。[GMAIL_CAPABILITY.md](design/GMAIL_CAPABILITY.md) 同步注明。
  - [design/MULTI_AGENT_DESIGN.md](design/MULTI_AGENT_DESIGN.md)：标注当前 schema v3；§8 `SignOutSettingsSection` 条目移回分组列表末尾 (原误放在调试页条目下)；首页名称改为「助理」。
  - [product/FEATURES.md](product/FEATURES.md)：标注同步到的 commit；新增 App 图标 / 名称、Web 客户端两行；记忆行注明窗口变量与无长期记忆。
  - [testing/TEST_CASES_v0.1.md](testing/TEST_CASES_v0.1.md)：注明全部 iOS 截图早于 2026-10-01 改动；SET-02 指向 SET-10 的现行顺序。
  - [frontend/README.md](../frontend/README.md)：目录树补 `MessageContentView` / `InAppBrowser` / `Haptics` / `AvatarImage` / `MessageMarkdown` / DebugView / 测试数量；Web 落后清单；显示名与图标。
  - [ops/RUN_LOCAL.md](ops/RUN_LOCAL.md) 增加视觉 / 输入栏 / 富文本验收入口；[ops/DELIVERY.md](ops/DELIVERY.md) 检查清单补 `avatar_profile_test.py` 与 `swift test` 数量；根 README 文档表补 MCP / Gmail 设计稿。
  - 下方较早条目中已被后续改动取代的描述 (设置页旧顺序、iOS「恢复默认头像」) 加注说明，不改原文。

- **iOS · 浮动 Liquid Glass 对话输入栏**：对话页底部输入栏改为浮动样式，去掉不透明底栏（`.bar`），消息可从输入栏下方滚过，仍用 `safeAreaInset(edge: .bottom)` 保证最后一条可见、随键盘上移。布局：左侧独立的圆形玻璃「＋」附件按钮（原占位菜单）；右侧胶囊玻璃输入框，占位文字「向 {Bot 名} 提问」，胶囊内尾部为 🎙 语音输入（录音中显示红色停止图标）。**移除「发送」按钮**：键盘 return 键（`.submitLabel(.send)` + `.onSubmit`）发送；多行输入框（`axis: .vertical`，1–5 行）里 return 也是发送而不是换行（检测到只新增一个换行时视为发送，粘贴的多行文本保留换行）；空内容或上一条仍在回复时不发送、文字保留。玻璃效果用 `Theme` 的 `glassSurface(in:)`（iOS 26 `.glassEffect(.regular.interactive())`）+ `GlassGroup`（`GlassEffectContainer`），iOS 17–18 回退 `regularMaterial`。「正在聆听」提示也放在玻璃胶囊里。
- **iOS · 白底 + Liquid Glass 视觉风格、沉浸式助理列表、主题色板 (Theme tokens)**：
  - 所有页面背景改为白色（深色模式为黑色）；分组列表 / 表单的 Section、卡片、Bot 回复气泡改用原页面灰底的浅色值 `#F2F2F7`（原 `systemGroupedBackground`），深色为 `secondarySystemBackground`（sheet 内自动取 elevated 值）——即「背景白、分组灰」反转。涉及设置、调试、用量、提醒、协作记录、新建 Bot、Bot 详情 / 编辑、对话页、登录页。
  - 「助理」首页 Bot 列表去掉圆角 inset grouped 分组，改为白底全宽 `.plain` 列表，`listRowSeparator(.hidden)` 无分隔线；保留头像、名称、时间、预览、系统 chevron，行上下 10pt 间距。
  - 颜色集中到 `Core/UI/Theme.swift`：语义色 `appBackground` / `sectionFill` / `brandSoft` / `botBubble` / `traceFill` / `insetFill`（`UIColor` 动态色，随 trait 解析，设置 › 外观 切换时全部一起更新）；容器 `ThemedForm` / `ThemedList`（白底 + 灰分组），修饰符 `themedPageBackground()`、`plainListRow()`、`themedFieldBackground()`。视图里不再写死颜色值。
  - 修复深色模式：`brandSoft`（表情选中底色、交接 Trace 卡片）增加深色变体 `#123D39`；Trace 卡片 / 气泡 / 输入框底色都改为带深色变体的语义色。
  - Liquid Glass（iOS 26 原生 API，`#available(iOS 26)` 判断，旧系统回退）：主操作按钮 `prominentButtonStyle()` → `.glassProminent`（回退 `.borderedProminent`，登录、创建第一个 Bot）；胶囊按钮 `glassButtonStyle()` → `.glass`（回退 `.bordered`，对话标题）；`glassSurface(in:)` → `.glassEffect(.regular.interactive())`（回退 `regularMaterial`）；`GlassGroup` → `GlassEffectContainer`。导航栏、Tab 栏、工具栏按钮沿用系统 iOS 26 默认玻璃。
  - 登录页：白色背景，输入框改为浅灰圆角底（`themedFieldBackground()`），替代 `roundedBorder`。

- **iOS · 对话标题胶囊按钮**：ChatView 的中心 Bot 标题保留原有 Bot 详情 sheet 点击行为与无障碍标签，改用 iOS 26 原生 Liquid Glass 胶囊按钮（头像 + 名称 + 下箭头）；iOS 17–18 回退为系统 bordered 胶囊按钮，避免与返回按钮产生视觉合并。
- **iOS · 首页导航栏与按需搜索**：移除首页大标题「我的 Bot」，改用紧凑 inline 导航栏，保留左上角头像与右上角两个独立的 Liquid Glass 圆形按钮（搜索在左、＋ 在右；iOS 26 在两个 `ToolbarItem` 之间插入 `ToolbarSpacer(.fixed, placement: .topBarTrailing)`，用 `if #available(iOS 26, *)` 包裹），并确保返回上级时不出现异常标题。搜索栏只有点按放大镜后才挂载 `.searchable`（`navigationBarDrawer(displayMode: .always)`，自动聚焦）；未激活时不挂载，下拉列表也不会露出搜索框。点圆形 X 取消后搜索栏收起并清空关键词。当前只过滤屏幕上已加载的列表（Bot 名称 + 最后一条消息预览），完整聊天历史搜索、搜索历史等移至后续迭代。
- **iOS · 取消 / 关闭按钮**：工具栏与 sheet 里的「取消」「关闭」统一改为系统圆形 X（新增 `Core/UI/DismissToolbarButton.swift`：iOS 26 用 `Button(role: .cancel / .close)` + `xmark`，呈现为 Liquid Glass 圆形按钮；iOS 17–18 回退 `role: .cancel` + `xmark`），无障碍标签仍为「取消」/「关闭」。涉及：新建 Bot、Bot 设置 / Bot 详情、头像预览。确认框 / alert 里的「取消」保持系统文字按钮。
- 文档同步：FEATURES / STATUS / TEST_CASES (新增 UI-11~14) / ARCHITECTURE §3.1 / frontend README。API 无变化。
- **iOS · 头像正圆**：新增 `Core/UI/CircleAvatar.swift`（固定等宽高 frame + `aspectRatio(contentMode: .fill)` + `clipShape(Circle())` + `fixedSize()`），`UserAvatar`、`HomeAvatarLabel`、`BotAvatar`、头像预览统一使用。修复首页左上角头像在导航栏按钮里被压成椭圆；没有照片时首字放在品牌色圆底上（30×30）。Bot 的表情头像也从圆角方形改成正圆（与照片头像一致）。
- **iOS · 设置页重排**：顺序改为 账号 → 用量 → 通用 (外观 / 通知 / 触感反馈 / 语言) → 语音 → 关于 → 退出登录。「账号」分组去掉「服务器」行（移到调试页）；「关于」只显示版本号，构建号等详细信息移到调试页。
- **iOS · 用量入口**：底部 Tab 移除「用量」（现在只有 助理 / 提醒）；「用量」成为设置页「账号」下方的一行，push 原有用量看板（`QuotaView` 去掉自带的 NavigationStack，标题 inline）。额度用完的错误提示改为「可在「设置 › 用量」查看」。
- **iOS · 头像**：移除用户和 Bot 头像的「恢复默认头像」入口（设置页账号区、Bot 详情），只保留从相册设置 / 更换。后端 `DELETE /api/me/avatar`、`DELETE /api/bots/{id}/avatar` 与 `VeraBotAPI.deleteMyAvatar()` / `deleteBotAvatar(botID:)` 保留未动（iOS UI 不再调用）。
- **iOS · Bot 列表**：移除列表底部的「已创建 N 个 Bot · 每个 Bot 的对话与记忆相互隔离 (已达上限 …)」页脚 (连同相关代码)；达到上限时右上角 ＋ 仍置灰。
- **iOS · 用量 / 设置**：「用量看板」页移除账号分组 (账号 / 服务器 / 退出登录)；账号信息合并进设置页原有的「账号」分组 (头像 + 用户名、服务器)，不再重复。「退出登录」移到设置页最底部，单独一组 (`SignOutSettingsSection`，系统 destructive 样式，保留「确定退出登录？」二次确认)。设置页顺序：账号 → 语音 → 关于 → 退出登录 (已被后来的「iOS · 设置页重排」取代)。
- 文档同步：FEATURES / STATUS / RUN_LOCAL / MULTI_AGENT_DESIGN §7–8 / TEST_CASES (新增 UI-01~03，更新 SET-08 / SET-10)。
- [design/GMAIL_CAPABILITY.md](design/GMAIL_CAPABILITY.md) v0.1 → v0.2：Gmail **主路径改为经 MCP 接入** Google 官方 Gmail MCP 服务器 (`gmailmcp.googleapis.com`，开发者预览)；新增候选 Gmail MCP 服务器评估 (许可证与可信度)；直连 Gmail REST API 降级为备用路径 (以进程内 MCP 服务器实现，工具名不变)；发送改为内置工具 `mail_send_draft` + 用户确认后 `drafts.send`，HITL 规则不变；取消 `oauth_connections` / `/api/connections/google/*`，并入 MCP 通用表与 API；里程碑改为 G0~G5 并依赖 MCP 里程碑。
- [STATUS.md](STATUS.md)：新增「当前状态：开发暂停，等待 Boss 评审」一节 (列出两份设计稿与 Boss 待办)；日期更新为 2026-10-01；「下一步」第 11 项更新 (远程仓库已配置)。
- 许可证：采用 [MIT License](../LICENSE) (Copyright (c) 2026 Luis Porsche)；根目录 / backend / frontend README 增加 License 小节；`scripts/package_backend.sh` 打包时附带 `LICENSE`。

---

## [0.1.0] — 2026-09-30 · 原型验证完成 (Prototype validated, feasible)

**结论**：私人 AI 助理团队 (多 Bot + 多 Agent 协作 + 流式对话 + 工具调用) 的原型已在 iOS 模拟器 + 本机后端上端到端跑通，91 条用例通过 90 / 失败 0 / 跳过 1，技术方案可行。
v0.1.0 包含当天的三部分工作：迭代 1 (MVP 基线)、迭代 2 (缺陷修复与功能完善)、工程化 (目录重构 + 交付)。数据库 schema v2；iOS `MARKETING_VERSION` 0.1.0 (build 1)。

### 工程化：目录重构与交付 (Restructure & delivery)

- **两个可独立交付的项目**：`backend/` (FastAPI) 与 `frontend/` (`ios/` + `web/`)，各自有 README、配置和运行说明；前后端只通过 HTTP API 交互。
- **后端分层 (无行为变化)**：原 `backend/*.py` 平铺结构拆为 Python 包 `verabot/`：`core` / `db` / `tools` / `services` / `agents` / `api/routers`，依赖方向 `api → services/agents → tools/db → core` (见 [ARCHITECTURE.md](design/ARCHITECTURE.md))。OpenAPI 与原版一致 (仅新增路由 tag)；mock 多 Agent 测试重构前后均 24/24。
- **后端依赖管理 uv**：`pyproject.toml` (直接依赖精确锁定) + `uv.lock` (44 个包，与验证环境一致) + 导出的 `requirements.txt`；Python 3.12 (`.python-version`)。
- **一键启动**：`backend/start.command` (macOS 双击) / `start.sh` (缺 uv 自动安装，官方源失败回退清华 tuna 镜像；按锁文件同步依赖；从 `.env.example` 创建 `.env` 并提示输入 DeepSeek Key；初始化数据库；启动，支持 `--detach` / `--setup-only`) / `stop.sh`；可选 `Dockerfile` + `docker-compose.yml`。
- **测试脚本修正 (只改测试，不改产品行为)**：`smoke_test.py` 适配迭代 2 (创建 Bot 后显式开通工具 / 委派；软上限读 `/api/bots` 的 `limit`；没有 `OPENAI_API_KEY` 时转写项 SKIP)；`api_regress.py` 修复 TC-13 计数差一 (off-by-one) 和变量 `s` 被覆盖导致的崩溃；`api_regress2.py` 结束时删除临时用户。
- **打包**：`scripts/package_backend.sh` → `dist/VeraBot-backend-v0.1.0.zip` (排除 `.venv`、`.env`、数据库、日志、JWT 密钥)。
- **iOS 模块化 (SPM)**：新增本地 Swift Package `frontend/ios/Packages/VeraBotKit`：`VeraBotCore` (模型 + SettingsKeys)、`VeraBotNetworking` (`VeraBotAPI` 协议 + `APIClient`)、`VeraBotTTS` (TTS)；App 源码按 `App/`、`Core/UI/`、`Features/*`、`Services/*` 分目录；App 通过协议 `any VeraBotAPI` 使用网络层。暂无第三方依赖，不使用 CocoaPods。`swift test` 4/4。
- **脚本归位**：测试脚本 → `backend/scripts/test/` (原 `~/vbqa` 下的 `api_regress*.py`、`api_test*.py` → `api_v01_tc*.py` 纳入仓库)；`seed_demo.py` → `backend/scripts/dev/`；Web 截图 / 语音测试 → `frontend/scripts/web/`；模拟器 UI 辅助 (`ui.sh`、click / drag 源码) → `frontend/scripts/sim/`；新增 `frontend/scripts/run_ios.sh`。
- **截图**：统一到 `assets/screenshots/{web,ios/test,ios/regress}`，iOS 截图压缩为 471×1024 JPEG；删除重复的 `_s.png`、早期 `sim_*` 截图和临时文件。
- **Git**：初始化仓库，`.gitignore` (密钥、数据库、`.venv`、DerivedData、临时截图、`dist/`)；`CONTRIBUTING.md` (代码与文档同 commit、文档清单、SemVer)；tag `v0.1.0`。
- **文档**：`docs/` 分为 `product/`、`design/`、`testing/`、`ops/`，新增 [STATUS](STATUS.md)、[RUN_LOCAL](ops/RUN_LOCAL.md)、[DELIVERY](ops/DELIVERY.md)、[FEATURES](product/FEATURES.md)，重写 [ARCHITECTURE](design/ARCHITECTURE.md)。
- 删除：根目录 `run.sh` (由 `backend/start.sh` 取代)、`.backup_pre_fix/` (旧备份)、根目录 `.venv` (改为 `backend/.venv`)、`requirements*.txt` (移到 `backend/`)。重构前完整备份：`~/Desktop/VeraBot-v0.1_backup_20260930_180403`。

### 迭代 2：缺陷修复与功能完善 (按完成顺序)

#### 1. 缺陷修复 (Bug fixes, 9 个：BUG-01 ~ BUG-09)

v0.1 测试 (31 条用例) 发现 9 个缺陷，均已修复并回归通过，详见 [TEST_CASES_v0.1.md](testing/TEST_CASES_v0.1.md)「缺陷列表」「缺陷验证」。

| ID | 问题 | 修复 (Fix) |
|---|---|---|
| BUG-01 | 温度区间「15~21.2°C」的 `~` 被当成 Markdown 删除线 (strikethrough) | iOS 聊天气泡 (现 `Features/Chat/MessageRow.swift`) 渲染 Markdown 前转义 `~` |
| BUG-02 | 可以创建空白名称的 Bot | 后端 `BotIn.name` 先 strip 再校验，空白 → 422「名称不能为空」 |
| BUG-03 | PATCH 名称不去空格；任何异常都报 409 | `BotPatch` trim + 空白校验；只有 `IntegrityError` 才返回 409 |
| BUG-04 | 纯空白消息能通过校验并调用 LLM | `ChatIn` strip 后校验 → 422 |
| BUG-05 | 清空对话 (🗑) 没有二次确认 | `.confirmationDialog`「清空与「X」的全部对话？」 |
| BUG-06 | 每日 Token 额度只展示、不拦截 | chat 前检查预算 (`VERABOT_DAILY_TOKEN_QUOTA` / `users.token_budget`)，超额 → 429「今日 Token 额度已用完」，委派也被拒 |
| BUG-07 | 错误气泡开头有两个空行 | `appendError()` 统一处理 (iOS + Web) |
| BUG-08 | 被委派的 Bot 向用户暴露内部工具名 | 委派 system prompt 要求不提及内部工具 |
| BUG-09 | LLM 空回复被静默保存为「（无回复）」 | 记录 `finish_reason`，自动重试 1 次，仍为空 → SSE `error{code: empty_reply}` |

另外回归中发现并修复：NEW-01 `ask_bot` 模糊匹配误路由 (「BobBot」→「B」)；NEW-02 422 信息带 pydantic「Value error, 」前缀。

#### 2. 多 Agent 协作：权限 / 上下文 / 护栏 / 审计 (Multi-agent permissions, context, guardrails, trace) + Bot 数量软上限

设计详见 [MULTI_AGENT_DESIGN.md](design/MULTI_AGENT_DESIGN.md)。

- **权限模型 (Permission model)**：每个 Bot 新增 `allowed_tools` (工具白名单)、`delegate_to` (委派白名单)、`accept_delegation` (是否接受委派)。新建 Bot 默认最小权限 (Least privilege)：无工具、不委派、不接受委派。
- **服务端强制 (Server-side enforcement)**：未授权的工具 schema 不暴露给 LLM；执行前再次检查；越权调用拒绝并写 `audit_log`。
- **上下文隔离 (Context isolation)**：委派只发送 question + 限长 shared_context (≤ 2000 字，超出截断并标记) + 调用方公开资料；不发送对话历史、私有指令；不写入对方的记忆。
- **护栏 (Guardrails)**：委派深度 (默认 1)、环路检测 (loop detection)、单轮最多 3 次委派、每日 Token 预算。
- **审计 (Trace / Audit)**：`delegations` 表记录 status / reason / depth / payload / tokens；`GET /api/bots/{id}/delegations`；iOS「协作记录」页 (DelegationLogView)，交接卡片显示「协作记录 #id」与 Token。
- **Bot 数量软上限 (Soft limit)**：`MAX_BOTS_PER_USER` (默认 20，兼容 `VERABOT_MAX_BOTS`) 取代硬编码 5；超出 → 400「已达到 Bot 数量上限（20 个）」；UI 不再显示 x/5。
- **数据库迁移 (Migration v1 → v2)**：启动时自动、幂等；已有 Bot 保留 v0.1 行为 (全部工具 + 互相委派)。
- **iOS**：BotEditView 工具权限开关、委派目标、接受委派、护栏说明；Bot 列表长按「编辑与权限」。
- 测试：`backend/scripts/test/multi_agent_test.py` MA-01 ~ MA-24 (mock LLM) 24/24；真实 LLM REG-* 10/10。

#### 3. 语音播放 TTS (用户消息 + Bot 回复)

- 新增 `TTS.swift` (现位于 SPM 模块 VeraBotTTS)：`protocol TTSEngine`、`LocalTTSEngine` (AVSpeechSynthesizer, zh-CN)、`CloudTTSEngine` (占位 stub)、`@Observable SpeechPlayer`。
- Bot 回复和用户消息气泡下方都有 🔊 (`SpeakButton`，用户消息右对齐)；播放中变为 ■，再点停止。

#### 4. 设置页 (Settings) + 头像入口 + 账号置顶

- 首页「我的 Bot」左上角用户头像 (首字母，`UserAvatar`) → `SettingsView`。
- 分组顺序：**账号 (Account)** (头像 / 用户名 / 服务器地址 / 退出登录，有二次确认) → **语音 (Voice)** (语音播放开关 `vb_tts_enabled`、语音引擎 `vb_tts_engine`：本机 TTS / 云端 TTS 即将支持，置灰) → **关于 (About)** (版本号)。
- 每个分组是独立的 `…SettingsSection: View`，便于扩展。

#### 5. 二级页面隐藏 Tab 栏 (Tab bar hidden on secondary pages)

- 对话页、设置页、协作记录等 push 进入的页面使用 `.toolbar(.hidden, for: .tabBar)`；返回后 Tab 栏 (助理 / 提醒 / 用量) 恢复。

#### 6. 对话标题 → Bot 详情 (系统默认 sheet，内嵌完整设置)

- 对话页导航栏只保留「返回」和标题 (头像 + 名称 + ›)；右上角不再有 ⚙ / 🗑。
- 点标题以系统默认 `.sheet` (page sheet，非 push、非全屏，可下滑关闭) 打开「Bot 详情」：`BotInfoView` 复用 `BotEditView(infoMode: true)`，包含资料卡片、基本信息、工具权限、委派、协作记录，底部「清空对话」(保留二次确认)。

#### 7. 首页导航栏原生圆形按钮 (Native circular nav buttons)

- 左上角头像、右上角 ＋ 改为系统 toolbar 按钮 (iOS 26 Liquid Glass 圆形样式)，去掉自绘背景。

#### 8. 键盘处理 (Keyboard handling pass)

- 新增 `Keyboard.swift` (现位于 `Services/Keyboard/`)：`Keyboard.dismiss()`、`keyboardDoneButton`、`dismissKeyboardOnBackground`、`bottomAnchoredScrolling` (iOS 18+ `defaultScrollAnchor(.bottom)`)。
- 对话页：输入栏通过 `safeAreaInset` 随键盘上移 (无手动偏移)；`scrollDismissesKeyboard(.interactively)`；点空白收起；键盘弹出后滚到底部；发送后保持焦点。
- 表单：`@FocusState`，单行字段 `submitLabel(.next)` 跳到下一项；离开页面、弹出 sheet、App 进入后台时收起键盘。

#### 9. 人设 / 指令支持多行 (Multi-line persona / instructions)

- `TextField(axis: .vertical).lineLimit(3...8)`，回车换行 (不使用 submitLabel)；后端原样保存换行 (KB-11 已验证)。

#### 10. Bot 详情保存后对话页布局修复 (Sheet-save layout fix，Boss 反馈)

- **现象**：对话页 → Bot 详情 → 编辑字段 (键盘弹出) → 保存，回到对话页后内容被顶起、留下键盘高度的空白，触摸后才恢复。
- **根因 (Root cause)**：page sheet 与下层对话页共享窗口的键盘安全区；sheet 内 `.keyboard` 工具栏 (inputAccessoryView)「完成」让对话页的键盘避让状态错乱；对话页的 keyboardDidShow 滚动不区分是谁的键盘。
- **修复**：BotEditView 的 保存 / 关闭 / 清空 / onDisappear (含下滑关闭) 先 `endEditing()` (清 FocusState + resignFirstResponder)；sheet 内不再使用键盘工具栏 (改用 下拉 / 保存 / 关闭 收起)；对话页只在自身输入框聚焦且无 sheet 时响应 keyboardDidShow；sheet `onDismiss` 无动画重新贴底。
- 验证：保存 ×3、关闭、下滑关闭均正常，之后点输入框时输入栏贴在键盘上方 (KB-12，截图 R36)。

### 迭代 1：MVP 基线 (Baseline)

- 账号：用户名 + 密码注册 / 登录，bcrypt + JWT；租户隔离 (per-user isolation，他人资源 404)。
- Bot 管理：emoji 头像 + 颜色 + 昵称 + 人设 (Persona) + 自定义指令 (Instructions)；每用户最多 5 个 (迭代 2 改为软上限 20)。
- 流式对话 (SSE)、每 Bot 独立记忆 (最近 20 条)、清空对话。
- 工具调用 (Tool Registry)：`get_weather` (Open-Meteo)、`create_reminder`、`list_reminders`、`ask_bot` (多 Agent 委派，深度 1，交接 Trace 卡片)。
- 提醒 Tab、用量看板 (Quota Dashboard)、附件 ＋ 菜单占位 (即将支持)、语音输入 (Web: `/api/transcribe`；iOS: Speech 框架)。
- 客户端：Web SPA (后端托管) + SwiftUI iOS App (iOS 17+，Swift 6 严格并发)。
- 测试：31 条用例 (TC-01 ~ TC-31)：26 通过、4 失败、1 跳过，发现 BUG-01 ~ 09。
