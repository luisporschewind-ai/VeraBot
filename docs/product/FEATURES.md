# 功能清单与 API 摘要 (Features & API) — v0.1.0 + 未发布改动 (Unreleased)

> 与代码同步至 main (2026-10-03)：包含 Bot 标签 (schema v5)、Bot 置顶 (schema v6) 与独立的头像实验室试验页。标注「待 Boss 验收」的界面效果见 [STATUS.md](../STATUS.md)「当前进度」。

## 功能 (Features)

| 模块 | 说明 |
|---|---|
| 账号 (Accounts) | 用户名 + 密码注册 / 登录；bcrypt 哈希；JWT (HS256) Bearer Token；失效自动退出；设置页底部退出登录 (二次确认)。昵称可在设置页修改（1–32 字，去空白），首页左上角和对话里的用户名立刻更新 |
| 租户隔离 (Per-user isolation) | 所有查询带 `user_id`；访问他人资源统一返回 404 (防枚举) |
| Bot 管理 | emoji 头像 + 颜色 + 昵称 + 人设 (多行) + 指令 (多行) + 标签 (最多 3 个，每个最多 4 个字，逗号 / 顿号 / 空格分隔；创建页一个输入框，Bot 详情点卡片上的标签行弹窗修改；首页行名称后显示为一个浅灰圆角矩形「搜索, 查询, 调研」，Bot 详情卡片名称下方一行)；＋ 创建 (达到上限时 ＋ 置灰；列表不显示数量页脚)、Bot 详情编辑、长按「编辑与权限」、左滑删除 (系统确认框二次确认，说明删除 / 保留的数据)、左滑 / 长按置顶；软上限 20 (`MAX_BOTS_PER_USER`)。列表每行名称右侧显示标签（放不下时尾部截断），右上角显示最后消息时间（今天 HH:mm / 昨天 / 本周星期几 / M/d / 非今年 yyyy/M/d，无消息回退创建时间）；首页不显示大导航标题；右上角放大镜点按后才出现系统搜索栏（平时不显示搜索框，下拉也不出现；取消后收起并清空），当前只过滤屏幕上已加载的列表（Bot 名称和最后一条消息预览）；完整聊天历史搜索、搜索历史等移至后续迭代。所有头像（用户 / Bot，照片或表情 / 首字）都显示为正圆。用户和每个 Bot 都可以另设一张圆形照片头像（相册选择、可更换；Bot 可在详情页点头像选「使用默认形象」移除照片，用户头像不提供该入口）；表情字段保留，没有照片时继续显示。Bot 详情页：顶部卡片 (点头像换照片 / 恢复默认形象，点昵称、标签弹窗修改，均在「保存」时才提交，「取消」丢弃) → 默认形象 (表情 + 颜色) → 人设 → 自定义指令 → 记忆 → 工具权限 (只显示中文名) → 委派 → 协作记录 (本机时间) → 清空对话；界面无英文 |
| 流式对话 (Streaming, SSE) | `POST /api/bots/{id}/chat` 返回 `text/event-stream`，逐 token 渲染；工具卡片、交接 Trace 卡片、错误气泡 |
| 消息富文本 (Rich messages) | iOS Bot 气泡支持 Markdown（标题 / 粗体 / 斜体 / 行内代码 / 代码块 / 引用 / 列表 / 表格 / 分隔线），自动识别网址 / 电话 / 邮箱；网页链接在 App 内 SFSafariViewController 打开，电话 / 邮件交给系统；长按气泡可复制全文或复制链接；`~` 按原文显示 (BUG-01) |
| 对话历史 (History) | 每个 Bot 独立保存历史，最近 20 条 (`VERABOT_HISTORY_WINDOW`) 注入上下文；清空对话 (二次确认：「仅清空对话」保留记忆 /「清空对话和「X」的记忆」) |
| 长期记忆 (Memory, M1) | **先确认、后保存**：Bot 用 `remember` / `forget_memory` 只生成提议，对话里出现「要我记住吗？」卡片 (记住 / 不用 / 编辑后记住)，确认后生效。作用域：所有 Bot 共享的「关于你」(global) 或仅某个 Bot；每个 Bot 的 `memory_access` (不使用 / 仅本 Bot / 本 Bot + 共享资料，默认后者)；每轮最多注入 12 条 / 1000 字，被委派的 Bot 不读写记忆。密码 / 验证码 / 密钥 / 证件号 / 卡号永不保存；健康、财务信息加密保存并标为敏感。设置 › 记忆：「Vera 了解的你」(查看 / 编辑 / 删除 / 手动添加 / 清空，首次打开说明会发送给 DeepSeek) + 「允许 Bot 记住」总开关。Bot 详情 › 记忆。方案与契约见 [MEMORY_GROWTH.md](../design/MEMORY_GROWTH.md)。Web 无记忆 UI |
| 工具 (Tool calling) | 可插拔注册表：`get_weather` (Open-Meteo，免 Key)、`create_reminder`、`list_reminders`、`ask_bot`；记忆工具 `remember`、`forget_memory` 不在白名单里，由 `memory_access` 控制 |
| 多 Agent 协作 | 工具 / 委派白名单、接受委派开关、上下文隔离、深度 / 环路 / 单轮上限 / Token 预算、审计日志、协作记录页 → [MULTI_AGENT_DESIGN.md](../design/MULTI_AGENT_DESIGN.md) |
| 每日 Token 预算 | 超额返回 429，委派也被拒 |
| 提醒 / 用量 (Reminders / Quota) | 提醒为 Tab 页，只落库不推送；用量看板从「设置 › 用量」进入：请求数、Token、7 日趋势、按 Bot 分布 (不含账号信息，账号信息在设置页) |
| 语音输入 (Voice input) | Web：录音 → `/api/transcribe` (OpenAI) → 填入输入框；iOS：系统 Speech 框架 (zh-CN)；都不自动发送 |
| 语音播放 (TTS) | 用户消息和 Bot 回复下方 🔊，本机 AVSpeechSynthesizer；设置里可关闭；云端 TTS 占位 |
| 设置页 (Settings) | 首页左上角头像进入；账号 (头像 / 昵称 / 用户名) → 用量 (push 用量看板) → 记忆 (「Vera 了解的你」+「允许 Bot 记住」) → 通用 (外观：跟随系统 / 浅色 / 深色；通知开关，开启时申请系统授权，被拒绝则回退并提供「前往设置」；触感反馈开关，控制 App 内所有 sensoryFeedback；语言：显示当前语言，点按打开系统设置中本 App 页面切换) → 语音 → 关于 (版本号) → 退出登录 (单独一组，位于最底部)。头像用系统 PhotosPicker，预览为圆形，确认后上传 |
| 调试页 (Debug) | 设置页导航栏右上角 🐞 (`ladybug`) push 进入：服务器地址、后端健康检查 (`GET /api/health`)、版本 / 构建号 / Bundle ID / 系统版本 / 构建配置；另有「头像实验室」独立试验页，可切换五款角色、八种状态 (与执行状态机对应) 与三种尺寸，并可「按状态机演示一轮对话」；支持深色模式与减弱动态效果，预览选择不会保存到 Bot 资料 |
| 导航 / 键盘 | 二级页面隐藏 Tab 栏；对话标题为可点击的原生胶囊按钮（iOS 26 Liquid Glass，旧系统 bordered 回退；头像 + 名称，不显示标签）并打开 Bot 详情 sheet；首页原生圆形按钮（左上角头像为正圆，iOS 26 隐藏系统共享玻璃底 (`.sharedBackgroundVisibility(.hidden)`) 并放大到 44pt，与右侧圆形按钮等大，旧系统 30pt；右上角 放大镜 搜索 与 ＋ 创建 为两个独立圆形按钮，iOS 26 用 `ToolbarSpacer(.fixed)` 分开）；工具栏 / sheet 的取消、关闭为系统圆形 X（iOS 26 `Button(role: .cancel / .close)`，确认框里的取消仍是文字）；输入栏随键盘上移、点空白 / 下拉收起。对话输入栏为浮动 Liquid Glass：圆形玻璃 ＋ 附件按钮 + 胶囊玻璃输入框（占位「向 {Bot 名} 提问」，尾部 🎙 语音输入），无发送按钮，键盘 return 发送 |
| 视觉风格 (Visual style) | 页面白底（深色黑底），分组 / 卡片 / Bot 气泡浅灰 `#EFEFEE` (RGB 239, 239, 238)（深色 `secondarySystemBackground`）；「助理」列表为白底全宽平铺、无分隔线；iOS 26 Liquid Glass（系统导航栏 / Tab 栏 / 工具栏按钮，`.glass` 胶囊、`.glassProminent` 主按钮，旧系统 bordered 回退）。颜色集中在 `Core/UI/Theme.swift` 语义色，设置 › 外观 切换时全局一致；所有开关为缩小 85% 的系统 Toggle (`CompactToggle`) |
| 附件 (Attachments) | 占位：＋ 菜单 图片 / 相机 / 文件「即将支持」(禁用) |
| App 图标 / 名称 (App icon & name) | 主屏显示名「Vera Bot」(`INFOPLIST_KEY_CFBundleDisplayName`，`InfoPlist.xcstrings` zh-Hans / en 均为「Vera Bot」)；App 图标为 `Assets.xcassets/AppIcon.appiconset` 单尺寸 1024×1024 (源图 `assets/brand/app-icon-source.png`)。设置 › 关于 中的应用简介仍写「VeraBot · 你的私人 AI 助理团队」 |
| Web 客户端 | 只作为 API 验收客户端，功能落后于 iOS (见 [STATUS.md](../STATUS.md) 已知限制) |

> **已实现**：Bot 置顶 (schema v6，`pinned_at` + PATCH `pinned`，首页左滑 / 长按「置顶」，置顶行浅灰底)，规格与测试见 [BOT_PIN.md](../design/BOT_PIN.md) 和 [STATUS.md](../STATUS.md)。

## API 摘要

所有 `/api/*` (除 auth / health) 需要 `Authorization: Bearer <JWT>`。完整 schema：后端启动后访问 `/docs`。

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/auth/register`、`/api/auth/login` | `{username, password}` → `{token, user}`。`user` 含 `nickname`、`display_name`、`has_avatar`、`avatar_updated_at` |
| GET | `/api/me` | 当前用户（字段同上；`nickname` 为空时 `display_name` 等于用户名） |
| PATCH | `/api/me` | `{nickname}` 修改昵称。先 trim；空 / 纯空白 / 超过 32 字 / 控制字符 → 422 |
| POST | `/api/me/avatar` | `multipart/form-data` 字段 `file`。JPEG / PNG / WebP（HEIC 仅在服务器装有解码器时）；最大 8MB。服务端居中裁成 512×512 JPEG。返回更新后的 `user` |
| GET | `/api/me/avatar` | 当前用户的 JPEG；未设置 → 404「未设置头像」 |
| DELETE | `/api/me/avatar` | 删除自定义头像（恢复默认），返回更新后的 `user`。iOS UI 目前不调用 |
| POST / GET / DELETE | `/api/bots/{id}/avatar` | 与用户头像相同，对象是该用户自己的 Bot。他人或不存在的 Bot → 404。删除后仍保留 emoji `avatar` 字段。删除 Bot 时照片行一并删除 |
| GET / POST | `/api/bots` | Bot 列表 / 创建 (新 Bot 默认最小权限)。每个 Bot 另有 `has_avatar`、`avatar_updated_at`、`tags`（字符串数组，缺省 `[]`）；`avatar` 仍是 emoji。创建时可带 `tags` |
| GET / PATCH / DELETE | `/api/bots/{id}` | 详情 / 修改 (含 `allowed_tools`、`delegate_to`、`accept_delegation`、`memory_access`、`tags`) / 删除。Bot JSON 另有 `memory_access` (`none`/`bot`/`bot_and_global`)、`memory_count`、`tags`。`tags` 省略 = 不修改，`[]` = 清空。非法标签 → 422 中文 |
| GET / DELETE | `/api/bots/{id}/messages` | 历史消息 (含 Trace) / 清空对话。DELETE 可选 `?include_memories=true` 同时删除该 Bot 的记忆与摘要，返回 `{ok, deleted_memories}` |
| GET | `/api/bots/{id}/delegations` | 该 Bot 发出和收到的委派记录 |
| POST | `/api/bots/{id}/chat` | **SSE** 流式对话 `{message}` |
| POST | `/api/transcribe` | 语音转写 (multipart `file` + `language`) → `{text, model, duration_s}` |
| GET | `/api/reminders`；POST `/api/reminders/{id}/done` | 提醒列表 / 标记完成 |
| GET | `/api/quota` | 用量看板 `{model, daily_token_quota, today, total, per_bot, daily, delegations, transcribe}`；`today` / `total` 为 `{requests, prompt_tokens, completion_tokens, total_tokens}`。设置 › 用量 行的「已用 N%」由 iOS 计算：round(`today.total_tokens` / `daily_token_quota` × 100)，额度 ≤ 0 时不显示 (字段映射见下方「用量字段映射」) |
| GET | `/api/tools` | 工具列表 (中文标签，不含记忆工具) + 当前护栏参数 + `memory: {enabled, max_active, inject_max}` |
| GET / POST / DELETE | `/api/memories` | 列表 (`status` 逗号分隔或 `all`、`scope`、`bot_id`、`ids`、`visible_to`、`limit`、`before_id`) → `{memories, counts, limits}` / 手动添加 (201，直接生效) / 清空 (`scope`、`bot_id`、必须 `confirm=true`) → `{ok, deleted}` |
| GET / PATCH / DELETE | `/api/memories/{id}` | 单条 / 编辑 (仅 active，重新做敏感检查) / 删除 |
| POST | `/api/memories/{id}/confirm`、`/api/memories/{id}/reject` | 确认提议 (可带 `{content}` 编辑后确认；删除提议返回 `{ok, deleted_id}`) / 拒绝 |
| GET / PATCH | `/api/memory/settings` | `{enabled, server_enabled, active_count, max_active, max_chars}`；PATCH `{enabled}` |
| GET | `/api/health` | 健康检查 `{ok, model}` |

Bot 置顶 (schema v6)：Bot JSON 含 `pinned_at` (UTC ISO 8601 或 null)；PATCH `/api/bots/{id}` 接受 `pinned: true/false`，省略或 null 不修改。GET `/api/bots` 将置顶项按时间倒序、同时间按 id 升序排列，再列出未置顶项 (id 升序)。Web 客户端冻结，不实现置顶 UI。

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

SSE `status` 事件字段映射 (`agents/runtime.py` `status_data` ↔ iOS `VeraBotCore.ChatStatus`，由 `status_event_test.py` STAT-08 读取 Swift 源码断言键名与 phase 取值一致)：

| 后端键 | iOS 属性 | 说明 |
|---|---|---|
| `phase` | `ChatStatus.phase` / `knownPhase` (`Phase`: `recalling` / `thinking` / `tool`) | 未知值保留原文，状态机忽略 |
| `depth` | `depth` (缺失 = 0) | 0 = 当前 Bot；≥1 = 委派链 |
| `bot_name` | `botName` | 正在工作的 Bot |
| `tool` | `tool` | `phase = tool` 时的工具名 |
| `parent_id` | `parentID` | 外层 `tool_start.id`；状态机据此更新 `delegating.progress` |

状态机与头像映射见 [EXECUTION_STATE.md](../design/EXECUTION_STATE.md)。Web 冻结，忽略该事件。

SSE 事件：

```
event: delta        data: {"text": "…"}
event: tool_start   data: {"id", "name", "args"}
event: tool_result  data: {"id", "name", "args", "result"}
event: status       data: {"phase": "recalling" | "thinking" | "tool", "depth", "bot_name", "tool", "parent_id"}   # 新增，旧客户端忽略
event: error        data: {"message": "…", "code"?: "empty_reply"}
event: done         data: {"message_id", "usage": {prompt_tokens, completion_tokens, total_tokens}, "memory_ids": [本轮注入的记忆 id]}
```
