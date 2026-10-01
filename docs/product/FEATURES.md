# 功能清单与 API 摘要 (Features & API) — v0.1.0

## 功能 (Features)

| 模块 | 说明 |
|---|---|
| 账号 (Accounts) | 用户名 + 密码注册 / 登录；bcrypt 哈希；JWT (HS256) Bearer Token；失效自动退出；设置页底部退出登录 (二次确认)。昵称可在设置页修改（1–32 字，去空白），首页左上角和对话里的用户名立刻更新 |
| 租户隔离 (Per-user isolation) | 所有查询带 `user_id`；访问他人资源统一返回 404 (防枚举) |
| Bot 管理 | emoji 头像 + 颜色 + 昵称 + 人设 (多行) + 指令 (多行)；＋ 创建 (达到上限时 ＋ 置灰；列表不显示数量页脚)、Bot 详情编辑、长按「编辑与权限」、左滑删除；软上限 20 (`MAX_BOTS_PER_USER`)。列表每行右上角显示最后消息时间（今天 HH:mm / 昨天 / 本周星期几 / M/d / 非今年 yyyy/M/d，无消息回退创建时间）；首页不显示大导航标题；右上角放大镜点按后才出现系统搜索栏（平时不显示搜索框，下拉也不出现；取消后收起并清空），当前只过滤屏幕上已加载的列表（Bot 名称和最后一条消息预览）；完整聊天历史搜索、搜索历史等移至后续迭代。所有头像（用户 / Bot，照片或表情 / 首字）都显示为正圆。用户和每个 Bot 都可以另设一张圆形照片头像（相册选择、可更换；iOS 不提供「恢复默认」入口）；表情字段保留，没有照片时继续显示 |
| 流式对话 (Streaming, SSE) | `POST /api/bots/{id}/chat` 返回 `text/event-stream`，逐 token 渲染；工具卡片、交接 Trace 卡片、错误气泡 |
| 记忆 (Memory) | 每个 Bot 独立保存历史，最近 20 条注入上下文；清空对话 (二次确认) |
| 工具 (Tool calling) | 可插拔注册表：`get_weather` (Open-Meteo，免 Key)、`create_reminder`、`list_reminders`、`ask_bot` |
| 多 Agent 协作 | 工具 / 委派白名单、接受委派开关、上下文隔离、深度 / 环路 / 单轮上限 / Token 预算、审计日志、协作记录页 → [MULTI_AGENT_DESIGN.md](../design/MULTI_AGENT_DESIGN.md) |
| 每日 Token 预算 | 超额返回 429，委派也被拒 |
| 提醒 / 用量 (Reminders / Quota) | 提醒为 Tab 页，只落库不推送；用量看板从「设置 › 用量」进入：请求数、Token、7 日趋势、按 Bot 分布 (不含账号信息，账号信息在设置页) |
| 语音输入 (Voice input) | Web：录音 → `/api/transcribe` (OpenAI) → 填入输入框；iOS：系统 Speech 框架 (zh-CN)；都不自动发送 |
| 语音播放 (TTS) | 用户消息和 Bot 回复下方 🔊，本机 AVSpeechSynthesizer；设置里可关闭；云端 TTS 占位 |
| 设置页 (Settings) | 首页左上角头像进入；账号 (头像 / 昵称 / 用户名) → 用量 (push 用量看板) → 通用 (外观：跟随系统 / 浅色 / 深色；通知开关，开启时申请系统授权，被拒绝则回退并提供「前往设置」；触感反馈开关，控制 App 内所有 sensoryFeedback；语言：显示当前语言，点按打开系统设置中本 App 页面切换) → 语音 → 关于 (版本号) → 退出登录 (单独一组，位于最底部)。头像用系统 PhotosPicker，预览为圆形，确认后上传 |
| 调试页 (Debug) | 设置页导航栏右上角 🐞 (`ladybug`) push 进入：服务器地址、后端健康检查 (`GET /api/health`)、版本 / 构建号 / Bundle ID / 系统版本 / 构建配置。开发信息不出现在普通设置里 |
| 导航 / 键盘 | 二级页面隐藏 Tab 栏；对话标题为可点击的原生胶囊按钮（iOS 26 Liquid Glass，旧系统 bordered 回退）并打开 Bot 详情 sheet；首页原生圆形按钮（左上角头像为固定 30×30 正圆；右上角 放大镜 搜索 与 ＋ 创建 为两个独立圆形按钮，iOS 26 用 `ToolbarSpacer(.fixed)` 分开）；工具栏 / sheet 的取消、关闭为系统圆形 X（iOS 26 `Button(role: .cancel / .close)`，确认框里的取消仍是文字）；输入栏随键盘上移、点空白 / 下拉收起 |
| 视觉风格 (Visual style) | 页面白底（深色黑底），分组 / 卡片 / Bot 气泡浅灰 `#F2F2F7`（深色 `secondarySystemBackground`）；「助理」列表为白底全宽平铺、无分隔线；iOS 26 Liquid Glass（系统导航栏 / Tab 栏 / 工具栏按钮，`.glass` 胶囊、`.glassProminent` 主按钮，旧系统 bordered 回退）。颜色集中在 `Core/UI/Theme.swift` 语义色，设置 › 外观 切换时全局一致 |
| 附件 (Attachments) | 占位：＋ 菜单 图片 / 相机 / 文件「即将支持」(禁用) |

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
| GET / POST | `/api/bots` | Bot 列表 / 创建 (新 Bot 默认最小权限)。每个 Bot 另有 `has_avatar`、`avatar_updated_at`；`avatar` 仍是 emoji |
| GET / PATCH / DELETE | `/api/bots/{id}` | 详情 / 修改 (含 `allowed_tools`、`delegate_to`、`accept_delegation`) / 删除 |
| GET / DELETE | `/api/bots/{id}/messages` | 历史消息 (含 Trace) / 清空记忆 |
| GET | `/api/bots/{id}/delegations` | 该 Bot 发出和收到的委派记录 |
| POST | `/api/bots/{id}/chat` | **SSE** 流式对话 `{message}` |
| POST | `/api/transcribe` | 语音转写 (multipart `file` + `language`) → `{text, model, duration_s}` |
| GET | `/api/reminders`；POST `/api/reminders/{id}/done` | 提醒列表 / 标记完成 |
| GET | `/api/quota` | 用量看板 |
| GET | `/api/tools` | 工具列表 (中文标签) + 当前护栏参数 |
| GET | `/api/health` | 健康检查 `{ok, model}` |

SSE 事件：

```
event: delta        data: {"text": "…"}
event: tool_start   data: {"id", "name", "args"}
event: tool_result  data: {"id", "name", "args", "result"}
event: error        data: {"message": "…", "code"?: "empty_reply"}
event: done         data: {"message_id", "usage": {prompt_tokens, completion_tokens, total_tokens}}
```
