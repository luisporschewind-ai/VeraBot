# 功能清单与 API 摘要 (Features & API) — v0.1.0

## 功能 (Features)

| 模块 | 说明 |
|---|---|
| 账号 (Accounts) | 用户名 + 密码注册 / 登录；bcrypt 哈希；JWT (HS256) Bearer Token；失效自动退出；设置页底部退出登录 (二次确认) |
| 租户隔离 (Per-user isolation) | 所有查询带 `user_id`；访问他人资源统一返回 404 (防枚举) |
| Bot 管理 | emoji 头像 + 颜色 + 昵称 + 人设 (多行) + 指令 (多行)；＋ 创建 (达到上限时 ＋ 置灰；列表不显示数量页脚)、Bot 详情编辑、长按「编辑与权限」、左滑删除；软上限 20 (`MAX_BOTS_PER_USER`) |
| 流式对话 (Streaming, SSE) | `POST /api/bots/{id}/chat` 返回 `text/event-stream`，逐 token 渲染；工具卡片、交接 Trace 卡片、错误气泡 |
| 记忆 (Memory) | 每个 Bot 独立保存历史，最近 20 条注入上下文；清空对话 (二次确认) |
| 工具 (Tool calling) | 可插拔注册表：`get_weather` (Open-Meteo，免 Key)、`create_reminder`、`list_reminders`、`ask_bot` |
| 多 Agent 协作 | 工具 / 委派白名单、接受委派开关、上下文隔离、深度 / 环路 / 单轮上限 / Token 预算、审计日志、协作记录页 → [MULTI_AGENT_DESIGN.md](../design/MULTI_AGENT_DESIGN.md) |
| 每日 Token 预算 | 超额返回 429，委派也被拒 |
| 提醒 / 用量 (Reminders / Quota) | Tab 页；提醒只落库不推送；用量看板：请求数、Token、7 日趋势、按 Bot 分布 (不含账号信息，账号信息在设置页) |
| 语音输入 (Voice input) | Web：录音 → `/api/transcribe` (OpenAI) → 填入输入框；iOS：系统 Speech 框架 (zh-CN)；都不自动发送 |
| 语音播放 (TTS) | 用户消息和 Bot 回复下方 🔊，本机 AVSpeechSynthesizer；设置里可关闭；云端 TTS 占位 |
| 设置页 (Settings) | 首页左上角头像进入；账号 (头像 / 用户名 / 服务器) → 语音 → 关于 → 退出登录 (单独一组，位于最底部) |
| 导航 / 键盘 | 二级页面隐藏 Tab 栏；对话标题 → Bot 详情 sheet；首页原生圆形按钮；输入栏随键盘上移、点空白 / 下拉收起 |
| 附件 (Attachments) | 占位：＋ 菜单 图片 / 相机 / 文件「即将支持」(禁用) |

## API 摘要

所有 `/api/*` (除 auth / health) 需要 `Authorization: Bearer <JWT>`。完整 schema：后端启动后访问 `/docs`。

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/auth/register`、`/api/auth/login` | `{username, password}` → `{token, user}` |
| GET | `/api/me` | 当前用户 |
| GET / POST | `/api/bots` | Bot 列表 / 创建 (新 Bot 默认最小权限) |
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
