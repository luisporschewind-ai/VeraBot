# 功能清单与 API 摘要 (Features & API) — v0.1.0 + 未发布改动 (Unreleased)

> 对话页导航条目更新至 2026-10-10；其余能力概览沿用既有记录。标注「待 Boss 验收」的界面效果见 [STATUS.md](../STATUS.md)。`frontend/web` 冻结，没有 MCP / 确认卡片界面。

## 功能 (Features)

> **2026-10-09 · iOS 体验更新**：本地 Bot 冷启动欢迎、连接失败默认页 / 保留内容提示、登录页重设计及已打开弹窗的主题同步。复用现有 Bot 动作；浅 / 深 / 跟随系统由整个窗口统一传递。详见 [验收记录](../testing/2026-10-09-startup-connection-appearance.md)，真机验收状态单独标注。

| 模块 | 说明 |
|---|---|
| 账号 (Accounts) | 邮箱 + 密码、邮箱 + 验证码 (新邮箱自动建号)、手机号 + 密码注册 / 登录 (默认邮箱密码，其他方式展开选择)；老的用户名账号 (demo) 仍可在邮箱框登录，界面不展示用户名；bcrypt 哈希；访问令牌 JWT 7 天 + 刷新令牌 60 天 (轮换，iOS 透明刷新，Keychain 保存)；连续 5 次密码错误锁 15 分钟；邮箱未验证可正常使用，设置页提醒验证；失效自动退出；设置页底部退出登录 (二次确认)。昵称可在设置页点按昵称弹窗修改（1–32 字，去空白），首页左上角和对话里的用户名立刻更新 |
| 租户隔离 (Per-user isolation) | 所有查询带 `user_id`；访问他人资源统一返回 404 (防枚举)。设备侧缓存：后端 `/api/*` 带 `Cache-Control: no-store`，iOS API 走无缓存会话，退出 / 登录清本机 `Cache.db`（缓存修复，Boss 于 2026-10-04 验收通过） |
| Bot 管理 | emoji 头像 + 颜色 + 昵称 + 人设 (多行) + 指令 (多行) + 标签 (最多 3 个，每个最多 4 个字，逗号 / 顿号 / 空格分隔；创建页一个输入框，Bot 详情点卡片上的标签行弹窗修改；首页行名称后显示为一个浅灰圆角矩形「搜索, 查询, 调研」，Bot 详情卡片名称下方一行)；＋ 创建 (达到上限时 ＋ 置灰；列表不显示数量页脚)、Bot 详情编辑、长按「编辑与权限」、左滑删除 (系统确认框二次确认，说明删除 / 保留的数据)、左滑 / 长按置顶 (品牌色实心 pin 图标，点按后行立即用系统动画移到新位置，再同步服务端，失败回滚)；软上限 20 (`MAX_BOTS_PER_USER`)。列表每行名称右侧显示标签（放不下时尾部截断），右上角显示最后消息时间（今天 HH:mm / 昨天 / 本周星期几 / M/d / 非今年 yyyy/M/d，无消息回退创建时间）；首页不显示大导航标题；右上角放大镜点按后才出现系统搜索栏（平时不显示搜索框，下拉也不出现；取消后收起并清空），当前只过滤屏幕上已加载的列表（Bot 名称和最后一条消息预览）；完整聊天历史搜索、搜索历史等移至后续迭代。所有头像（用户 / Bot，照片或表情 / 首字）都显示为正圆。用户和每个 Bot 都可以另设一张圆形照片头像（相册选择、可更换；Bot 可在详情页点头像选「使用默认形象」移除照片，用户头像不提供该入口）；表情字段保留，没有照片时继续显示。Bot 详情页：顶部卡片 (点头像换照片 / 恢复默认形象，点昵称、标签弹窗修改，均在「保存」时才提交，「取消」丢弃) → 默认形象 (表情 + 颜色) → 人设 → 自定义指令 → 记忆 → 工具权限 (只显示中文名) → 委派 → 协作记录 (本机时间) → 清空对话；界面无英文 |
| 流式对话 (Streaming, SSE) | `POST /api/bots/{id}/chat` 返回 `text/event-stream`，逐 token 渲染；工具卡片、交接 Trace 卡片、错误气泡 |
| 对话页导航 | 中间标题（Bot 头像 + 名称）打开 Bot 详情；右上角三点「更多」按钮沿用玻璃样式，当前为空操作 |
| 消息富文本 (Rich messages) | iOS Bot 气泡支持 Markdown（标题 / 粗体 / 斜体 / 行内代码 / 代码块 / 引用 / 列表 / 表格 / 分隔线），自动识别网址 / 电话 / 邮箱；网页链接在 App 内 SFSafariViewController 打开，电话 / 邮件交给系统；长按气泡可复制全文或复制链接，用户 / Bot 气泡长按均有「删除」(系统确认框二次确认，只删这一条；欢迎语与正在生成的回复不显示)；`~` 按原文显示 (BUG-01) |
| 对话历史 (History) | 每个 Bot 独立保存历史，最近 20 条 (`VERABOT_HISTORY_WINDOW`) 注入上下文；清空对话 (二次确认：「仅清空对话」删除对话摘要、保留已确认记忆 /「清空对话和「X」的记忆」再删该 Bot 的记忆) |
| 长期记忆 (Memory, M1 + M2) | **先确认、后保存**：Bot 用 `remember` / `forget_memory` 只生成提议，对话里出现「要我记住吗？」卡片 (记住 / 不用 / 编辑后记住)，确认后生效。作用域：所有 Bot 共享的「关于你」(global) 或仅某个 Bot；每个 Bot 的 `memory_access` (不使用 / 仅本 Bot / 本 Bot + 共享资料，默认后者)；每轮最多注入 12 条 / 1000 字，风格最多 3 条排在最前，被委派的 Bot 不读写记忆。密码 / 验证码 / 密钥 / 证件号 / 卡号永不保存；健康、财务信息加密保存并标为敏感。**M2**：每个 Bot 一条滚动摘要（窗口外积压满 20 条才压缩，≤ 400 字，不经确认，清空对话时删除）；回复气泡可 👍 / 👎，「再短一点」或 14 天内 3 次「太长」只提议风格（「以后都这样回答吗？」），确认前不生效。设置 › 记忆：「Vera 了解的你」(查看 / 编辑 / 删除 / 手动添加 / 清空，首次打开说明会发送给 DeepSeek) + 「允许 Bot 记住」总开关。Bot 详情 › 记忆。方案与契约见 [MEMORY_GROWTH.md](../design/MEMORY_GROWTH.md)。Web 无记忆 UI |
| 工具 (Tool calling) | 可插拔注册表：`get_weather`、提醒三件套、`ask_bot`；记忆工具由 `memory_access` 控制。MCP 工具默认关闭；OAuth 远程连接（M4）使用 PKCE，Token 加密保存在后端。Gmail 目前只有连接入口，邮件工具尚未开放。**写 / 发送 / 破坏性**调用会弹出确认卡片（M3，`pending_actions`），确认后才执行冻结参数；只读可直接执行。委派深度 ≥ 1 不能用 MCP |
| 多 Agent 协作 | 工具 / 委派白名单、接受委派开关、上下文隔离、深度 / 环路 / 单轮上限 / Token 预算、审计日志、协作记录页 → [MULTI_AGENT_DESIGN.md](../design/MULTI_AGENT_DESIGN.md) |
| 每日 Token 预算 | 超额返回 429，委派也被拒 |
| 提醒 / 用量 (Reminders / Quota) | 提醒为 Tab 页，顶部分段「提醒 / 通知」。提醒按逾期、今天、即将、无日期分组，可新建、编辑、完成、稍后、跳过；到时由服务端调度，iOS 用本地通知（「完成」「稍后 10 分钟」），R1 不发 APNs。点按提醒通知 → 「提醒」Tab → 该提醒页，「来源」里「查看对话」进入对话；只有 Bot 消息通知直接打开对话。设置 › 通知管理分类、免打扰和显示内容。用量看板从「设置 › 用量」进入：请求数、Token、7 日趋势、按 Bot 分布 (不含账号信息，账号信息在设置页)。Web 没有新的提醒界面。**R1 Boss 于 2026-10-04 验收通过**（模拟器；真机未测） |
| 语音输入 (Voice input) | Web：录音 → `/api/transcribe` (OpenAI) → 填入输入框；iOS：系统 Speech 框架 (zh-CN)；都不自动发送 |
| 语音播放 (TTS) | 用户消息和 Bot 回复下方 🔊，本机 AVSpeechSynthesizer；设置里可关闭；云端 TTS 占位 |
| 设置页 (Settings) | 首页左上角头像进入；账号 (点头像换照片、点昵称弹窗修改；下方显示邮箱 / 手机号，老账号显示用户名；邮箱未验证时显示「邮箱未验证 · 验证」) → 用量 (push 用量看板) → 记忆 (「Vera 了解的你」+「允许 Bot 记住」) → MCP 服务 (按服务启用、刷新、给某个 Bot 开只读工具) → 通用 (外观：跟随系统 / 浅色 / 深色；通知开关，开启时申请系统授权，被拒绝则回退并提供「前往设置」；触感反馈开关，控制 App 内所有 sensoryFeedback；语言：显示当前语言，点按打开系统设置中本 App 页面切换) → 语音 → 关于 (版本号) → 退出登录 (单独一组，位于最底部)。头像用系统 PhotosPicker，预览为圆形，确认后上传 |
| 调试页 (Debug) | 登录页 / 设置页右上角 🐞 (`ladybug`) 进入；未登录时可编辑服务器，登录后只读；包含外观切换、最近连接错误详情、后端健康检查 (`GET /api/health`)、版本 / 构建号 / Bundle ID / 系统版本 / 构建配置；另有「头像实验室」独立试验页，可切换五款角色、八种状态 (与执行状态机对应) 与三种尺寸，并可「按状态机演示一轮对话」；支持深色模式与减弱动态效果，预览选择不会保存到 Bot 资料 |
| 导航 / 键盘 | 二级页面隐藏 Tab 栏；对话标题为可点击的原生胶囊按钮（iOS 26 Liquid Glass，旧系统 bordered 回退；头像 + 名称，不显示标签）并打开 Bot 详情 sheet；首页原生圆形按钮（左上角头像为正圆，iOS 26 隐藏系统共享玻璃底 (`.sharedBackgroundVisibility(.hidden)`) 并放大到 44pt，与右侧圆形按钮等大，旧系统 30pt；右上角 放大镜 搜索 与 ＋ 创建 为两个独立圆形按钮，iOS 26 用 `ToolbarSpacer(.fixed)` 分开）；工具栏 / sheet 的取消、关闭为系统圆形 X（iOS 26 `Button(role: .cancel / .close)`，确认框里的取消仍是文字）；输入栏随键盘上移、点空白 / 下拉收起。对话输入栏为浮动 Liquid Glass：圆形玻璃 ＋ 附件按钮 + 胶囊玻璃输入框（占位「向 {Bot 名} 提问」，尾部 🎙 语音输入），无发送按钮，键盘 return 发送；iOS 26 输入栏用 `safeAreaBar(edge: .bottom)`，消息滚到输入栏下方有系统底部滚动边缘效果（渐隐模糊，与顶部导航栏一致），旧系统 `safeAreaInset` |
| 视觉风格 (Visual style) | 页面白底（深色黑底），分组 / 卡片 / Bot 气泡浅灰 `#EFEFEE` (RGB 239, 239, 238)（深色 `secondarySystemBackground`）；「助理」列表为白底全宽平铺、无分隔线；iOS 26 Liquid Glass（系统导航栏 / Tab 栏 / 工具栏按钮，`.glass` 胶囊、`.glassProminent` 主按钮，旧系统 bordered 回退）。颜色集中在 `Core/UI/Theme.swift` 语义色，设置 › 外观 切换时全局一致；所有开关为缩小 85% 的系统 Toggle (`CompactToggle`) |
| 附件 (Attachments) | **图片 (P1，schema v12)**：＋ 菜单「图片」用系统 PhotosPicker 选 1 张 (再选替换)，本机压缩后上传，输入栏显示缩略图 (上传中不能发送，可只发图片)；气泡始终显示真实图片，GIF 播放动画，点按 Quick Look 全屏 / 分享；模型 `deepseek-flash` 看图，之后按需召回 (描述 + `view_image` / 回指时重发原图)；委派时图片转给被委派 Bot；带图轮次创建提醒需文字确认；图片随清空对话 / 删除 Bot 删除。**拍照 (P2)**：＋ 菜单「拍照」打开系统相机 (UIImagePickerController)，拍到的图与相册同一路径 (1 张、再拍替换、压缩去 EXIF、上传中不能发送)；无相机设备 / 模拟器不显示；拒绝相机权限时提示「前往设置」。文件入口已启用（iOS 系统文件选择器，支持 PDF/TXT/MD/CSV/DOCX/XLSX，单文件 10 MB、每条消息 1 个）；后端按需读取文本并以 Quick Look 预览。设备级与真实模型验收待完成。Web 不支持 |
| App 图标 / 名称 (App icon & name) | 主屏显示名「Vera Bot」(`INFOPLIST_KEY_CFBundleDisplayName`，`InfoPlist.xcstrings` zh-Hans / en 均为「Vera Bot」)；App 图标为 `Assets.xcassets/AppIcon.appiconset` 单尺寸 1024×1024 (源图 `assets/brand/app-icon-source.png`)。设置 › 关于 中的应用简介仍写「VeraBot · 你的私人 AI 助理团队」 |
| Web 客户端 | 只作为 API 验收客户端，功能落后于 iOS (见 [STATUS.md](../STATUS.md) 已知限制) |

> **已实现**：Bot 置顶 (schema v6，`pinned_at` + PATCH `pinned`，首页左滑 / 长按「置顶」，置顶行浅灰底)，规格与测试见 [BOT_PIN.md](../design/BOT_PIN.md) 和 [STATUS.md](../STATUS.md)。

## API 摘要

所有 `/api/*` (除 auth / health) 需要 `Authorization: Bearer <JWT>`。完整 schema：后端启动后访问 `/docs`。

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/auth/register` | `{email, password}` / `{phone, password}` (≥ 8 位)；旧 `{username, password}` 保留 → `{token, refresh_token, expires_in, refresh_expires_in, user}`。`user` 含 `nickname`、`display_name`、`has_avatar`、`avatar_updated_at`、`email`、`email_verified`、`phone`。409 `email_taken` / `phone_taken` |
| POST | `/api/auth/login` | `{identifier, password}` (邮箱 / 手机号 / 用户名) 或旧 `{username, password}`；401「账号或密码错误」；429 `account_locked` |
| POST | `/api/auth/refresh`、`/api/auth/logout` | `{refresh_token}`；刷新返回新的一对 (旧的作废，复用则吊销全部) / 吊销 |
| POST | `/api/auth/logout-all` | 所有设备失效 (`token_version + 1`) |
| POST | `/api/auth/email/send-code`、`/api/auth/email/login` | `{email}` → `{ok, expires_in, retry_after}` (60 秒 1 次、每天 10 次)；`{email, code}` → 会话 (新邮箱自动建号) |
| POST | `/api/me/email/send-verification`、`/api/me/email/verify` | 发验证码 / `{code}` 验证当前邮箱 → `user` |
| GET | `/api/me` | 当前用户（字段同上；`display_name`：昵称 → 邮箱 @ 前部分 → 用户<手机后 4 位> → 用户名） |
| PATCH | `/api/me` | `{nickname}` 修改昵称。先 trim；空 / 纯空白 / 超过 32 字 / 控制字符 → 422 |
| POST | `/api/me/avatar` | `multipart/form-data` 字段 `file`。JPEG / PNG / WebP（HEIC 仅在服务器装有解码器时）；最大 8MB。服务端居中裁成 512×512 JPEG。返回更新后的 `user` |
| GET | `/api/me/avatar` | 当前用户的 JPEG；未设置 → 404「未设置头像」 |
| DELETE | `/api/me/avatar` | 删除自定义头像（恢复默认），返回更新后的 `user`。iOS UI 目前不调用 |
| POST / GET / DELETE | `/api/bots/{id}/avatar` | 与用户头像相同，对象是该用户自己的 Bot。他人或不存在的 Bot → 404。删除后仍保留 emoji `avatar` 字段。删除 Bot 时照片行一并删除 |
| GET / POST | `/api/bots` | Bot 列表 / 创建 (新 Bot 默认最小权限)。每个 Bot 另有 `has_avatar`、`avatar_updated_at`、`tags`（字符串数组，缺省 `[]`）；`avatar` 仍是 emoji。创建时可带 `tags` |
| GET / PATCH / DELETE | `/api/bots/{id}` | 详情 / 修改 (含 `allowed_tools`、`delegate_to`、`accept_delegation`、`memory_access`、`tags`) / 删除。Bot JSON 另有 `memory_access` (`none`/`bot`/`bot_and_global`)、`memory_count`、`tags`。`tags` 省略 = 不修改，`[]` = 清空。非法标签 → 422 中文 |
| GET / DELETE | `/api/bots/{id}/messages` | 历史消息 (含 Trace；每条另有 `attachments` 数组；assistant 消息另有 `feedback`: `{rating, reason}` 或 null) / 清空对话 (同时删除该 Bot 的图片行、文件和滚动摘要，已确认记忆默认保留)。DELETE 可选 `?include_memories=true` 再删除该 Bot 的本 Bot 记忆，返回 `{ok, deleted_memories}` |
| POST / DELETE | `/api/messages/{id}/feedback` | 给本人的 assistant 消息点 👍 `{"rating":1}` 或 👎 `{"rating":-1,"reason":"too_long\|too_short\|inaccurate\|tone\|other"}`。同一条可改。返回 `{ok, feedback, style_trace}`；凑满风格条件时 `style_trace` 是待确认的 remember 结果，否则 null。DELETE 撤销。他人 / 用户消息 / 不存在 → 404。Web 未接入 |
| DELETE | `/api/bots/{bot_id}/messages/{message_id}` | 删除单条消息（物理删除，只删这一条，不连带同一轮的另一条）→ `{ok: true}`。按 `user_id` + `bot_id` + `id` 限定：他人的 Bot / 消息、Bot 与消息不匹配、不存在或已删除一律 404「消息不存在」(相同响应)。`memories.source_message_id`、`notifications.message_id`、`reminders.source_message_id` 置 NULL；**已提取的记忆不删除**。带图消息：`attachments` 行同事务删除，提交后立即删除原图 / 缩略图 (GIF 另有第一帧)，之后 `GET /api/attachments/{id}`、`/content`、`/thumb` 均 404。无 schema 变更 (v12 不变)。Web 未接入 |
| GET | `/api/bots/{id}/delegations` | 该 Bot 发出和收到的委派记录 |
| POST | `/api/bots/{id}/chat` | **SSE** 流式对话 `{message, attachment_ids?}`；`attachment_ids` 最多 1 个 (多 → 422)，有图时 `message` 可为空；附件他人 / 不存在 404、已发送 409、过期 410、属于其他 Bot 422。带图失败时 `error` 事件含 `code`：`vision_unsupported` / `vision_failed` |
| POST | `/api/attachments` | 图片上传 (v12)：multipart `file` + 可选 `bot_id` → 201 `{id, kind, mime, width, height, bytes, status:"pending", expires_at}`。JPEG / PNG / WebP / GIF (HEIC 需服务器解码器)；415 类型、413 超 10 MB 或存储满、400 超 4000 万像素 / 无法解析、429 每天超 50 张 |
| GET | `/api/attachments/{id}`、`/content`、`/thumb` | 元数据 / 原图 / 320 px 缩略图；`Cache-Control: private, no-store`、`nosniff`；他人或不存在 404，文件已删 410 |
| DELETE | `/api/attachments/{id}` | 删除未发送的图；已发送 409 (随消息删除) |
| POST | `/api/transcribe` | 语音转写 (multipart `file` + `language`) → `{text, model, duration_s}` |
| GET / POST / PATCH / DELETE | `/api/reminders`、`/api/reminders/{id}`、`.../complete`、`.../done`、`.../snooze`、`.../reopen`、`.../skip`、`.../restore`、`.../events` | 提醒列表与单条操作。写接口认 `Idempotency-Key`。`/done` 仍是完成的别名。字段见 [REMINDER_PUSH_DESIGN.md](../design/REMINDER_PUSH_DESIGN.md) §8 |
| GET / POST / PATCH / DELETE | `/api/notifications`、`/summary`、`/read-all`、`/{id}/read`、`/{id}/unread`、`/{id}/events`、`/api/notification-settings`、`/api/devices` | 收件箱、偏好、设备。R1 不发 APNs。响应 `Cache-Control: no-store` |
| GET | `/api/quota` | 用量看板 `{model, daily_token_quota, today, total, per_bot, daily, delegations, transcribe}`；`today` / `total` 为 `{requests, prompt_tokens, completion_tokens, total_tokens}`。设置 › 用量 行的「已用 N%」由 iOS 计算：round(`today.total_tokens` / `daily_token_quota` × 100)，额度 ≤ 0 时不显示 (字段映射见下方「用量字段映射」) |
| GET / POST | `/api/pending-actions`、`/api/pending-actions/{id}/confirm`、`/cancel` | MCP M3：待确认操作列表 / 确认执行冻结参数 / 取消。他人 404；已处理 409；过期 410。SSE 另有 `confirmation_required` |
| GET | `/api/bots/{id}/tool-calls` | MCP M3：该 Bot 的工具调用 / 确认相关审计摘要（不含原文） |
| GET | `/api/tools` | 工具列表 (中文标签，不含记忆工具) + 当前护栏参数 + `memory: {enabled, max_active, inject_max}`。每项另有 `source`、`server`、`server_id`、`risk`、`requires_confirmation`、`delegable`、`status`、`plugin_id`（天气 `builtin_weather`，提醒工具 `builtin_reminder`，`ask_bot` 为 `null`，已连接的外部工具为插件 id）。已连接且已同意的外部工具附在后面。此接口不连接外部服务 |
| GET | `/api/plugins/catalog` | 可安装的外部插件目录。每项是 Plugin JSON，含当前用户的 `installed`、`available`。不含原始 URL |
| GET | `/api/plugins` | 内置插件 + 已安装的外部插件。新用户只有天气和提醒。不在这个请求里联网。响应 `Cache-Control: no-store` |
| GET | `/api/plugins/{plugin_id}` | 单个插件。未安装或未知 → 404 |
| POST | `/api/plugins/{plugin_id}/install` | 安装。首次和重装都是 201；已安装 409。不自动同意。内置插件 422 |
| DELETE | `/api/plugins/{plugin_id}` | 卸载。返回 `{ok, removed_tools, affected_bots}`。清同意，并从所有 Bot 与工具缓存去掉该插件的工具。内置插件 422 |
| PATCH | `/api/plugins/{plugin_id}` | `{enabled}`。停用后工具不进模型 schema，调用返回 `not_connected`。内置插件 422 |
| POST | `/api/plugins/{plugin_id}/consent` | `{granted}`。写入其下服务的同意时间。内置插件 422。未安装 404 |
| GET | `/api/plugins/{plugin_id}/tools` | 该插件的工具，字段同 MCP 工具并带 `plugin_id`。内置插件 404（开关在 Bot 的工具权限） |
| POST | `/api/mcp/servers/{id}/auth/start`、`/auth/callback`、`/auth/cancel` | M4 OAuth：发起授权、提交授权回调、取消授权；响应不返回 Token |
| DELETE | `/api/mcp/servers/{id}/auth` | M4 OAuth：尝试撤销并清除本地 OAuth 凭据。Google 邮件工具尚未开放 |
| POST | `/api/plugins/{plugin_id}/sync` | `{added, changed, removed, plugin}`。已停用 → 409 |
| PUT | `/api/plugins/{plugin_id}/credential` | 需令牌插件（GitHub / Linear，`auth_mode=bearer`）：`{token}`。只接受本机回环或 HTTPS（否则 403 `insecure_transport`，`VERABOT_ALLOW_LAN_CREDENTIALS=1` 可放开）；格式错 422 `credential_format`；服务 401 → 422 `credential_invalid`（不保存）；网络不通 502 `network_unreachable`。成功：Fernet 加密保存、同步工具，返回 Plugin（不含令牌）。Plugin 新增可选字段 `auth_connected`、`account_label`、`credential_hint`（末 4 位）、`credential_expires_at`、`auth_error`、`credential_help`、`credential_help_url`、`tools_changed`；`state` 新值 `needs_auth`。对照表见 [MCP_AUTH_CONNECTORS_PLAN.md](../design/MCP_AUTH_CONNECTORS_PLAN.md) §13.1 |
| DELETE | `/api/plugins/{plugin_id}/credential` | 断开：删令牌、回到 `needs_auth`，保留同意与 Bot 工具开关。未连接 404 |
| POST | `/api/plugins/{plugin_id}/accept-tool-changes` | 接受该插件所有定义已变化的工具：`{accepted, plugin}` |
| GET | `/api/mcp/catalog` | **已弃用。** 可添加的目录：`catalog[]`（含 `catalog_id`、`url_configured`，不含原始 URL）。新客户端用 `/api/plugins/catalog` |
| GET / POST | `/api/mcp/servers` | **已弃用。** GET 只返回已安装插件的服务，不再补未安装的目录行，也不在这个请求里连外网。POST `{catalog_id}` 走插件安装，已存在 → 409「已经添加过这个服务」。每项另有 `consent_at`、`sync_status`、`circuit_state`、`circuit_open_until`、`consecutive_failures` |
| PATCH / DELETE | `/api/mcp/servers/{id}` | `{enabled}` 启用或停用 / 删除（并从各 Bot 白名单去掉该服务的工具）。启用后后台同步 |
| POST | `/api/mcp/servers/{id}/consent` | `{"granted": true\|false}`。同意记下时间；撤回清空。未同意时不调用该服务的工具。他人 → 404 |
| POST | `/api/mcp/servers/{id}/sync` | 重新拉取工具（这次会等待结果）。服务已停用 → 409。熔断打开时不连外网 |
| GET | `/api/mcp/servers/{id}/tools` | 该服务的工具 |
| POST | `/api/mcp/tools/{id}/accept-change` | 接受定义变更 |
| GET / POST / DELETE | `/api/memories` | 列表 (`status` 逗号分隔或 `all`、`scope`、`bot_id`、`ids`、`visible_to`、`limit`、`before_id`) → `{memories, counts, limits}` / 手动添加 (201，直接生效) / 清空 (`scope`、`bot_id`、必须 `confirm=true`) → `{ok, deleted}` |
| GET / PATCH / DELETE | `/api/memories/{id}` | 单条 / 编辑 (仅 active，重新做敏感检查) / 删除 |
| POST | `/api/memories/{id}/confirm`、`/api/memories/{id}/reject` | 确认提议 (可带 `{content}` 编辑后确认；删除提议返回 `{ok, deleted_id}`) / 拒绝 |
| GET / PATCH | `/api/memory/settings` | `{enabled, server_enabled, active_count, max_active, max_chars}`；PATCH `{enabled}` |
| GET | `/api/health` | 健康检查 `{ok, model}` |

Bot 置顶 (schema v6)：Bot JSON 含 `pinned_at` (UTC ISO 8601 或 null)；PATCH `/api/bots/{id}` 接受 `pinned: true/false`，省略或 null 不修改。GET `/api/bots` 将置顶项按时间倒序、同时间按 id 升序排列，再列出未置顶项 (id 升序)。Web 客户端冻结，不实现置顶 UI。

MCP 字段映射 (schema v8，完整表见 [MCP_CAPABILITY.md](../design/MCP_CAPABILITY.md) §18.2 与 §18.3)：`MCPCatalogItem` / `MCPServer` / `MCPTool` / `ToolInfo` 的 CodingKeys 与上表 JSON 同名（蛇形）。M2 起 `MCPServer` 还包含 `consent_at`、`sync_status`、`circuit_state`、`circuit_open_until`、`consecutive_failures`。`ToolInfo.source` 缺省时不当作 MCP。`frontend/web` 不使用这些接口的界面。

Bot 详情改版字段映射 (2026-10-01，**无 API 变更**，全部是已有接口与字段)：

| 界面操作 | 请求 | 字段 / 说明 |
|---|---|---|
| 打开详情 | `GET /api/bots`、`GET /api/tools` | `Bot` (`name`、`avatar`、`color`、`tags`、`has_avatar`、`avatar_updated_at` …)；`tools[].label` → `ToolInfo.displayName` (缺失 / 等于 `name` 时「未命名工具」，iOS 回退，后端 `labels` 表未改) |
| 保存 (总是先发) | `PATCH /api/bots/{id}` | `BotPatch`：`name` (trim，1~20 字，与 `_clean_name` 一致)、`avatar`、`color` (**详情页现在发送**，原来为 nil；后端早已接受，≤ 9 字符)、`persona`、`instructions`、`allowed_tools`、`delegate_to`、`accept_delegation`、`memory_access`、`tags` (总是发送，`[]` = 清空，规则同 TAG-10) |
| 保存时有新照片 | `POST /api/bots/{id}/avatar` | 已有接口 (JPEG，iOS 先裁成正方形)；返回 `Bot`，写入 `AvatarStore` |
| 保存时「使用默认形象」 | `DELETE /api/bots/{id}/avatar` | 已有接口 (AV-15)；`deleteBotAvatar` 原先未被界面调用 |
| 协作记录 | `GET /api/bots/{id}/delegations` | `created_at` (UTC ISO 8601，带 `+00:00`) 由 iOS 转本机时区；`total_tokens` 显示为「用量 N」 |

用量字段映射 (`GET /api/quota` ↔ iOS `VeraBotCore.Quota`，由 `multi_agent_test.py` MA-25 断言)：

| 后端 JSON (`services/quota.py`) | iOS 属性 | 用途 |
|---|---|---|
| `daily_token_quota` | `Quota.dailyTokenQuota` | 今日额度 (分母)；= `users.token_budget` 或 `VERABOT_DAILY_TOKEN_QUOTA` (默认 200000) |
| `today.total_tokens` | `Quota.today.totalTokens` | 今日已用 (分子)；与 `db.token_budget` 的已用相同 |
| — (iOS 计算) | `Quota.usedPercent` / `usedPercentText` | 设置 › 用量 行右侧「已用 N%」 |
| `model` / `total` / `per_bot` / `daily` / `delegations` / `transcribe` | `model` / `total` / `perBot` / `daily` / `delegations` / `transcribe` | 用量看板其余内容 (不变) |

删除单条消息字段映射 (由 `message_delete_test.py` MSG-DEL-07 / 09 读取 Swift 源码断言路径、方法与键名一致；MSG-DEL-08 断言后端实际发出该字段)：

| 后端 | iOS | 说明 |
|---|---|---|
| `DELETE /api/bots/{bot_id}/messages/{message_id}` | `VeraBotAPI.deleteMessage(botID:messageID:)` → `OKResponse` | 404 时 `APIError.status == 404`，`ChatViewModel.delete` 按已删除处理并移除该条 |
| `GET …/messages` 的 `messages[].id` / SSE `done.message_id` | `ChatDone.messageID` → `ChatViewModel.Item.messageID` (回复) | 有 id 才显示「删除」；流式输出中不显示 |
| SSE `done.user_message_id` (新增，仅追加字段；旧客户端 / Web 忽略) | `ChatDone.userMessageID` (`decodeIfPresent`，旧后端为 nil) → 刚发出的用户消息的 `messageID` | 回复结束即可删除刚发出的用户消息 |

图片附件字段映射 (schema v12，`services/attachments/repo.py` `public()` ↔ iOS `VeraBotCore.Attachment`，由 `attachments_test.py` ATT-CONTRACT 读取 Swift 源码断言键名一致)：

| 后端键 | iOS 属性 | 说明 |
|---|---|---|
| `id` | `id` | `att_` + 26 位 base32 |
| `kind` | `kind` | 目前只有 `image` |
| `mime` | `mime` (`isGIF`) | `image/jpeg` / `image/png` / `image/gif` |
| `width` / `height` | `width` / `height` (`aspectRatio`) | 处理后的像素尺寸 |
| `bytes` | `bytes` | 存储的文件大小 |
| `status` | `status` | `pending` / `attached` |
| `expires_at` | `expiresAt` | 仅 pending；已发送为 `null` |
| 消息 `attachments` | `ChatMessage.attachments` | 旧后端缺键时为 `[]` (`decodeIfPresent`) |
| 请求 `attachment_ids` | `ChatRequest.attachmentIDs` | 最多 1 个 |
| 上传字段 `file` / `bot_id` | `uploadAttachment(data:mime:botID:)` | multipart |
| SSE `error.code` `vision_unsupported` / `vision_failed` | `ChatEvent.error(message)` | iOS 原样显示中文 `message`，不按 code 分支 |

自查清单：☑ 后端 pydantic (`ChatIn.attachment_ids`) ☑ Swift 模型与 CodingKeys ☑ `VeraBotAPI` 方法 (`uploadAttachment`、`attachmentContent`、`attachmentThumb`、`deleteAttachment`、`chatStream(…attachmentIDs:)`) ☑ ATT-CONTRACT ☑ 本表与 API 摘要 ☑ CHANGELOG ☑ TEST_CASES ☑ STATUS (含 Web 落后)。

SSE `status` 事件字段映射 (`agents/runtime.py` `status_data` ↔ iOS `VeraBotCore.ChatStatus`，由 `status_event_test.py` STAT-08 读取 Swift 源码断言键名与 phase 取值一致)：

| 后端键 | iOS 属性 | 说明 |
|---|---|---|
| `phase` | `ChatStatus.phase` / `knownPhase` (`Phase`: `recalling` / `thinking` / `tool`) | 未知值保留原文，状态机忽略 |
| `depth` | `depth` (缺失 = 0) | 0 = 当前 Bot；≥1 = 委派链 |
| `bot_name` | `botName` | 正在工作的 Bot |
| `tool` | `tool` | `phase = tool` 时的工具名 |
| `parent_id` | `parentID` | 外层 `tool_start.id`；状态机据此更新 `delegating.progress` |

没有新增或改名的 `status` 键。10 个执行状态到 8 种头像姿态（Core `BotAvatarPose`，App `AvatarLabState` 同名转发）：

| `ExecutionState` | 头像姿态 |
|---|---|
| `idle` | `idle` 空闲 |
| `recalling`、`thinking` | `thinking` 思考中 |
| `callingTool` | `working` 执行中 |
| `delegating` | `delegating` 委派中 |
| `replying` | `replying` 回复中 |
| `awaitingConfirmation` | `waiting` 等你确认 |
| `completed` | `done` 已完成，1.5 s 后 `reset` → `idle` |
| `blocked`、`failed` | `blocked` 遇到阻塞（`blocked` 1.2 s 后回到原流程） |

默认形象仍用已有字段，不新增 JSON 键（AV-18）：

| 存储 | iOS |
|---|---|
| `bots.avatar` | 五款形象 id：`veraBean` / `sprout` / `star` / `cloud` / `sugar`（均 ≤ `max_length` 8），或旧表情。无照片时画对应形象；旧表情按 `BotLook.emojis` 的位置对应五款 |
| `has_avatar` | `true` 时显示相册照片，优先于形象 id 和旧表情 |

状态机与动画见 [EXECUTION_STATE.md](../design/EXECUTION_STATE.md)。Web 冻结，忽略 `status`；形象 id 会按原文显示。

SSE 事件：

```
event: delta        data: {"text": "…"}
event: tool_start   data: {"id", "name", "args"}
event: tool_result  data: {"id", "name", "args", "result"}
event: status       data: {"phase": "recalling" | "thinking" | "tool", "depth", "bot_name", "tool", "parent_id"}   # 新增，旧客户端忽略
event: error        data: {"message": "…", "code"?: "empty_reply"}
event: done         data: {"message_id", "usage": {prompt_tokens, completion_tokens, total_tokens}, "memory_ids": [本轮注入的记忆 id]}
```

### 登录信息记忆（2026-10-09）

成功登录后按服务器记住账号和密码，登录页自动填回；本机钥匙串保存，验证码不保存。正常重启沿用已保存会话直接进入首页，退出后仍可填回；登录页提供「忘记已保存的登录信息」。

## 俄罗斯方块陪玩（2026-10-09 首版）

- iOS 游乐场：真实现有 Bot 在场，换伙伴、安静陪伴、点头像暂停聊天、局面讨论。选择按账号保存在本机，本局对话不持久化。
- `POST /api/bots/{bot_id}/tetris-companion`：鉴权并检查 Bot 归属和每日预算；输入事件 start/clear/pause/end/chat、分数、消行、堆叠高度、空洞数量、最近最多 8 轮消息，返回 `{text}`。自动回应最多 60 字，手动 180 字。无工具执行、无记忆读取或写入；模型用量计入 game。
- 不联网也能玩；接口失败显示连接提示，不编造 Bot 回复。
