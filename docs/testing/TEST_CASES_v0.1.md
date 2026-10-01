# VeraBot v0.1 测试用例与执行结果 (Test Cases & Results)

> 截图位置：iOS [`assets/screenshots/ios/test/`](../../assets/screenshots/ios/test/) (T*) 和 [`ios/regress/`](../../assets/screenshots/ios/regress/) (R*)，Web [`assets/screenshots/web/`](../../assets/screenshots/web/)。iOS 截图为 471×1024 JPEG。
> 过时截图：`R34_form_keyboard` (仍显示已移除的键盘工具栏「完成」)、`R11_settings` (旧分组顺序)。此外**所有 iOS 截图 (T* / R*) 都早于 2026-10-01 的界面改动** (设置页重排、正圆头像、白底 + Liquid Glass、浮动输入栏、富文本等)，只代表当时的界面；2026-10-01 新增的 UI-* / MSG-* 用例尚无截图，大多待 Boss 验收。
> 版本说明：「迭代 1」= MVP 基线 (TC-01~31)，「迭代 2」= 缺陷修复 + 多 Agent 权限 + 设置 / TTS / 键盘等改动；两轮都属于 v0.1.0 (见 CHANGELOG)。
> v0.1.0 目录重构 (2026-09-30 18:00 后) 的回归结果见文末「v0.1.0 重构回归」。

- 执行日期 (Date)：2026-09-30 12:35–13:01 (UTC+8)
- 环境 (Env)：macOS Intel + iPhone 17 模拟器 (iOS 26)，后端 FastAPI + SQLite @ http://127.0.0.1:8000，LLM `deepseek-chat`
- 方法 (Method)：API 黑盒 (Python urllib / curl，`--noproxy '*'`) + 模拟器 UI (CGEvent 点击 + 截图)；未修改任何应用源码
- 测试数据 (Test data)：临时用户 `qa_tmp_43016` (5 个测试 Bot)；demo 账号下临时 Bot「QA临时」。测试结束后已全部清理
- 汇总 (Summary)：**31 条用例：通过 26 / 失败 4 / 跳过 1**

| ID | 模块 | 用例 | 步骤 | 预期 | 结果 | 备注 |
|---|---|---|---|---|---|---|
| TC-01 | 登录 Login | 登录页展示 (UI) | 清空 Token 后启动 App | 显示 Logo、用户名/密码输入框；输入为空时「登录」按钮禁用 | 通过 | 截图 T01_login |
| TC-02 | 登录 Login | 正确密码登录 | API `POST /api/auth/login` demo/verabot2026；UI 输入后点登录 | 200 + JWT；UI 进入「我的 Bot」列表 | 通过 | UI 进入 Bot 列表 (T03_bot_list) |
| TC-03 | 登录 Login | 错误密码 / 未知用户 | API 错误密码、不存在的用户名；UI 输入错误密码 | 401「用户名或密码错误」；UI 显示红色提示且停留在登录页 | 通过 | 两种情况文案一致，不会泄露用户是否存在 (no user enumeration)；T02_login_wrong |
| TC-04 | 登录 Login | Token 持久化 (Token Persistence) | 登录后 `simctl terminate` 杀进程再启动 | 无需重新登录，直接显示 Bot 列表 | 通过 | Token 存在 UserDefaults 里 (代码注释已写明生产环境应改用 Keychain) |
| TC-05 | 注册 Register | 注册校验 | 注册新用户；重复注册；用户名 2 位 / 密码 5 位 | 200；409「用户名已存在」；422 | 通过 | |
| TC-06 | 安全 Security | 无效 Token → 401 | 不带 Token、乱码 Token、篡改 payload (sub=1) 的 JWT 分别请求 `/api/bots`、`/api/me` | 全部 401 | 通过 | 「未登录」/「登录已失效，请重新登录」 |
| TC-07 | 安全 Security | App 内 Token 失效处理 | 往 App 容器的 plist 写入无效 vb_token 后重启 | 后端 401 → App 自动退出到登录页 | 通过 | 登录页没有任何提示 (如「登录已过期」)，属于体验问题 |
| TC-08 | 用户隔离 Isolation | 新用户看不到 demo 的数据 | 注册临时用户 → `GET /api/bots`、`/api/reminders` | Bot 列表为空 (limit=5)，提醒列表为空 | 通过 | |
| TC-09 | 用户隔离 Isolation | 越权访问 demo 的 Bot (IDOR) | 临时用户对 Vera(id=7) 调 GET / PATCH / DELETE / messages / clear / chat，以及 `reminders/1/done` | 全部 404，数据不变 | 通过 | 7/7 都是 404，他人资源与不存在的资源返回一致 |
| TC-10 | Bot CRUD | UI 创建 Bot | Bot 列表点 ＋ → 填昵称「QA临时」、选头像🐙和橙色、填人设 → 创建 | Sheet 关闭，列表出现新 Bot，底部显示 4/5 | 通过 | T05_create_form；API 同名创建返回 409「已有同名 Bot」 |
| TC-11 | Bot CRUD | 编辑 Bot (Edit) | API `PATCH` 修改 persona、avatar；再改成已存在的名字 | 200 且字段更新；同名 409 | 通过 | iOS 端没有编辑入口 (只能创建/左滑删除)，只能通过 API 验证 |
| TC-12 | Bot CRUD | 删除 Bot (Delete) | API `DELETE /api/bots/{id}` → 再 GET | 200，之后 404；消息级联删除 (cascade) | 通过 | UI 左滑删除没执行 (点击工具不支持滑动)，用 API 覆盖 |
| TC-13 | Bot CRUD | 5 个 Bot 上限 (Limit) | 临时用户建满 5 个后建第 6 个 | 400「每个用户最多创建 5 个 Bot」 | 通过 | iOS ＋ 按钮在 count≥limit 时禁用 (代码确认) |
| TC-14 | Bot CRUD | 空白名称校验 | `POST /api/bots {"name":"   "}` | 400/422 拒绝 | **失败** | 实际返回 201，创建了 name="" 的 Bot (BUG-02) |
| TC-15 | Bot CRUD | 编辑时名称去空格 (Trim) | `PATCH {"name":"  测试D2  "}` | 保存为「测试D2」 | **失败** | 原样保存成 "  测试D2  " (BUG-03) |
| TC-16 | 对话 Chat | 流式输出 (Streaming, SSE) | API 发「你好…」；UI 在 QA临时 发「石家庄天气怎么样」，2.2 秒时截图 | `text/event-stream`，多个 delta 事件后是 done；UI 显示 ▍ 光标，内容逐步出现 | 通过 | 17 个 delta，首字 2.03 秒，总耗时 2.21 秒；T08_streaming |
| TC-17 | 对话 Chat | 空消息 (Empty) | API message=""；UI 输入框为空 | 422；UI 的「发送」按钮禁用 | 通过 | |
| TC-18 | 对话 Chat | 纯空白消息 (Whitespace) | API message="   " | 400/422 拒绝 | **失败** | 返回 200，保存了一条空的 user 消息，并照常调用 LLM 消耗 Token (BUG-04) |
| TC-19 | 对话 Chat | 长消息 (Long message) | 发 3997 字的消息；再发 4001 字 | 正常回复「收到」；4001 字返回 422 | 通过 | 4000 字消息会留在 20 条历史窗口里，后续每轮 prompt 都很大 (该临时用户当日用了 9.8 万 Token) |
| TC-20 | 对话 Chat | 清空对话 (Clear, 垃圾桶图标) | UI 点右上角 🗑；API `DELETE /messages` 后再问之前说过的事实 | 对话清空只剩欢迎语；清空后 Bot 不再记得 | 通过 | 点击后立即清空，**没有二次确认** (BUG-05)；清空后问幸运数字，回答「不知道」 |
| TC-21 | 记忆 Memory | 同一 Bot 记住事实 | 对测试A 说「幸运数字 427、猫叫豆包」→ 再问 | 回答里有 427 和豆包 | 通过 | 回复：「幸运数字 427，猫叫豆包。」 |
| TC-22 | 记忆 Memory | 不同 Bot 记忆隔离 | 用同样的问题问测试B | 不知道这两个事实 | 通过 | 测试B：「不知道…这两个信息我这边都没有记录」 |
| TC-23 | 天气工具 Weather | 实时天气 + 工具卡片 | UI/API：「石家庄天气怎么样」；「火星城XYZ123的天气」 | 调用 get_weather (Open-Meteo)，显示「天气查询」卡片和 3 天预报；未知城市返回友好错误 | 通过 | 数据源 Open-Meteo，当前 19.9–20°C；未知城市返回「找不到城市」；T09_weather_done |
| TC-24 | 天气工具 Weather | 温度区间 Markdown 渲染 | 看天气回复里的「15~21.2°C」 | 按原文显示「~」 | **失败** | 已知 bug 已确认：两个 ~ 之间的文字被渲染成删除线 (strikethrough)，~ 本身消失 (BUG-01) |
| TC-25 | 提醒工具 Reminder | 对话创建提醒 → 提醒 Tab | UI：「明天下午3点提醒我给妈妈打电话」→ 切到 提醒 Tab；API：列表 + `POST /done` | 显示「创建提醒」卡片；提醒 Tab 显示「给妈妈打电话 2026-10-01 15:00 · 来自 QA 临时」；done=1 | 通过 | T14_reminders_tab；同一 Bot 重复发相同请求时模型没调用工具 (视作重复请求)，换一个 Bot 就正常 |
| TC-26 | 委派 ask_bot | Bot 间委派 + 交接卡片 (Trace card) | UI 在 QA临时 说「请问问阿厨：今晚吃什么？」；API 测试A → 测试B | 调用 ask_bot；卡片显示「QA临时 → 阿厨」、问题、共享背景和 ↩ 回答；最终回复引用阿厨的回答 | 通过 | T11_delegation_trace；API 返回 to_bot=测试B；委派给不存在的 Bot 时返回 error + available_bots |
| TC-27 | 委派 ask_bot | 禁止链式委派 (No chaining) | 要求测试A 让测试B 再 ask_bot 测试C | 只有 1 次委派，被委派的 Bot 没有 ask_bot 工具 | 通过 | 测试B 回复自己没有 ask_bot；但回复里把内部工具名 (create_reminder…) 暴露给了用户 (BUG-08) |
| TC-28 | 用量 Quota | 用量页与 API | UI 切到 用量 Tab；API `GET /api/quota` | 显示今日额度进度条、累计 Token、Bot 间协作次数、模型；数据随使用刷新；只统计本人的 Bot | 通过 | 今日用量 29,788 → 38,647；T15_quota_tab；每日额度只展示、不拦截 (BUG-06) |
| TC-29 | 附件 ＋ Menu | ＋ 菜单禁用项 | 点 ＋ → 点「图片」 | 显示 文件/相机/图片 (即将支持)，都是禁用状态，点击没有反应 | 通过 | T13_plus_menu |
| TC-30 | 异常 Error | 后端停机 (Backend down) | 停掉 uvicorn → App 发「你好」→ 重启后端 | 显示「⚠️ 无法连接服务器。」，不崩溃；重启后恢复 | 通过 | 错误气泡前有两个空行 (BUG-07)；T17_backend_down；后端已恢复 |
| TC-31 | 语音 Voice | 语音输入 /api/transcribe | — | — | 跳过 | 按要求跳过 |


## 缺陷列表 (Bugs)

| ID | 严重度 Severity | 描述 | 复现 | 建议修复 (Suggested fix) |
|---|---|---|---|---|
| BUG-01 | 中 Medium | 温度区间里的「~」被当成 Markdown 删除线 | 问天气，回复「15~21.2°C…10~22.3°C」中间的文字被划掉 | 在 `ChatView.swift` 的 `markdown()` 解析前把单个 `~` 转义成 `\~`；或在 system prompt 里要求用「至 / –」表示区间 |
| BUG-02 | 中 Medium | 可以创建空白名称的 Bot | `POST /api/bots {"name":"   "}` → 201，name="" | `BotIn.name` 先 strip 再校验长度 (pydantic `field_validator` / `StringConstraints(strip_whitespace=True, min_length=1)`)，否则返回 422 |
| BUG-03 | 低 Low | PATCH 修改名称时没有去空格和空白校验；任何异常都被报成 409 | `PATCH {"name":"  测试D2  "}` 原样保存 | `BotPatch` 用和 BUG-02 相同的校验器；只捕获 `sqlite3.IntegrityError` 并返回 409 |
| BUG-04 | 中 Medium | 纯空白消息也能通过校验 | `POST /chat {"message":"   "}` → 200，保存空消息并调用 LLM | `ChatIn` 增加 strip 后非空的校验，返回 422 (iOS 端已经拦截，但 Web/API 没有) |
| BUG-05 | 低 Low | 清空对话 (🗑) 没有二次确认，误点会直接丢掉全部历史和记忆 | 对话页点垃圾桶 | 加 `.confirmationDialog("清空与该 Bot 的全部对话？")` |
| BUG-06 | 低 Low | 每日 Token 额度 (200,000) 只展示、不拦截 (代码审查确认) | `DAILY_TOKEN_QUOTA` 只在 `/api/quota` 里用到 | chat 前查询当日用量，超额时返回 429 / SSE error 事件 |
| BUG-07 | 低 Low | 错误气泡开头有两个空行 | 停后端后发消息 | `send()` 里当 `text` 为空时直接赋值 `"⚠️ …"`，不再拼接 `"\n\n"` |
| BUG-08 | 低 Low | 被委派的 Bot 会把内部工具名暴露给用户 | 要求链式委派，子 Bot 的回答里列出了 `create_reminder`… | 在委派 system prompt 里加一句：遇到转交请求时说明无法转交，不要提及内部工具 |
| BUG-09 | 低 Low (偶发 Intermittent) | LLM 返回空内容时静默保存「（无回复）」，没有 error 事件 | 出现 1 次，之后重试 0/3 未复现 | 内容为空时记录 finish_reason 并自动重试一次，仍为空则发送 error 事件 |

其他观察 (Observations，非缺陷)：iOS 没有编辑 Bot 的界面；Token 失效自动退出后登录页没有提示文案；删除 Bot 后 delegations 表里的记录会残留 (没有外键级联)。


---

## 回归测试 (Regression) — 迭代 2 (Iteration 2)，2026-09-30

环境：MacBook, iPhone 17 Simulator, 后端 uvicorn :8000 (deepseek-chat), DB schema v2。自动化脚本：`backend/scripts/test/multi_agent_test.py` (mock LLM)；`backend/scripts/test/api_regress.py` + `api_regress2.py` (真实 LLM，临时用户 `qa_reg_*`，测试后已删除)。截图：[`assets/screenshots/ios/regress/`](../../assets/screenshots/ios/regress/)。

### 汇总 (Summary)

| 类别 | 用例数 | 通过 | 失败 | 跳过 |
|---|---|---|---|---|
| 原 31 条用例 (TC-01~31) | 31 | 30 | 0 | 1 (TC-31 语音输入，按要求跳过) |
| 多 Agent 自动化 (MA-01~24, mock) | 24 | 24 | 0 | 0 |
| 多 Agent 真实 LLM (REG-*) | 10 | 10 | 0 | 0 |
| 设置 / TTS / 导航 UI (SET-01~10, NAV-01~04) | 14 | 14 | 0 | 0 |
| 键盘 Keyboard (KB-01~12) | 12 | 12 (其中 KB-04/08/09 为代码审查) | 0 | 0 |
| **合计** | **91** | **90** | **0** | **1** |

> 说明：API 类用例和 4 条原失败用例都用新代码实际重跑过。部分纯 UI 用例 (TC-07 Token 失效、TC-29 ＋ 菜单、TC-30 断网气泡) 本轮没有重新点测，这些代码除了 BUG-07 的错误文本拼接以外没有改动，因此沿用迭代 1 的结果，建议下轮补测。

### 原失败用例 (Previously failing)

| ID | 迭代 1 | 迭代 2 | 说明 |
|---|---|---|---|
| TC-14 | 失败 (BUG-02) | 通过 | 空白名称 → 422「名称不能为空」 |
| TC-15 | 失败 (BUG-03) | 通过 | PATCH `"  测试D2  "` 会去掉首尾空格；空白 → 422 |
| TC-18 | 失败 (BUG-04) | 通过 | 纯空白消息 → 422 |
| TC-24 | 失败 (BUG-01) | 通过 | 「2~3 次」「7~8 小时」「40%~60%」原样显示，没有删除线 (R14/R16) |
| TC-13 | 通过 (硬上限 5) | 通过 (行为变更) | 改为软上限 20，第 21 个 → 400「已达到 Bot 数量上限（20 个）」；UI 不再显示 x/5 (R01) |

### 缺陷验证 (Bug verification)

| Bug | 修复文件 | 验证 | 结果 |
|---|---|---|---|
| BUG-01 ~ 删除线 | ios `ChatView.swift` (`markdown()` 转义 ~) | 天气 / 历史消息里的区间 ~ 原样显示 | ✅ |
| BUG-02 空白名称 | backend `api/schemas.py` (BotIn 校验器；原 `app.py`) | TC-14, MA-19 | ✅ |
| BUG-03 PATCH trim / 409 | `api/schemas.py` + `api/routers/bots.py` (BotPatch + 只捕获 IntegrityError) | TC-15, MA-20 | ✅ |
| BUG-04 空白消息 | `api/schemas.py` (ChatIn) | TC-18, MA-21 | ✅ |
| BUG-05 清空无确认 | `ChatView.swift` (`.confirmationDialog`) | 🗑 弹出「清空与「Vera」的全部对话？」，点外部取消后 6 条消息仍在 (R19) | ✅ |
| BUG-06 额度不拦截 | `api/routers/chat.py`, `db/` (`token_budget`) | REG-BUDGET：429「今日 Token 额度已用完（29,144 / 100）」；委派也被拒 (MA-17) | ✅ |
| BUG-07 错误气泡空行 | `ChatView.swift` (`appendError`)、`web/app.js` | 代码审查 + 429 / 断网路径使用同一函数 | ✅ |
| BUG-08 泄露工具名 | `agents/prompts.py` (委派 prompt) | TC-27：测试B 只说无法转交，没有提到工具名；MA-24 | ✅ |
| BUG-09 静默「无回复」 | `agents/runtime.py`, `services/llm.py` (finish_reason + 重试 + SSE error) | MA-22 (重试后成功)、MA-23 (仍为空 → `empty_reply`) | ✅ |

### 多 Agent 真实 LLM (REG-*)

| ID | 场景 | 结果 |
|---|---|---|
| REG-MIG | 迁移后 demo Bot 可以互相委派 (Vera→[8,9] …) | ✅ |
| REG-LP | 新 Bot 默认 `allowed_tools=[]`、`delegate_to=[]`、`accept=0` | ✅ |
| REG-PERM | PATCH 权限；未知工具 / 其他用户的 Bot / 自己 → 422 | ✅ |
| REG-TOOL | 没有开通天气的 Bot 不调用天气，回复「暂未开通「天气查询」能力…」 | ✅ |
| REG-CTX | 委派 payload 里没有对话历史中的「秘密」 | ✅ |
| REG-ALLOW | 目标不在白名单 → rejected / not_in_allowlist | ✅ |
| REG-ACCEPT | 目标 accept=0 → rejected / target_refuses | ✅ |
| REG-AUDIT | audit_log 写入 delegation_rejected / tool_denied | ✅ |
| REG-BUDGET | 预算 100 → 429；恢复后正常 | ✅ |
| REG-422 | 校验错误信息去掉「Value error, 」前缀 | ✅ |

另外 TC-26 委派成功，返回 delegation_id=18、205 tokens；TC-16 流式输出首 token 1.93 s。

### 设置页 / TTS (Settings)

| ID | 场景 | 步骤 | 结果 | 截图 |
|---|---|---|---|---|
| SET-01 | 首页左上角头像 | 登录后看「我的 Bot」 | 左上角显示用户首字母头像「D」 | R10_home_avatar |
| SET-02 | 进入设置 | 点头像 | 打开「设置」(当时顺序：账号 / 语音 / 关于；R11 截图为更早的「语音在前」，已过时)。**现顺序见 SET-10**：账号 → 用量 → 通用 → 语音 → 关于 → 退出登录 | R11_settings (过时), R31_settings_account_top |
| SET-03 | 语音引擎 | 点「本机 TTS」 | 本机 TTS ✓；云端 TTS (即将支持) 置灰，点击无效 (没有写入 vb_tts_engine) | R12_engine_picker |
| SET-04 | 关闭语音播放 | 关闭开关 → 打开 Vera 对话 | plist `vb_tts_enabled=0`；引擎选择置灰；气泡下方没有 🔊 | R13_tts_off, R14_chat_tts_off |
| SET-05 | 重启后保持 (Persist) | 关闭状态下 terminate + launch | 重启后仍为关闭，没有 🔊 | R14_chat_tts_off |
| SET-06 | 重新开启 | 开启 → 回到对话 | `vb_tts_enabled=1`，🔊 重新出现 | R16_chat_tts_on |
| SET-07 | 朗读 | 点 🔊 | 按钮变成 ■ (停止)，再点停止 | R17_tts_playing |
| SET-08 | 退出登录 | 设置 → 滚动到最底部 → 退出登录 → 确认 | 弹出「确定退出登录？」；确认后回到登录页，vb_token 被清除；重新登录 demo 成功 | R20, R21, R22 |
| SET-09 | 用户消息也有 🔊 | 临时 Bot 一问一答 → 开 / 关「语音播放」 | 开启时用户气泡下方 (右对齐) 和 Bot 气泡下方都有 🔊；关闭后两者都隐藏 | R23_user_tts, R23b_user_tts_off |
| NAV-01 | 二级页面隐藏 Tab 栏 | 打开 小研 对话 → 返回 → 点头像进设置 → 返回 | 对话页、设置页不显示底部「助理 / 提醒」Tab 栏（2026-10-01 起「用量」不再是 Tab），输入栏贴底部安全区；返回 Bot 列表后 Tab 栏重新出现 (Bot 设置、协作记录、新建 Bot 同样隐藏) | R24_chat_no_tabbar, R25_settings_no_tabbar, R26_back_tabbar |
| NAV-02 | 对话标题 → Bot 详情 sheet | 打开 小研 对话 → 点顶部胶囊标题（头像 + 名称，无下箭头） | 对话页导航栏只有返回 + 胶囊标题（右上角 ⚙/🗑 已移除）；以系统默认 sheet 弹出「Bot 详情」（非 push、非全屏，2026-10-01 起不能下滑关闭，见 DETAIL-UI-09），内嵌完整设置：头像/名称/标签/人设卡片、默认形象、人设、自定义指令、记忆、工具权限、委派目标/接受委派、协作记录 (2026-10-01 改版，见 DETAIL-UI)、底部「清空对话」；右上角「保存」、左上角「关闭」 | R27_chat_title, R28_bot_info |
| NAV-03 | 详情页清空对话仍需确认 | Bot 详情 → 滚动到底部 → 清空对话 | 弹出「清空与「小研」的全部对话？」确认框；取消后消息仍在 | R29_clear_confirm_from_info |
| NAV-04 | 首页导航栏原生样式 | 看「我的 Bot」导航栏 | 左上角头像（首字母）与右上角 ＋ 均为 iOS 26 系统 Liquid Glass 圆形按钮，无自绘背景 | R30_home_nav_native |
| SET-10 | 设置页账号置顶 | 首页点头像进入设置 | 分组顺序：账号 → 用量 → 通用 (外观 / 通知 / 触感反馈 / 语言) → 语音 → 关于 → 退出登录；账号区没有「服务器」行 (2026-10-01 再次更新) | R31_settings_account_top (旧版，退出登录仍在账号组内)；新版由 Boss 目视验证 |
| UI-01 | Bot 列表无数量页脚 | 「我的 Bot」列表滚动到底部 | 列表下方不再显示「已创建 N 个 Bot · …」页脚 (2026-10-01) | — (Boss 目视验证) |
| UI-02 | 用量页无账号分组 | 设置 → 用量 → 滚动到底部 | 只显示今日额度 / 累计 / 近 7 日 / 按 Bot 统计；没有 账号 / 服务器 / 退出登录 (2026-10-01) | — (Boss 目视验证) |
| UI-03 | 设置页退出登录在最底部 | 设置 → 滚动到最底部 → 退出登录 → 确认 → 重新登录 demo | 「退出登录」单独一组位于「关于」之下，红色 destructive；确认后回到登录页；重新登录后回到「我的 Bot」 (2026-10-01) | — (Boss 目视验证) |
| UI-04 | 用量不再是 Tab | 登录后看底部 Tab；进设置点「用量」 | Tab 只有「助理」「提醒」；「用量」位于「账号」下方，push「用量看板」，返回回到设置 (2026-10-01) | — (Boss 验收) |
| UI-05 | 调试页 | 设置 → 导航栏右上角 🐞 | push「调试」：服务器地址、状态 (正常 / 无法连接) + 模型、重新检查、版本 / 构建号 / Bundle ID / 系统 / 构建配置；普通设置里不再出现服务器地址和构建号 (2026-10-01) | — (Boss 验收) |
| UI-06 | 外观 | 设置 → 通用 → 外观 选 深色 / 浅色 / 跟随系统 → 杀掉 App 重开 | 立即生效；重开后保持 (`vb_appearance`) | — (Boss 验收) |
| UI-07 | 通知授权 | 打开「通知」→ 系统弹窗选「不允许」；再打开一次 | 拒绝后开关回到关闭；再次打开时弹「通知权限已关闭」，可「前往设置」；允许时开关保持开启 (`vb_notifications_enabled`) | — (Boss 验收) |
| UI-08 | 触感反馈 | 关闭「触感反馈」→ 发送消息 / 语音输入 / 完成提醒 | 关闭后不再有触感；开启后恢复 (`vb_haptics_enabled`，需真机) | — (Boss 验收) |
| UI-09 | 语言 | 设置 → 通用 → 语言 | 显示当前语言 (如「中文（简体）」)；点按打开系统设置中 Vera Bot 页面，其中有「语言」选项 | — (Boss 验收) |
| UI-10 | ~~无「恢复默认头像」~~ | — | 已部分作废 (2026-10-01 改版)：设置账号区仍没有恢复入口；Bot 详情点头像可选「使用默认形象」，见 DETAIL-UI-02 | — |
| UI-11 | 头像正圆 | 首页左上角 (有照片 / 无照片两种)；设置账号区；Bot 列表、对话标题、气泡、Bot 详情、头像预览 | 所有头像都是正圆，不被压扁成椭圆；无照片时用户为品牌色圆底首字，Bot 为颜色圆底表情 (2026-10-01) | — (Boss 验收) |
| UI-12 | 圆形 X 取消 / 关闭 | 首页 ＋ 新建 Bot；长按 Bot「编辑与权限」；对话标题 → Bot 详情；选照片后的头像预览 | 左上角都是系统圆形 X 按钮 (Liquid Glass)，VoiceOver 读「取消」/「关闭」，点按关闭 sheet；清空对话 / 退出登录 / 通知权限弹窗里的「取消」仍是文字 (2026-10-01) | — (Boss 验收) |
| UI-13 | 列表行时间 | 「我的 Bot」列表 | 每行右上角为最后消息时间 (footnote / 次要色)：今天 HH:mm、昨天「昨天」、本周「星期X」、更早 M/d、往年 yyyy/M/d；没有消息的 Bot 显示创建时间。格式另有 `swift test` 单元测试 `listTimestamp*` (2026-10-01) | — (Boss 验收)；单元测试通过 |
| UI-14 | 首页搜索 (按需，当前范围) | 首页（无大导航标题、未搜索）观察右上角与列表；下拉列表；点 🔍 → 输入 Bot 名称 / 最后一条消息预览里的词 → 点圆形 X 取消 | 🔍 与 ＋ 是两个独立的 Liquid Glass 圆形按钮 (🔍 在左)，不合并成一个胶囊；首页不显示大标题或常驻搜索框，下拉也不出现；点 🔍 后才出现系统搜索栏并聚焦；当前只按名称和最后一条消息预览过滤屏幕上已加载的列表；无结果显示系统「无结果」；取消后搜索栏消失、关键词清空、恢复完整列表 (2026-10-01，iPhone 17 / iOS 26 模拟器截图验证)。完整聊天历史搜索、搜索历史等属于后续迭代 | — (Boss 验收) |
| UI-15 | 对话标题胶囊按钮 | 打开任一 Bot 对话页观察导航栏中心标题，并点按标题 | iOS 26 显示原生 Liquid Glass 胶囊按钮（头像 + 名称，无下箭头），iOS 17–18 使用 bordered 胶囊回退；按钮不与返回按钮视觉合并，点按仍打开 Bot 详情且 VoiceOver 标签仍为「查看 Bot 详情」 | —（本次 iPhone 17 / iOS 26 模拟器目视验证） |
| UI-16 | 白底 + 灰分组 | 浅色模式依次打开 设置、调试、用量、提醒、协作记录、新建 Bot、Bot 详情、登录页 | 页面背景纯白；分组 Section / 卡片为浅灰 `#EFEFEE` (RGB 239, 239, 238；2026-10-01 由 `#F2F2F7` 改，见 UI-22)；Bot 详情顶部头像卡片无底色 (2026-10-01) | — (iPhone 17 / iOS 26 模拟器目视：首页、设置、对话、Bot 详情；其余 Boss 验收) |
| UI-17 | 助理列表沉浸式 | 首页「助理」列表 | 白底全宽平铺，无圆角分组、无分隔线；每行头像 + 名称 + 时间 + 预览 + chevron，间距舒适；长按「编辑与权限」、左滑删除仍可用 | — (模拟器目视) |
| UI-18 | 深色模式一致 | 设置 › 外观 选「深色」，再看首页 / 设置 / 对话 / Bot 详情 / 新建 Bot (表情选中) / 提醒；再切回「浅色」「跟随系统」 | 深色：页面黑底、分组深灰 (`secondarySystemBackground`)、表情选中与交接 Trace 为深青底 (`brandSoft` 深色变体)，文字对比度正常；切换立即全局生效 | — (模拟器目视：首页、设置、对话、Bot 详情；其余 Boss 验收) |
| UI-19 | Liquid Glass 按钮 | 登录页「登录」；无 Bot 时「＋ 创建第一个 Bot」；对话标题 | iOS 26：主按钮为品牌色 `.glassProminent`，标题为 `.glass` 胶囊；iOS 17–18 为 borderedProminent / bordered | — (Boss 验收) |
| UI-20 | 浮动玻璃输入栏 | 打开 Vera 对话；滚动消息；点输入框输入「你好」按 return；再输入一段后点 🎙；浅色 / 深色各看一次 | 底部无不透明底栏，消息从输入栏下方滚过，最后一条不被遮挡；左侧独立圆形玻璃 ＋（点开附件占位菜单），右侧胶囊玻璃输入框，占位「向 Vera 提问」，胶囊内尾部 🎙；没有「发送」按钮，return 键为「发送」并发送消息、键盘保持弹出；多行输入时 return 也发送而不换行；粘贴多行文本保留换行；回复进行中按 return 不发送、文字保留；🎙 录音中为红色停止图标并显示玻璃胶囊「正在聆听…」 (2026-10-01) | — (已构建安装；Boss 验收，本轮不做模拟器点测) |
| MSG-01 | Markdown 排版 | 让 Bot 回复含 `# 标题`、**粗体**、*斜体*、`行内代码`、```代码块```、> 引用、- / 1. 列表 (含缩进)、表格、--- 的内容 | 各元素按原生样式显示：标题加粗放大、列表带 • / 序号且缩进、引用左侧青色竖条、代码块与表格为等宽 / 网格且可横向滚动；流式输出中未闭合代码块也正常显示 (2026-10-01) | — (Boss 验收)；解析由 `MessageMarkdownTests` 覆盖 |
| MSG-02 | ~ 不删除线 (BUG-01 回归) | 问天气，看「15~21°C」 | 原样显示 ~，无删除线 | — (Boss 验收)；`inlineKeepsTildeLiteral` 单元测试 |
| MSG-03 | 自动链接 + App 内网页 | 回复中含 https 网址、`[文字](https://…)`、电话、邮箱；依次点按 | 网址 / Markdown 链接全屏打开 App 内 Safari (SFSafariViewController)，「完成」返回对话页且布局正常；电话交给系统拨号、邮箱交给系统邮件；行内代码里的网址不可点 | — (Boss 验收，模拟器无电话) |
| MSG-04 | 长按复制 | 长按含链接的 Bot 气泡 | 菜单有「复制」与每个链接「复制链接 …」，电话 / 邮箱复制时不带 tel: / mailto: | — (Boss 验收) |
| KB-01 | 对话：输入栏随键盘上移 | 关闭硬件键盘 → 点输入框 | 软键盘弹出；输入栏贴在键盘上方 (safeAreaInset，无手动偏移)；最后一条消息与 🔊 可见 | R32_chat_keyboard_up |
| KB-02 | 对话：点空白处收起 | 键盘弹出时点消息区域 | 键盘收起，输入栏回到底部安全区 | R33_chat_keyboard_down |
| KB-03 | 对话：发送后键盘保持 + 自动滚动 | 用软键盘输入 hi → 按键盘 return「发送」(2026-10-01 起无发送按钮，见 UI-20) | 键盘不收起；新消息和回复出现后自动滚到最后一条 (测试消息已删除) | R32b_chat_after_send |
| KB-04 | 对话：交互式收起 | 代码审查：`.scrollDismissesKeyboard(.interactively)` | 下拉消息列表可跟手收起键盘 | — (模拟器鼠标拖动难以复现，未截图) |
| KB-05 | 弹出 sheet 时收起键盘 | 键盘弹出时点标题打开 Bot 详情 | sheet 打开时没有残留键盘 | — (已目视确认) |
| KB-06 | 表单：收起键盘 | Bot 详情 → 点人设输入 → 下拉 / 保存 / 关闭 | 键盘收起 (2026-10-01 改版后昵称改为卡片弹窗编辑，不再有「昵称 → 人设」的 next；新建 Bot 页仍为 next，见 KB-09) | R34_form_keyboard (旧版) |
| KB-07 | 返回时收起键盘 | 对话页点输入框 → 点返回 | 回到 Bot 列表，键盘已收起 | — (已目视确认) |
| KB-08 | 进入后台收起键盘 | 代码审查：scenePhase ≠ active 时 resignFirstResponder | App 切到后台再回来时键盘不残留 | — (未在模拟器中实测) |
| KB-09 | 登录 / 新建 Bot 表单 | 代码审查：同样的 FocusState + 键盘工具栏「完成」按钮 (非 sheet 内的表单保留)；登录页 用户名 → 密码 为 next，密码回车即登录；新建 Bot 的昵称 → 人设 为 next | 与 KB-06 / KB-10 实现相同 | — (本轮未点测，需要退出登录 / 新建 Bot) |
| KB-10 | 人设 / 指令支持多行 | Vera → Bot 详情 → 点人设末尾 → 回车 → 输入 hi → 关闭 (不保存) | 回车键为 ↵，回车插入换行 (「Hi」在第二行)，焦点留在人设不跳转；字段 3~8 行 (`TextField(axis: .vertical).lineLimit(3...8)`)，不使用 submitLabel；关闭时收起键盘；关闭后 Vera 数据不变 (🐼、原人设) | R35_multiline_persona |
| KB-11 | 后端保留换行 | API：PATCH Vera persona=`第一行\n第二行\n\n第四行`、instructions=`A\nB` → GET → 恢复原值 | 读回内容与写入完全一致 (包括空行)；恢复后 Vera 与原来一致 | — (API) |
| KB-12 | Bot 详情 sheet 键盘弹出时关闭，对话页布局正常 (Boss 反馈) | 关闭硬件键盘 → Vera 对话 → 点标题打开 Bot 详情 → 点人设 (软键盘弹出) → 保存；重复 3 次，另测一次「关闭」(2026-10-01 起 sheet 不能下滑关闭)；每次回到对话页后再点输入框 | 回到对话页时内容贴底、没有键盘高度的空白 / 内容被顶起，无需触摸页面；再点输入框时输入栏贴在键盘上方 (不被键盘遮住)；Vera 数据不变 (🐼、原人设/指令)，无测试消息。根因：page sheet 与对话页共享窗口键盘安全区，且 sheet 内 `.keyboard` 工具栏 (inputAccessoryView)「完成」让对话页键盘避让状态错乱 (关闭后留下键盘 inset / 少算工具栏高度)；对话页 keyboardDidShow 不区分输入框。修复：BotEditView 保存 / 关闭 / onDisappear 先 endEditing (清 FocusState + resignFirstResponder)；sheet 内不再使用键盘工具栏；对话页 keyboardDidShow 只在自身输入框聚焦且无 sheet 时滚动；sheet onDismiss 无动画重新贴底 | R36_chat_after_sheet_save |

### 新发现的问题 (New issues)

| ID | 描述 | 状态 |
|---|---|---|
| NEW-01 | `ask_bot` 模糊匹配误路由：「BobBot」被匹配到 Bot「B」 | 已修复 (先精确匹配；模糊匹配要求唯一，且较短名称不少于 2 字) |
| NEW-02 | 422 校验信息带有 pydantic「Value error, 」前缀 | 已修复 (RequestValidationError handler) |
| NEW-03 | `frontend/ios/VeraBot/File.txt` (8 字节，内容「QA回归」，不是本次改动产生的；v0.1.0 重构时随 ios/ 目录原样移动) | 未处理，请确认是否删除 |

### 测试后状态 (Post-test state)

demo 只保留 Vera / 小研 / 阿厨 (权限为迁移后状态)，没有新增消息 / 提醒 / 委派；临时用户 `qa_reg_*` 已删除；`token_budget` 为 NULL；后端运行中；App 已登录 demo，停在 Bot 列表。

## v0.1.0 重构回归 (Restructure regression) — 2026-09-30 18:29–18:45 (UTC+8)

目录重构 (backend 分层 + uv、frontend 拆分 + SPM VeraBotKit) 之后在 Mac 上重跑。结论：**全部通过，行为无变化**。

| 项 | 方法 | 结果 |
|---|---|---|
| 后端启动 | `backend/start.sh --setup-only` → `--detach` (uv sync --frozen) | ✅ `/api/health` → `{"ok":true,"model":"deepseek-chat"}`；`/` 托管 Web |
| OpenAPI 契约 | 重构前后 `/openapi.json` 对比 | ✅ 路径 / 参数 / 模型一致 (仅新增路由 tag) |
| 多 Agent (mock) | `uv run python scripts/test/multi_agent_test.py` | ✅ 24/24 (重构前基线同为 24/24) |
| 冒烟 (真实 LLM) | `scripts/test/smoke_test.py` (已适配迭代 2) | ✅ PASS：22 项通过，2 项 SKIP (未配置 `OPENAI_API_KEY`，转写) |
| 回归 (真实 LLM) | `api_regress.py` + `api_regress2.py` | ✅ 35/35 + 3/3 (修复脚本自身的 TC-13 off-by-one 与崩溃后)，临时用户已删除 |
| SPM 包测试 | `swift test` (VeraBotKit) | ✅ 4/4 |
| iOS 编译 | `xcodebuild … -sdk iphonesimulator build` (Xcode 26.0.1) | ✅ BUILD SUCCEEDED，无新增警告 |
| iOS UI | 重新安装后：Bot 列表 → Vera 对话 (🔊 可见、无 Tab 栏) → 点标题 Bot 详情 → 点人设 (软键盘，无「完成」工具栏) → 保存 → 对话页贴底无空白 (KB-12) → 点输入框 (输入栏在键盘上方) → 返回 (Tab 栏恢复) → 设置 (账号 → 语音 → 关于，无 Tab 栏) → 返回 Bot 列表 | ✅ 全部符合预期 |
| 打包交付 | `scripts/package_backend.sh` → 解压到全新临时目录 → `PORT=8765 ./start.sh --detach` → health / 注册 / 建 Bot → `./stop.sh`；另测 `VERABOT_FORCE_MIRROR=1` (清华 tuna) 安装 | ✅ 两种安装方式均成功；8000 上的 demo 不受影响；临时目录已删除 |
| Docker | `docker compose config --quiet` | 🟡 配置校验通过；daemon 未运行，未构建镜像 |
| demo 数据 | 重构前后 SQLite 对比 | ✅ 完全一致：messages 10 条 (max id 108)、usage_log max id 67、提醒 1、委派 1；Vera 🐼 人设 / 指令不变；只剩 demo 用户 |

## 头像与昵称 (Avatars & nickname) — 2026-10-01

环境：Linux 上的临时 SQLite + FastAPI `TestClient`，不调用 LLM。脚本：`backend/scripts/test/avatar_profile_test.py`。同一轮 `multi_agent_test.py` 仍为 24/24（v1→v3 迁移不破坏权限回填）。iOS 界面本环境没有 Xcode，下表 UI 行标为待 Mac 模拟器验证，步骤见 [RUN_LOCAL.md](../ops/RUN_LOCAL.md)。

| ID | 模块 | 用例 | 预期 | 结果 |
|---|---|---|---|---|
| AV-01 | 迁移 | 已有 schema v2 库启动 | 版本变为 3；出现 `nickname`、`avatar_updated_at`、`image_updated_at`、`avatars`；存量 Bot 的工具权限不被改写 | 通过 |
| AV-02 | 资料 | 注册 | `nickname` 为 null，`display_name` 等于用户名，`has_avatar` 为 false | 通过 |
| NK-01 | 昵称 | `PATCH /api/me` `{"nickname":"  小云  "}` 再 `GET /api/me` | 存成「小云」，用户名不变 | 通过 |
| NK-02 | 昵称 | 改完后重新登录 | 登录响应里仍是「小云」 | 通过 |
| NK-03 | 昵称 | 空白、空串、33 字、含换行、正好 32 字 | 前四项 422（「不能为空」/「最多 32 个字」，无 `Value error` 前缀）；32 字 200 | 通过 |
| NK-04 | 隔离 | 用户 A 改昵称后看用户 B 的 `/api/me` | B 的昵称仍为空 | 通过 |
| AV-03 | 用户头像 | 未上传就 GET | 404「未设置头像」 | 通过 |
| AV-04 | 用户头像 | 不带 Token GET | 401 | 通过 |
| AV-05 | 用户头像 | 上传 800×400 JPEG | 200，`has_avatar` true；GET 为 512×512 JPEG | 通过 |
| AV-06 | 用户头像 | 左右红色、中间绿色的宽图 | 中心像素仍是绿色（居中裁切） | 通过 |
| AV-07 | 用户头像 | 带透明的 PNG、WebP | 都接受，存成 JPEG | 通过 |
| AV-08 | 用户头像 | GIF、损坏的 JPEG、假 HEIC | GIF 415；损坏 400；未装 HEIC 解码器时 415 并提示改用 JPEG/PNG/WebP | 通过 |
| AV-09 | 用户头像 | 超过大小上限 | 413 | 通过 |
| AV-10 | 隔离 | 用户 B `GET /api/me/avatar` | 404，拿不到 A 的字节 | 通过 |
| AV-11 | 用户头像 | DELETE 后再 GET，并看 `/api/me` | `has_avatar` false，GET 404，昵称还在 | 通过 |
| AV-12 | Bot 头像 | 新建 Bot | `has_avatar` false，emoji 仍在，GET 404 | 通过 |
| AV-13 | Bot 头像 | 上传宽图 | 列表 `has_avatar` true，GET 512 JPEG，emoji 仍是原来的 | 通过 |
| AV-14 | 隔离 | 对方对这个 Bot 做 GET/POST/DELETE；自己对对方 Bot 和不存在的 id 做同样的事 | 全部 404，原图还在 | 通过 |
| AV-15 | Bot 头像 | DELETE 照片 | emoji 还在，`has_avatar` false，再 GET 404 | 通过 |
| AV-16 | Bot 头像 | 上传后再删 Bot | `avatars` 里该 Bot 的行没了 | 通过 |
| AV-17 | 用量 | `GET /api/quota` 的 `per_bot` | 每项带 `has_avatar` 和 emoji `avatar` | 通过 |
| UI-AV-01 | iOS | 设置页点头像 → 相册 → 圆形预览 → 使用 | 设置页和首页左上角变成该照片；退出再登录（或另一台设备）仍在 | 待 Mac 模拟器 |
| UI-AV-02 | iOS | ~~设置页「恢复默认头像」~~ | 已作废：2026-10-01 移除该入口，见 UI-10 | 作废 |
| UI-AV-03 | iOS | Bot 详情点头像 →「从相册选择」→ 保存 | 保存前只在卡片预览；保存后列表、对话标题、气泡换成圆形照片 (2026-10-01 改版：入口由按钮改为头像弹窗，见 DETAIL-UI-02) | 待 Mac 模拟器 |
| UI-NK-01 | iOS | 设置页改昵称并保存，回到首页再打开对话 | 首页首字（无照片时）立刻是新昵称，不用下拉刷新；用户消息气泡上方不再显示昵称 | 待 Mac 模拟器 |

汇总：API **21/21 通过**（2026-10-01，Linux）。UI 4 条未在模拟器执行。

## 长期记忆 M1 (Memory) — 2026-10-01

自动化：`backend/scripts/test/memory_test.py` (mock LLM + 临时 DB；用例定义见 [MEMORY_GROWTH.md](../design/MEMORY_GROWTH.md) §10)。iOS：`swift test` (`MemoryTests` 14 个) + 模拟器构建。

| ID | 模块 | 用例 | 结果 |
|---|---|---|---|
| MEM-01 | 迁移 | v3 库 → v4：`memories` 表、`bots.memory_access` (= bot_and_global)、`users.memory_enabled` (= 1)、`messages.memory_ids` 出现；连续执行两次幂等；已有 Bot 的 allowed_tools / delegate_to、头像、昵称不变。`schema_meta.version` 写到当前 `SCHEMA_VERSION`（标签落地后为 5，不再写死 4） | 通过 |
| MEM-02 | 权限 | `get_schemas`：memory_on 且 depth 0 才含 `remember` / `forget_memory`；`memory_access=none`、用户关闭、`VERABOT_MEMORY=0`、depth 1 时都不含；`/api/tools` 不列出记忆工具 | 通过 |
| MEM-03 | 权限 | `PATCH /api/bots/{id}` 把 `remember` 放进 `allowed_tools` → 422；`memory_access` 非法值 → 422；合法值保存并在 `GET` 中返回 | 通过 |
| MEM-04 | 提议 / 确认 | mock LLM 调用 `remember` → 生成 proposed 行 (source=explicit_chat, source_bot_id, source_message_id, expires_at +7d)；trace 含 memory_id；**下一轮 system prompt 不含该内容** | 通过 |
| MEM-05 | 提议 / 确认 | confirm → active, confirmed_at；下一轮 system prompt 含 `[M{id}·全局·资料]`；`done` 事件与 `messages.memory_ids` 含该 id；use_count +1、last_used_at 更新 | 通过 |
| MEM-06 | 提议 / 确认 | 编辑后确认：保存编辑后的正文与新 hash；编辑成敏感内容 → 422 且仍为 proposed | 通过 |
| MEM-07 | 提议 / 确认 | reject → status=rejected、content 为空、hash 保留；30 天内相同 remember → `previously_declined`，无新行；冷却期后可再次提议 | 通过 |
| MEM-08 | 提议 / 确认 | 去重：已有 active 同内容 → `already_known`，无新行；全角 / 空白差异规范化后视为相同 | 通过 |
| MEM-09 | 提议 / 确认 | 更新：`replaces_memory_id` → action=update 提议；confirm 后旧行被物理删除、新行 active；reject 后旧行不变 | 通过 |
| MEM-10 | 提议 / 确认 | `forget_memory` → delete 提议；confirm 删除目标与提议；reject 只删提议；对不可见 / 他人 id → `not_found` | 通过 |
| MEM-11 | 提议 / 确认 | 凭据：「密码是 abc123」「验证码 384920」「sk-xxxx」→ `sensitive_credential`，无行；`audit_log` 有 `memory_blocked` 且 detail 不含原文；服务器日志不含原文 | 通过 |
| MEM-12 | 提议 / 确认 | 证件 / 卡号：有效 18 位身份证、通过 Luhn 的卡号 → 拒绝；不通过 Luhn 的普通数字 (如订单号) → 允许 | 通过 |
| MEM-13 | 提议 / 确认 | 健康 / 财务 → 允许保存，Fernet 加密 (库内只有占位与密文)，API 返回明文且 `sensitive=true`；宗教 / 他人联系方式 / 住址 → `sensitive_category` | 通过 |
| MEM-14 | 提议 / 确认 | 注入特征 (「忽略之前所有指令」「</user_memory>」「调用 ask_bot」) → `blocked_content` | 通过 |
| MEM-15 | 提议 / 确认 | 单轮提议上限 2：第 3 次 → `proposal_cap` | 通过 |
| MEM-16 | 提议 / 确认 | 每用户 active 上限：达到上限后 confirm / POST → 400 `memory_limit`；update / delete 不受限 | 通过 |
| MEM-17 | 提议 / 确认 | 过期：proposed 超过 7 天 → confirm 返回 410 并置 expired、正文清空 | 通过 |
| MEM-18 | 提议 / 确认 | 重复处理：已 active 再 confirm / reject → 409 | 通过 |
| MEM-19 | 隔离 | 租户隔离：用户 B 对 A 的记忆 GET / PATCH / DELETE / confirm / reject → 404；列表与 counts 只含本人；`DELETE /api/memories?scope=all` 只删本人 | 通过 |
| MEM-20 | 召回 | 作用域：Vera 的 bot 记忆不注入小研；global 注入所有 `bot_and_global` 的 Bot；`memory_access=bot` 的 Bot 不注入 global、提议 global 被降为 bot；`none` 无注入 | 通过 |
| MEM-21 | 委派 | 委派：小研 (被委派) 的 `run_once` system prompt 不含 `<user_memory>`，即使小研有自己的 bot 记忆；mock 让小研调用 `remember` → `memory_not_delegable` + `tool_denied` 审计；无新行 | 通过 |
| MEM-22 | 委派 | 委派载荷：调用方把记忆写进 shared_context 时，`delegations.payload` 如实记录；未写时 payload 中无记忆内容 | 通过 |
| MEM-23 | 注入 | 渲染转义：正文含 `<`、`>`、零宽字符、bidi 控制符、换行 → 渲染结果为全角尖括号、单行、无隐藏字符 | 通过 |
| MEM-24 | 召回 | 预算：30 条 active → 注入 ≤ 12 条、正文总字数 ≤ 1000；profile / style 优先；与用户消息关键词重叠的条目排在前面；≤ 12 条时全部注入 | 通过 |
| MEM-25 | 记忆页 / API | 删除 Bot → 其 bot 记忆删除；该 Bot 提议的 global 记忆保留且 source_bot_id 为 NULL | 通过 |
| MEM-26 | 记忆页 / API | 清空对话 (`DELETE /messages`) → 记忆保留，source_message_id 为 NULL；之后对话仍注入记忆；`include_memories=true` → 删除该 Bot 的 bot / summary 记忆，global 保留，返回 `deleted_memories` | 通过 |
| MEM-27 | 记忆页 / API | 清空全部：缺 `confirm=true` → 400；`scope=bot&bot_id=` 只删该 Bot 的 bot 记忆；`scope=all` 删除本人全部 (含 proposed) | 通过 |
| MEM-28 | 记忆页 / API | 记忆页手动添加：POST → active、source=memory_page；策略检查同 MEM-11~14；重复 → 409 返回已有 id；bot_id 为他人 Bot → 404 | 通过 |
| MEM-29 | 记忆页 / API | PATCH：修改正文 / 类型 / 作用域；global → bot 时 bot_id 必填且属于本人；非 active → 409 | 通过 |
| MEM-30 | 记忆页 / API | 用户总开关：关闭 → 不注入、无记忆工具、API 可查看 / 删除；打开后恢复 | 通过 |
| MEM-31 | 审计 | 审计：proposed / confirmed / rejected / created / updated / deleted / cleared / blocked / settings 都有记录，且 detail 中无正文 | 通过 |
| MEM-32 | 兼容 | 回归：MA-01~24、AV-01~17、NK-01~04 通过；旧客户端 (不认识 `memory_ids` / 新字段) 解析 SSE 与 Bot JSON 正常 | 通过 |
| MEM-33 | 加密 | 加密密钥与数据库分离 (`data/.memory_key` 权限 600)；换错密钥解密返回 None (界面显示占位) | 通过 |
| MEM-34 | 加密 | 健康类提议：SSE trace 与存库的 `messages.traces` 不含明文，按 `memory_id` 拉取得到明文 | 通过 |
| MEM-35 | 契约 | `confirm` 接受空 body (带 JSON Content-Type，iOS 无编辑时的请求) 与 `{}` | 通过 |
| MEM-36 | 契约 | 前后端契约：Memory JSON 键 ⊇ iOS `Memory` CodingKeys；列表 / settings / 清空对话响应字段与 iOS 模型一致 | 通过 |
| MEM-UI-01 | iOS Kit | `MemoryTests` 解码 / 未知枚举 / trace 解析 / 旧 Bot JSON 默认值 | 通过 (`swift test` 34/34) |
| MEM-UI-02~12 | iOS | 确认卡片、设置分组、记忆页、编辑页、Bot 详情记忆分组、清空对话两个选项、敏感标记、首次说明 (见 MEMORY_GROWTH §10.2) | 待 Boss 在模拟器 / 真机验收 (模拟器已构建并安装，未做 UI 自动化) |

汇总：MEM **36/36 通过**；回归 MA 24/24、AV/NK 21/21 通过 (2026-10-01)。

## 设置 › 用量 已用百分比 (Usage percent) — 2026-10-01

自动化：`backend/scripts/test/multi_agent_test.py` MA-25 (mock LLM + 临时 DB)；iOS `swift test` (`QuotaTests`)。百分比 = round(`today.total_tokens` / `daily_token_quota` × 100)，只在 iOS 计算，后端字段不变。

| ID | 模块 | 用例 | 预期 | 结果 |
|---|---|---|---|---|
| QUOTA-03 | 契约 (MA-25) | `GET /api/quota` 的键与 iOS 模型对照；与 `db.token_budget` 对照 | 顶层键 ⊇ {model, daily_token_quota, today, total, per_bot, daily, delegations, transcribe}；`today` / `total` ⊇ {requests, prompt_tokens, completion_tokens, total_tokens}；`daily_token_quota` 为整数且 = 预算 > 0；`today.total_tokens` = 今日已用 (拦截用的同一数值) | 通过 |
| QUOTA-04 | iOS Kit | `QuotaTests`：74000 / 200000 → 「已用 37%」；37.5 → 38；0 → 「已用 0%」；200000 → 100；500 / 400 → 125 (不截断)；额度 0 → nil (不显示)；分子用 `today` 而非 `total` | 全部符合 | 通过 (`swift test`) |
| UI-21 | iOS | demo 登录 → 首页头像 → 设置，看「用量」行；点进用量看板再返回；断开后端后重进设置 | 行右侧系统灰色次要文字「已用 N%」，N 与用量看板「今日 Token 额度」的 已用 / 额度 一致 (四舍五入取整)；加载完成前不显示数字；后端不可达时不显示假数字 | 待 Boss 在模拟器验收 (已构建并安装，未做 UI 自动化) |

## 分组灰 #EFEFEE 与缩小开关 (Section grey & compact toggles) — 2026-10-01

纯 iOS 改动，后端未改。`swift test` 38/38、模拟器构建通过。

| ID | 模块 | 用例 | 预期 | 结果 |
|---|---|---|---|---|
| UI-22 | iOS | 浅色模式打开 设置、Bot 详情、对话页、登录页；再切到深色 | 浅色：分组 / 卡片 / Bot 气泡 / 输入框底为 `#EFEFEE` (RGB 239, 239, 238)，页面背景仍为纯白；深色：分组为系统 `secondarySystemBackground`，与改动前一致 | **像素已核对**：`xcrun simctl io booted screenshot` 取模拟器帧缓冲，设置页 (push / TabView 内 push / sheet)、Form 行、纯色块均为 **(239, 239, 238)**，无叠加层、无色彩空间偏差。取色须用 simctl 截图或在设备上截图；在 Mac 屏幕上对 Simulator 窗口取色会经过 macOS 色彩管理，数值偏暗 (例如 Generic RGB 下为 235, 235, 234；外接 DELL 配置文件下为 237, 237, 235)，不是 App 的输出。界面整体待 Boss 验收 |
| UI-23 | iOS | 依次查看 设置 (通知 / 触感反馈 / 语音播放)、设置 › 记忆 (允许 Bot 记住)、Bot 详情 (工具权限、委派目标、接受委派) 的开关并切换 | 开关比系统默认小 (85%)，右对齐，与右边距对齐；行高不变、开关和标题不被裁切；切换手感与动画为系统默认；禁用的委派目标行标题变淡且不可切换；VoiceOver 读作「标题 + 开关」 | 待 Boss 在模拟器验收 (已构建并安装，未做 UI 自动化) |

## Bot 标签 (Tags) — 2026-10-01 (同日重新设计：3 个 / 4 字，见文末汇总)

自动化：`backend/scripts/test/bot_tags_test.py`（临时 DB，不消耗 Token）。iOS 规则在 `VeraBotCore/BotTags.swift`，用例 `BotTagTests`。Linux Swift 6.2 上对 Core 源文件做了类型检查，并用独立程序跑通 `BotTagRules` 与 `Bot` / `BotPatch` / `BotCreate` 的编解码（与 TAG-UI-01 / TAG-UI-02 相同的断言）。完整 `swift test` 未能编译：既有 `MessageMarkdown.swift` 依赖 Apple Foundation 的 Markdown 与 `NSDataDetector`，swift-corelibs-foundation 没有这些 API。

| ID | 模块 | 用例 | 预期 | 结果 |
|---|---|---|---|---|
| TAG-01 | 迁移 | 已有 schema v4 库（含 `memory_access`，无 `tags`）启动两次 | `schema_meta.version = 5`，`bots.tags` 出现且存量行为 `[]`；`allowed_tools` / `delegate_to` / `image_updated_at` / `memory_access` 不变；把标签写成 `["研究"]` 后再跑 `init_db()` 不被清掉 | 通过 |
| TAG-02 | 创建 | `POST /api/bots` 不带 `tags` | 201，响应 `tags: []`，仍是最小权限；`GET /api/bots/{id}` 同样是 `[]` | 通过 |
| TAG-03 | 创建 | `tags: ["  研究 ", "", "研究", "写作", "  ", "写作", "　天气　"]` | 201，顺序为 `["研究", "写作", "天气"]`；列表与详情一致 | 通过 |
| TAG-04 | 更新 | 只 PATCH 名称，省略 `tags` | 200，名称变了，标签不变 | 通过 |
| TAG-05 | 更新 | `tags: []`，再 PATCH `[" 日程 ", "日程", "笔记"]` | 先清空为 `[]`，再变成 `["日程", "笔记"]` | 通过 |
| TAG-06 | 校验 | 3 个标签、恰好 4 字；4 个；5 字；换行；DEL；`tags` 为字符串 / 数字 / null | 前两种 201；其余 422，`detail[0].msg` 依次为「每个 Bot 最多 3 个标签」「每个标签最多 4 个字」「标签不能包含控制字符」「标签必须是列表」「标签必须是文字」「标签必须是列表」；文案不含 `Value error`；失败不写入 | 通过 (重新设计后) |
| TAG-07 | 隔离 | 用户 B PATCH / GET 用户 A 的 Bot，并拉自己的列表 | 404 / 404；A 的标签不变；B 的列表没有这个 Bot | 通过 |
| TAG-08 | 创建 | `tags` 只有空白和重复 | 201，收成一个标签 | 通过 |
| TAG-09 | 存量数据 | 库里直接写入超限标签 `["一二三四五六", "研究", "  ", "一二三四", "写作", "天气", "日程"]`；读取；再跑两次 `init_db()`；带收敛后的标签 PATCH | 读取与库内都变成 `["一二三四", "研究", "写作"]` (截到 4 字、去重、留前 3 个)，幂等；PATCH 200 | 通过 |
| TAG-10 | 契约 | 后端读取 iOS `BotTags.swift` | `maxCount` / `maxLength` = `MAX_BOT_TAGS` / `MAX_TAG_CHARS` = 3 / 4；三条错误文案一致；Bot JSON 含 `tags` 数组 | 通过 |
| TAG-UI-01 | iOS Kit | 旧 Bot JSON 无 `tags` 或 `tags: null` | 解码为 `[]`；有字段时按顺序解码 | 通过 (`swift test` 46/46，Mac) |
| TAG-UI-02 | iOS Kit | `BotTagRules`：trim / 去空 / 去重 / 4 字 / 5 字 / 4 个 / 控制字符；`parse` 支持「,」「，」「、」与空格 (含全角)；`display` 为「a, b, c」且可往返 | 与后端 TAG-03 / TAG-06 一致；`BotPatch` 省略 nil `tags`，显式 `[]` 会编码 | 通过 (`swift test` 46/46，Mac) |
| TAG-UI-03 | iOS | 首页 Bot 行、对话胶囊标题、Bot 详情卡片 | 首页：名称后一个浅灰圆角矩形 (#EFEFEE，圆角 5)，「搜索, 查询, 调研」次要小字，放不下尾部截断，名称优先，无 `+N`，时间不变；对话标题只有头像 + 名称；Bot 详情卡片名称下方一行「搜索, 查询, 调研」；无标签时都不占位 | 待 Boss 在模拟器验收 (已构建并安装，未做 UI 自动化) |
| TAG-UI-04 | iOS | 创建 Bot 的「标签」行；Bot 详情点卡片标签行 | 创建页：一个输入框，占位「如：搜索, 查询, 调研」，输入 4 个或某个 5 字时下方立即出现红色提示，不能提交。Bot 详情 (2026-10-01 改版)：系统弹窗输入，确认后不合法弹出错误、保留原值，见 DETAIL-UI-04 | 待 Boss 在模拟器验收 |

汇总：TAG **10/10 通过** (2026-10-01 重新设计后，Mac)；回归 MA 25/25、AV/NK 21/21、MEM 36/36；`swift test` 46/46；模拟器构建通过。iOS 界面待 Boss 验收。

## Bot 详情 / 创建页改版 (Bot detail redesign) — 2026-10-01

仅 iOS，后端与 API 未改。逻辑在 `VeraBotCore/BotProfileDraft.swift` (`BotProfileDraft`、`PendingBotPhoto`、`BotLook`、`ToolInfo.displayName`) 与 `ListTimestamp.fullLabel`，用例 `BotProfileDraftTests`。界面用例未做 UI 自动化，待 Boss 在模拟器验收。

| ID | 模块 | 用例 | 预期 | 结果 |
|---|---|---|---|---|
| DETAIL-01 | iOS Kit | 草稿初始状态；改昵称 (空白 / 21 字 / 带空格 / 改回原值) | 空白「昵称不能为空」、21 字「昵称最多 20 个字」且保留原值；合法时去首尾空白；改回原值后不算改动 | 通过 (`swift test` 53/53，Mac) |
| DETAIL-02 | iOS Kit | 草稿改标签：4 个、5 字、重复与混合分隔符、空白 | 前两种返回与 `BotTagRules` 相同的错误并保留原值；「搜索，查询 搜索」→ `["搜索","查询"]`；空白 → `[]` (PATCH 清空) | 通过 |
| DETAIL-03 | iOS Kit | 照片待保存状态：无照片时选图再「使用默认形象」；有照片时「使用默认形象」、再选图、再恢复 | 前者撤销为 unchanged；后者依次为 remove (不显示照片、不再提供「使用默认形象」) → replace → remove | 通过 |
| DETAIL-04 | iOS Kit | `BotLook.sameColor`、工具显示名、协作记录时间 | 颜色忽略大小写；`label` 缺失 / 空白 / 等于原始名 →「未命名工具」；`2026-10-01T09:32:00+00:00` 在 Asia/Shanghai 显示「2026/10/1 17:32」 | 通过 |
| DETAIL-UI-01 | iOS | Bot 详情 (对话标题) 与长按「编辑与权限」的分组顺序 | 顶部卡片 → 默认形象 → 人设 → 自定义指令 → 记忆 → 工具权限 → 委派 → 协作记录 → (详情页) 清空对话；没有「基本信息」分组 | 待 Boss 验收 |
| DETAIL-UI-02 | iOS | 点卡片头像 | 系统操作表：「从相册选择」(打开系统相册) 、「取消」；已有照片或待保存照片时多一项「使用默认形象」；选图后卡片立即显示新照片，列表 / 对话不变，直到点「保存」 | 待 Boss 验收 |
| DETAIL-UI-03 | iOS | 点昵称 → 清空 → 确定按钮；输入新昵称 → 确定 → 取消整页 | 输入为空时「确定」不可点；确定后卡片更新；点「取消」/「关闭」后重新打开仍是原昵称 | 待 Boss 验收 |
| DETAIL-UI-04 | iOS | 点标签行 (无标签时灰色「添加标签」) → 输入「一, 二, 三, 四」→ 确定 | 弹出「无法修改」+「每个 Bot 最多 3 个标签」，标签保持原值；输入合法后卡片更新，保存后首页行同步 | 待 Boss 验收 |
| DETAIL-UI-05 | iOS | 有照片的 Bot：「使用默认形象」→ 保存；另测选图 → 取消 | 前者卡片显示表情 + 底色，保存后各处去掉照片 (`DELETE /api/bots/{id}/avatar`)；后者服务端照片不变、没有上传 | 待 Boss 验收 |
| DETAIL-UI-06 | iOS | 默认形象分组：选表情和颜色 → 保存 | 卡片 (无照片时) 即时预览；保存后列表头像底色改变 (PATCH 带 `color`)；页脚「设置了相册照片时，优先显示照片。」 | 待 Boss 验收 |
| DETAIL-UI-07 | iOS | 详情页与创建页的人设 / 自定义指令 | 都是独立分组，标题「人设」「自定义指令」，占位为创建页例句，页脚分别为「对其他 Bot 公开，协作时用来介绍自己。」「仅本 Bot 使用，不对其他 Bot 公开。」；创建页最小权限说明为「新 Bot 默认不开启工具、不参与委派。」 | 待 Boss 验收 |
| DETAIL-UI-08 | iOS | 浏览 Bot 详情、创建页、协作记录 | 无英文：分组「工具权限」「委派」「协作记录」，工具行只有中文名，委派页脚写「委派其他 Bot」；协作记录时间为本机时间、末尾「用量 N」 | 待 Boss 验收 |

| DETAIL-UI-09 | iOS | 打开 Bot 详情 (对话标题)、长按「编辑与权限」、首页 ＋ 创建 Bot，分别在有 / 无改动时向下拖动 sheet | 都不能下滑关闭 (系统 `interactiveDismissDisabled()`，始终开启，无确认弹窗)；只能点「关闭」/「取消」或「保存」/「创建」退出 | 待 Boss 验收 |
汇总：DETAIL-01~04 **通过** (`swift test` 53/53，Mac，2026-10-01)；后端 AV/NK 21/21 回归；模拟器构建、安装、启动通过；DETAIL-UI-01~09 待验收。
