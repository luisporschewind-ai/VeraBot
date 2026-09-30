# 更新日志 (CHANGELOG)

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/)，版本号遵循 [SemVer](https://semver.org/lang/zh-CN/) (见 [CONTRIBUTING.md](../CONTRIBUTING.md))。时间为北京时间 (UTC+8)。

## [Unreleased]

### 新增 (Added)

- 设计文档 (未实现)：[design/GMAIL_CAPABILITY.md](design/GMAIL_CAPABILITY.md) — Gmail 能力方案 (v1 直连 Gmail API + Google OAuth，未来 MCP)，含 HITL 发送确认、权限与委派集成、测试计划和待 Boss 决策的开放问题。
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

