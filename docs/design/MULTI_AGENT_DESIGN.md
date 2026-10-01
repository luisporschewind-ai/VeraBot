# VeraBot 多 Agent 协作设计 (Multi-Agent Design) — v0.1.0

> 适用版本：v0.1.0 (迭代 2 引入，数据库 schema v2)。代码位置：`backend/verabot/agents/` (permissions / guardrails / context / delegation / runtime / prompts)。本文说明 Bot 之间的权限模型 (permission model)、上下文隔离 (context isolation)、防护措施 (guardrails)、审计 (audit)，以及 iOS 端的配置界面和设置页 (Settings) 的扩展方式。

## 1. 目标 (Goals)

| 目标 | 做法 |
|---|---|
| 最小权限 (Least privilege) | 新建 Bot 默认**没有任何工具、不能委派、不接受委派**，由用户按需开启 |
| 服务端强制 (Server-side enforcement) | 权限在后端检查，不依赖 prompt 或客户端；越权调用会被拒绝并写入审计日志 |
| 上下文隔离 (Context isolation) | 委派时只发送「问题 + 限长共享背景 + 对方的公开资料」，不发送对话历史和私有指令 |
| 可控的成本与环路 (Bounded cost & no loops) | 委派深度、环路检测、单轮次数上限、每用户 Token 预算 |
| 可追溯 (Traceability) | 每次委派 (包括被拒绝的) 都记录发送内容、结果和 Token；iOS 端可以查看 |

## 2. 权限模型 (Permission Model)

每个 Bot 有三个权限字段 (`bots` 表)：

| 字段 | 类型 | 含义 | 新 Bot 默认值 |
|---|---|---|---|
| `allowed_tools` | JSON list | 工具白名单 (Tool allowlist)：`get_weather` / `create_reminder` / `list_reminders` / `ask_bot` | `[]` |
| `delegate_to` | JSON list[int] | 委派白名单 (Delegation allowlist)：可以委派给哪些 Bot (必须是同一用户的 Bot) | `[]` |
| `accept_delegation` | 0/1 | 是否接受其他 Bot 的委派 (Accept delegation) | `0` |

- **要能委派**，必须同时满足：`ask_bot ∈ allowed_tools`、目标 ∈ `delegate_to`、目标的 `accept_delegation = 1`。
- 校验 (`services/bots.py::validate_perms`)：未知工具、其他用户的 Bot、把自己设为目标，都返回 **422**。
- 删除 Bot 时，会从其他 Bot 的 `delegate_to` 里移除它的 id。

### 强制执行点 (Enforcement Points)

1. **暴露层 (Exposure)**：`agents/permissions.py::get_schemas(bot, depth)` 只把有权限的工具 schema 交给 LLM。模型「看不到」没有开通的工具。system prompt 里也只列出允许委派的目标。
2. **执行层 (Execution)**：`tools/registry.py::run_tool` → `agents/permissions.py::is_permitted()` 再检查一次。即使模型编造了工具调用 (hallucinated tool call)，也会被拒绝，并记录 `log.warning` 和 `audit_log(kind='tool_denied')`。
3. **委派层 (Delegation)**：`ask_bot` (`agents/delegation.py`) 通过 `agents/guardrails.py::check_delegation` 依次检查 self / loop / not_in_allowlist / target_refuses / turn_cap / budget。每种拒绝都写入 `delegations (status='rejected', reason=…)` 和 `audit_log`，并向模型返回可读的错误。
4. 目标解析：先精确匹配 Bot 名称。只有唯一匹配、且较短名称不少于 2 个字符时，才做模糊匹配 (fuzzy match)。这是为了修复回归中发现的误路由问题：「BobBot」曾被匹配到 Bot「B」。

## 3. 上下文隔离 (Context Isolation)

被委派的 Bot (callee) 在一个**全新的、无历史**的会话里运行 (`agents/runtime.py::run_once`)。它收到的内容：

| 内容 | 是否发送 |
|---|---|
| 问题 `question` | ✅ |
| 共享背景 `shared_context` | ✅，最多 `VERABOT_MAX_SHARED_CONTEXT` (默认 2000) 字符，超出会被截断，并标记 `shared_truncated=1` |
| 调用方公开资料 (public profile) | ✅，名称 + persona 前 80 字 |
| 调用方对话历史 (history) / 私有指令 (instructions) / 用户其他数据 | ❌ |
| 被委派方自己的对话历史 | ❌ (不读取，也不写入。委派不会污染对方的记忆) |

实际发送的内容以 JSON 保存在 `delegations.payload`，方便审计时核对「到底共享了什么」。

## 4. 防护措施 (Guardrails)

| 防护 | 环境变量 (Env var) | 默认值 | 说明 |
|---|---|---|---|
| 委派深度 (Depth) | `VERABOT_MAX_DELEGATION_DEPTH` | 1 | depth ≥ 上限的 Bot 拿不到 `ask_bot` schema。调大后支持多跳委派 |
| 环路检测 (Loop detection) | — | 开启 | `chain` 记录调用链，目标已经在链上时拒绝 (`reason=loop`) |
| 单轮上限 (Per-turn cap) | `VERABOT_MAX_DELEGATIONS_PER_TURN` | 3 | 一次用户请求内的委派总次数 |
| Token 预算 (Budget) | `VERABOT_DAILY_TOKEN_QUOTA` + `users.token_budget` | 200000 | 超额时 chat 返回 **429**「今日 Token 额度已用完 (x / y)」，委派也会被拒绝 (`reason=budget`) |
| Bot 数量软上限 (Soft limit) | `MAX_BOTS_PER_USER` (兼容 `VERABOT_MAX_BOTS`) | 20 | 替代迭代 1 的硬编码 5。超出返回 400「已达到 Bot 数量上限（20 个）」。UI 不再显示 x/5 |
| 空回复重试 (Empty reply) | `VERABOT_EMPTY_REPLY_RETRIES` | 1 | 记录 finish_reason，重试后仍为空时发送 SSE `error{code: empty_reply}` |

`GET /api/tools` 会返回工具中文标签和当前 guardrails，iOS 编辑页的说明文字直接使用这些值。

## 5. 审计与委派记录 (Audit & Delegation Log)

- `delegations` 表新增：`status` (ok/rejected/error)、`reason`、`depth`、`payload`、`shared_truncated`、`prompt/completion/total_tokens`。
- `audit_log` 表：`tool_denied`、`delegation_rejected` 等安全事件 (user_id, bot_id, kind, detail, created_at)。
- API：`GET /api/bots/{id}/delegations` 返回该 Bot 发出和收到的委派记录 (访问其他用户的 Bot 返回 404)。
- iOS：对话页点标题 → Bot 详情 → 「协作记录」(DelegationLogView)。对话中的交接卡片 (Trace card) 会显示「协作记录 #id」、Token 数和截断标记。

## 6. 数据库迁移 (Migration, schema v1 → v2)

`db/schema.py::init_db()` 在启动时 (以及 `start.sh` 初始化时) 自动执行。迁移是幂等的 (idempotent)，版本号记在 `schema_meta`：

1. `ALTER TABLE` 增加上述列。**列默认值就是最小权限**，所以之后新建的 Bot 自动受保护。
2. 只在 v1 → v2 时执行一次：**已有的 Bot** 保留迭代 1 的行为，即开通全部 4 个工具、可以委派给同一用户的其他 Bot、`accept_delegation=1`。例如 demo 迁移后：Vera→[小研, 阿厨]，小研→[Vera, 阿厨]，阿厨→[Vera, 小研]。
3. 清理孤儿委派记录 (orphan delegations)，即 Bot 已被删除的记录。
4. 回滚：迁移不可逆，升级前请先复制 `backend/data/verabot.db`。(迭代 2 升级时的临时备份 `/tmp/verabot_prefix_backup.db` 已随 Mac 重启被清除。)

当前库版本是 **schema v3**（昵称、用户头像、Bot 照片）。v2 → v3 只 `ALTER` 加列并创建 `avatars` 表，不重跑上面的权限回填。字段与 API 见 [ARCHITECTURE.md](ARCHITECTURE.md)「资料与头像」。

## 7. iOS 界面

- **Bot 列表**：长按 → 「编辑与权限」；不显示数量页脚 (2026-10-01 移除)，到达上限时右上角 ＋ 置灰。新建表单里有最小权限提示。
- **BotEditView** (对话页点标题进入 Bot 详情，或 Bot 列表长按「编辑与权限」)：基本信息 (名称 / 表情 / 人设 / 指令)，另有「从相册设置头像 / 恢复默认」（照片优先于表情）；工具权限开关 (Tool allowlist)；委派目标 (没有开启 `ask_bot` 时不可选)；接受委派开关；guardrail 说明；「协作记录」入口。保存资料时调用 `PATCH /api/bots/{id}`；照片走 `/api/bots/{id}/avatar`，不跟「保存」按钮绑在一起。
- **Bot 详情** (对话页点标题「头像 + 名称 ›」)：以系统默认 sheet 弹出 (非 push、非全屏、下滑关闭)。它复用 `BotEditView(infoMode: true)`，内嵌完整设置：资料卡片、基本信息、工具权限、委派、协作记录，底部「清空对话」(有二次确认)。对话页导航栏只保留返回和标题。
- **首页导航栏**：没有照片时左上角仍是首字，和 ＋ 一样用系统圆形 toolbar 按钮，不自绘背景。有照片时按钮里显示圆形头像。

## 8. 设置页 (Settings) 与 TTS 扩展性

- 入口：首页 (我的 Bot) **左上角的用户头像** (`UserAvatar`)，点击进入 `SettingsView`。
- 分组顺序：账号 → 语音 → 关于 → 退出登录 (每组是一个独立的 `struct …Section: View`)：
  - `AccountSettingsSection`（实现在 `Features/Settings/UserProfileEditor.swift`）：头像（点按打开系统相册，圆形预览后上传；可恢复默认）、昵称（保存后写入 `AppState.displayName`，首页和对话立刻更新）、用户名、服务器地址。原「用量」页的账号分组已合并到这里，用量页不再显示账号信息。
  - `VoiceSettingsSection`：语音播放开关 (`@AppStorage("vb_tts_enabled")`，默认开启，同时控制用户消息和 Bot 回复气泡下方的 🔊 按钮 (共用 `SpeakButton`；用户消息的按钮右对齐))；语音引擎选择 (`vb_tts_engine`)，可选「本机 TTS」，「云端 TTS (即将支持)」用 `selectionDisabled` 置灰。
  - `AboutSettingsSection`：版本号 (CFBundleShortVersionString (CFBundleVersion))。
  - `SignOutSettingsSection`：单独一组，固定在最底部；「退出登录」(destructive，有二次确认)。
- **TTS 协议** (`frontend/ios/Packages/VeraBotKit/Sources/VeraBotTTS/TTS.swift`，SPM 模块 VeraBotTTS)：`protocol TTSEngine { speak(_:onFinish:) / stop() }`；`TTSEngineKind` (local / cloud，带 `isAvailable`)；`LocalTTSEngine` (AVSpeechSynthesizer, zh-CN)；`CloudTTSEngine` (占位 stub)；`@Observable SpeechPlayer` 根据当前引擎分派，并通过 `.environment` 注入。
- **扩展方法**：
  1. 在 `SettingsKeys` (VeraBotCore) 里加 key。
  2. 新建一个 `XxxSettingsSection` 并放进 `SettingsView` 的 Form。
  3. 云端 TTS：实现 `CloudTTSEngine` (例如调用后端 `/api/tts`)，再把 `TTSEngineKind.cloud.isAvailable` 改为 true。UI 不需要修改。

## 9. 测试 (Tests)

- `backend/scripts/test/multi_agent_test.py`：确定性测试，使用 mock LLM 和临时 DB，**24/24 通过** (MA-01 ~ MA-24，覆盖迁移、最小权限、校验、拒绝与审计、白名单、accept、隔离、截断、深度、环路、单轮上限、预算、软上限，以及 BUG-02/03/04/08/09)。头像 / 昵称另见 `avatar_profile_test.py`（不在本文件的多 Agent 范围内）。
- 真实 LLM 回归：`backend/scripts/test/api_regress.py`、`api_regress2.py`。iOS UI 回归见 [TEST_CASES_v0.1.md](../testing/TEST_CASES_v0.1.md) 的「回归测试」一节。
