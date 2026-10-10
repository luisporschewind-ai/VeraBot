# 项目状态 (STATUS) — 2026-10-07

## 2026-10-10 · 文件附件实现进行中

- iOS 文件菜单已启用系统文件选择器；后端 schema v19 已增加文件存储、文本抽取和按需读取能力。支持 PDF/TXT/MD/CSV/DOCX/XLSX，10 MB，单消息一个附件。设备/真实模型验收尚未完成；解析器 15 秒硬超时已加入。

## 2026-10-10 · 主线整合待主机测试

- `main` 已纳入头像系统、俄罗斯方块陪玩、记忆成长 M2–M5；数据库迁移版本为 v19（v15 Bot 外观、v16 M3、v17 M4、v18 M5、v19 文件附件）。
- M3/M4/M5 自动化与模拟器构建沿用隔离分支记录；本次整合后尚未重跑。M3/M4 页面与 M5 语义召回、权限共享、反馈提示仍待手工验收。
- M5 的 BGE-small-zh 向量能力为可选本地依赖；未安装或不可用时回退关键词。Web 冻结。
- 当前工作区为本机 `main`，整合后可在主机上启动验收；远程 `origin/main` 尚未同步。

## 2026-10-09 · 俄罗斯方块陪玩首版

- 已实现伙伴选择、在场形象、稀疏主动回应、安静陪伴、暂停聊天与本局回顾。 真实开局与手动局面交流接口已跑通；最终头像点按和聊天面板验收受独立模拟器系统首次启动阻塞，未标为已通过。
- 服务接口专项 4 项通过；Kit 182 项 Swift Testing + 1 项 XCTest 通过。模拟器与真实回应验收见 [验收记录](testing/2026-10-09-tetris-companion.md)；真机待用户验收，未提交或推送本次改动。

## 2026-10-09 · iOS 启动 / 连接 / 登录 / 主题专项

- 补充登录信息记忆：本机钥匙串按服务器保存成功登录的账号／密码，登录页自动填回并可清除；现有会话保持不变。提交快照完整 Kit 测试 175 项通过，iPhone 17 模拟器干净构建并启动成功；完整触控交互待人工验收。

- 用户已授权四项实施与文档同步；新界面复用现有 Bot 等待 / 警告 / 错误动作。
- 已实现本地启动欢迎、首次连接失败默认页与列表保留提示、登录页及右上角调试配置入口。
- 已在 iPhone 17 / iOS 26 模拟器复现：根页面切至深色时，已打开的 sheet 仍为浅色。现改为所属窗口同步外观；无需重建页面。
- Kit 提交快照 **175 项通过**（174 项 Swift Testing + 1 项 XCTest）；原生窗口主题回归 **16/16**（sheet / fullScreenCover / alert / 关闭返回 / 浅深切换 / 两种系统外观）；独立代码审查通过。页面实测和真机状态以 [专项验收记录](testing/2026-10-09-startup-connection-appearance.md) 为准。
- 登录信息记忆已补入本专项；变更已提交至本地 main 供用户验收，尚未推送。其他头像 / 游乐场工作保持独立。

## 当前进度 — MCP M4 OAuth，等待 main 验收

- **实现**：M4 OAuth 2.1 / PKCE 后端桥接、issuer 绑定的加密凭据、令牌刷新 / 撤销、授权状态一次性消费、scope step-up 处理，以及 iOS `ASWebAuthenticationSession` 连接页和 Gmail 目录项已合入 `main`。未实现 Gmail 邮件工具（后续里程碑）。
- **自动验收**：OAuth 假服务器、MCP / 插件回归通过；失败的重新授权不会复用旧 Token，断开后迟到回调会被拒绝；Kit `swift test` 157/157；main 上 iPhone 17 模拟器构建 / 安装 / 启动成功。scope step-up、`invalid_grant` 刷新、并发刷新、跨用户回调仍需专项用例。
- **已有回归注意**：静态 Bearer `connector_test.py` 的旧用例 CONN-03 仍要求未同意时状态为 `connected`，与当前 `needs_consent` 不符；同意后 CONN-03b 为 `ready`。这项断言更新不属于 M4。
- **此前模拟器记录**：隔离测试账号登录、Gmail 目录显示 / 安装、详情页数据用途说明、DeepSeek 数据同意开关默认关闭已实测；真实 Google 登录未启动。
- **待用户手工验收**：真实 Google 登录与取消、授权后重启保持、scope step-up、失效刷新、断开 / 撤销。需要 Google Cloud OAuth 客户端、测试用户和 Workspace Developer Preview；当前环境未配置真实凭据。
- **main 验收环境**：统一使用主仓库后端 `http://127.0.0.1:8000` 和 `backend/data/verabot.db`；iOS 默认地址也是 `8000`。先前功能分支的模拟器记录曾使用隔离后端 `8001` / `/tmp/verabot-m4-sim`，该实例不再作为验收环境。

## v0.1.0 · 原型验证完成 (Prototype validated, feasible)

| 项 | 状态 |
|---|---|
| 结论 | ✅ 原型验证完成，方案可行：多 Bot 私聊 + 多 Agent 协作 (权限 / 隔离 / 护栏 / 审计) + SSE 流式 + 工具调用在 iOS 模拟器 + 本机后端上端到端跑通 |
| 版本 | git tag `v0.1.0`；后端 `verabot 0.1.0`。已发布包为 schema v2；当前代码启动时迁移至 **schema v19**（v3 头像 / 昵称；v4 记忆；v5 标签；v6 置顶；v7 MCP；v8 MCP 同意 / 同步 / 熔断；v9 账号；v10 插件；v11 提醒与通知；v12 图片附件；v13 授权连接器；v14 M2 任务；v15 Bot 外观；v16 M3；v17 M4；v18 M5 向量；v19 文件附件）。iOS `0.1.0 (1)` |
| 测试 | v0.1.0 原始回归快照：**91 条用例：通过 90 / 失败 0 / 跳过 1** (当时 TC-31 按要求跳过)，见 [TEST_CASES_v0.1.md](testing/TEST_CASES_v0.1.md)；2026-10-01 后续手工验收结果见该文档「后续手工验收」。之后新增：AV / NK 21/21 (API)、MEM 36/36 (记忆，mock)、MA 25/25 (含 MA-25 用量契约)、TAG 8/8 (Bot 标签)；UI 剩余验收已列为延期项。|
| 交付 | 后端 `dist/VeraBot-backend-v0.1.0.zip` (一键启动)；iOS Xcode 工程 + SPM 本地包；见 [DELIVERY.md](ops/DELIVERY.md) |
| 运行环境 | macOS Intel (MacBook Pro 13" 2018)、Xcode 26.0.1、iPhone 17 模拟器 (iOS 26)、Python 3.12 (uv)、DeepSeek `deepseek-flash` (思考模式关闭；2026-10-03 前为 `deepseek-chat`) |

## 🔁 当前交接 (Handoff) — 2026-10-07 UTC+8

- **主线快照**：`main` 比 `origin/main` 超前 4 个本地提交，HEAD `17a71ee`（M4 OAuth 功能提交、合并提交、文档更新及 OAuth 流程失效修复）；远端仍在 PR #30 的 `61b9b4f`。未发布版本；数据库 schema **v14**（v12 图片附件、v13 授权连接器、v14 记忆 M2），iOS 版本仍为 `0.1.0 (1)`。
- **开放 PR**：当前没有开放 PR。MCP M3 已由 PR #30 合入主线；图片附件 P1 的 PR #14、授权连接器 PR #24、记忆 M2 PR #28 和提醒编辑页修复 PR #27 也已合入。
- **本地分支**：`feat/attachments-p1`、`cursor/camera-capture`、`cursor/mcp-auth-p1`、`feat/memory-m2`、`fix/notif-main-actor-speech-cleanup` 仍有本地引用，但对应改动已合入主线；这些引用不是开放 PR。其他本地工作区 / worktree 的状态以 `git worktree list` 为准，清理前需确认其中没有待保留工作。
- **图片 / 拍照验收**：Boss 于 2026-10-07 确认图片附件与拍照验收通过；同日 ATT-LIVE-01 在临时隔离库用真实 `deepseek-flash` 请求通过，200 返回、识别测试图中的蓝色与红色图形，caption 已持久化。详见 [TEST_CASES_v0.1.md](testing/TEST_CASES_v0.1.md) ATT-UI、ATT-CAM 与 ATT-LIVE-01。
- **其他手工验收**：Boss 于 2026-10-07 确认提醒编辑页视觉修复、头像实验室观感、回复加载状态均通过。对应记录见 REM-UI-02、AVLAB-01/02、MSG-05。
- **首页搜索与弹层统一**：Boss 于 2026-10-07 确认搜索 sheet，以及新建页 / 设置页弹层统一验收通过。对应记录见 [TEST_CASES_v0.1.md](testing/TEST_CASES_v0.1.md) UI-14、UI-24。
- **记忆 M2（schema v14）**：滚动摘要 + 风格校准已合入主线（PR #28；见 [MEMORY_GROWTH.md](design/MEMORY_GROWTH.md) §11.1 / §20）。`memory_m2_test.py` 覆盖 MEM-40~49。Web 无 👍 / 👎 与摘要界面（冻结）。
- **MCP M3（PR #30）**：通用 HITL 确认卡片已合入；M3 后端用例 23/23、MCP / 插件 / 并发回归通过，Kit `swift test` 156/156。连接的 iPhone 12 Pro Max 目标构建通过；尚未安装 / 启动，确认卡片的真机手工验收待 Boss 在 Xcode 运行后完成。过期确认已修为原子检查并拒绝。
- **提醒编辑页本地改动**：保留了未提交的提醒编辑逻辑修复；修复 `VeraBotCore` 日期工具可见性及 Swift 6.2 的 `Binding` setter 编译崩溃后，iPhone 目标构建通过。提醒保存 / 删除 / 时区等交互尚待 Boss 在 Xcode 运行并手工验收。原提醒编辑页视觉修复已于 2026-10-07 验收通过。
- **本地改动须保留**：个人签名与本地化配置均保持在工作区，不覆盖或提交。

## 🔁 历史交接记录 — 2026-10-05 UTC+8

- **MCP M3（HITL，不升 schema；10-05 设计快照）**：写工具走 `pending_actions` + 确认卡片（见 [MCP_CAPABILITY.md](design/MCP_CAPABILITY.md) §7 / §18.5）。原计划的自动化与交互验收状态已在当前交接更新；PR #30 于 2026-10-07 合入。OAuth、变更审阅、Gmail 仍未做。**Web 冻结**。
- **记忆 M2（schema v14）**：滚动摘要 + 风格校准已实现（见 [MEMORY_GROWTH.md](design/MEMORY_GROWTH.md) §11.1 / §20）。`memory_m2_test.py` 覆盖 MEM-40~49。清空对话会删摘要、保留已确认记忆。**Web 落后**：没有 👍 / 👎 和摘要界面（冻结）。iOS 未在云端 `xcodebuild`。

## 🔁 更早的交接记录 — 2026-10-03 UTC+8

- **HEAD**：功能与文档均已提交并推送 (置顶 `c5529ce`、首页头像正圆 `3504fef`、App 图标亮 / 暗色 `832cdb0`，及本次文档对齐)，分支 `main`，仓库 `/Users/admin/Desktop/VeraBot-v0.1` (Mac)，origin `github.com/luisporschewind-ai/VeraBot`。
- **不要提交的本地改动**：`frontend/ios/VeraBot.xcodeproj/project.pbxproj` (`DEVELOPMENT_TEAM = 4M4EACBGAJ`，Boss 签名) 与 `frontend/ios/VeraBot/InfoPlist.xcstrings`。只 `git add` 自己的文件。不动 tag `v0.1.0`。
- **规则**：前后端同步 (字段 / 文案 / 上限改动要有契约测试并写对照表)；Web 冻结 (只在 STATUS 记落后项)；iOS 只用原生默认样式、无自定义动画、Theme 语义色、头像正圆 (照片或表情 + 底色)；代码、测试、文档 (CHANGELOG / FEATURES / TEST_CASES / STATUS) 同一提交；作者 `Luis <luisporschewind@gmail.com>`；不做 UI 自动化 / 点按 / 截图；只装 **iPhone 17 模拟器** (UDID `6FD1E62D-DA65-42B1-81F5-554042006671`)，不装真机；不用 Homebrew。
- **构建 / 测试**：`frontend/ios`：`xcodebuild -project VeraBot.xcodeproj -scheme VeraBot -sdk iphonesimulator -destination "id=<UDID>" -derivedDataPath /tmp/verabot_dd build`；Kit `swift test` (当前 112 条)；后端确定性用例 (在 `backend/`)：`uv run python scripts/test/{cache_headers_test,auth_test,avatar_profile_test,bot_pin_test,bot_tags_test,memory_test,multi_agent_test,status_event_test,mcp_test,plugin_test}.py`。
- **后端启动**：`backend/stop.sh` 后 `backend/start.sh --detach` (默认 `0.0.0.0:8000`，日志 `data/server.log`)；健康检查 `curl http://192.168.0.104:8000/api/health`；demo / verabot2026。
- **近期更新 (2026-10-03)**：首页置顶改为乐观更新 + 系统 List 行移动动画，置顶图标改为品牌色实心 pin；首页头像左边距与右侧按钮一致；设置页昵称改为点按弹窗修改；登录页用 App 图标并显示清楚的登录中状态；新增账号体系改造方案 [AUTH_REFACTOR.md](design/AUTH_REFACTOR.md) (已定稿 v1.0 并实现，见下方「账号 v9」)。
- **近期更新**：Bot 置顶已实现 (schema v6；见 [BOT_PIN.md](design/BOT_PIN.md))，本机数据库迁移前备份 `backend/data/verabot.db.bak-before-v6`。
- **验收记录 (2026-10-01)**：Boss 确认 Bot 置顶功能无问题；TC-07 无效 token 返回 401 后自动回登录页；TC-29/30、设置、首页与导航、主要列表、消息、头像/昵称，以及触感反馈、语音、键盘相关验收通过。余下详情/创建页、长期记忆、用量、标签细节、删除流程及部分视觉页验收由 Boss 同意延期，不阻塞当前任务。详见测试用例记录。
- **2026-10-03**：首页左上角头像外的 iOS 26 玻璃胶囊底已关掉 (`.sharedBackgroundVisibility(.hidden)`)，头像 44pt 正圆，与右侧按钮等大；Boss 已验收 (UI-11b)。
- **2026-10-03**：iOS 界面残留英文 tokens 已改为「用量」(委派 Trace 行、用量看板、额度用完提示)；待 Boss 验收 (UI-EN-01)。
- **2026-10-03**：VeraBotCore 新增执行状态机 `ExecutionStateMachine` (8 种状态，由现有 SSE 事件推导，`ChatViewModel` 只读暴露，界面未改，后端未改)；`swift test` 74/74 (EXEC-01~19)。
- **2026-10-03**：执行状态机 v1.1：后端新增 SSE `status` 事件 (`recalling` / 委派内部 `thinking` / `tool`，`{phase, depth, bot_name, tool, parent_id}`)，`status_event_test.py` 8/8 (含契约)；Core 新增 `recalling`、`delegating.progress`、短暂受阻 `blocked` (1.2 s 自动回到原流程)；头像实验室新增「回复中」「委派中」、持续状态可见时循环、按状态机演示。`swift test` 88/88；回归 MA 25/25、MEM 36/36、AV/NK 21/21、TAG 10/10、PIN 8/8。**Web 落后**：不处理 `status` 事件 (冻结，忽略即可，无报错)。
- **2026-10-03**：头像实验室测试与修复：iPhone 17 模拟器截图 / 录屏 (浅色 + 深色、演示一轮、减弱动态效果、退到后台再回来) + 新离屏检查 `frontend/ios/Tools/AvatarLabHarness/run.sh` (Mac，约 2.5 分钟，AVLAB-T01~T13 13/13，输出浅色 / 深色 × 68 / 104 / 148 的对照图到 `/tmp/avatarlab_harness`)。修复：深色模式状态角标几乎看不清；角标挡住 V豆 顶部圆点、星点星光 (移到右下角)；演示「停止 → 再开始」可能两轮叠加 (运行令牌)；角色色改为 Theme 语义色 (支持深色)；文档里演示顺序漏了中间的「思考中」。持续状态循环、离开 / 回来、减弱动态效果静止：模拟器复测正常。Boss 于 2026-10-07 确认头像实验室观感通过。
- **2026-10-03**：头像实验室的五款形象成为默认 Bot 头像（无相册照片时）：首页列表静态，对话页导航栏按执行状态机动画，Bot 详情 / 创建页可选择并写入已有 `avatar` 字段。照片优先。`completed` 1.5 s 后回空闲。修了三处遗留：68pt 角标符号过小；预览滚出屏幕后循环不停；`reset` 不取消受阻计时。后端无新字段。**Web 落后**：不画这五款形象，形象 id 会当文字显示（冻结）。iOS 模拟器未在本环境编译。
- **MCP M1（schema v7）**：已实现。默认服务 Microsoft Learn（开启），备用 AWS Knowledge（默认关闭）。Web 冻结，没有 MCP 界面。
- **2026-10-03**：MCP M1 (PR #4) 合并评审：合并 main 的 status 事件、修复 MCP 长结果被截断导致结束标记丢失、设置页加 DeepSeek 数据说明、补 Kit 测试；Mac 实测 Learn / AWS 可用 (约 2.4–2.9 s / 次)。
- **MCP M2（schema v8）**：已实现产品确认的五项：按服务记录 D4 同意时间（可撤回，未同意不调用）、复用 `Mcp-Session-Id`（404 重新握手并再试一次）、每次调用写审计且不存外部原文、`GET /api/mcp/servers` 改为后台同步并返回 `sync_status`、可重试错误的退避重试和按服务熔断。设置页显示同意时间、同步状态和熔断。OAuth、变更审阅仍未做；**确认卡片已由 M3 落地**。`frontend/web` 冻结。iOS 工程在 Linux 上未编译。
- **2026-10-03**：PR #4 已合并到 main (`7d93a00`)；本机数据库已迁移到 v7 (迁移前备份 `backend/data/verabot.db.bak-before-v7-20261003-132234`)；「研究助手」已开启 Learn 3 个只读工具用于验收。合并后修复：对话里 MCP Trace 不再铺出外部原文、工具名显示中文。待 Boss 验收：设置 › MCP 服务、Bot 详情「MCP 服务」、对话里查微软文档 (MCP-UI-01)。
- **2026-10-05**：修复 MCP 内嵌资源（`type: resource`）正文没进模型输入的问题（GitHub 读 README 只剩 SHA）；文本 blob 解码，二进制只注明大小。
- **2026-10-05**：修复提醒编辑页「日期」「时间」重复两行（PR #27）：两个 `DatePicker` 改用 `.labelsHidden()`（显式 `accessibilityLabel` 保留字段名），开关改用 `CompactToggle`。Boss 于 2026-10-07 确认视觉修复通过。同轮代码审查发现的保存语义、版本冲突、删除确认等旧缺陷仍见「已知遗留」。
- **账号 v9 (AUTH-M1，2026-10-03)**：邮箱 + 密码、邮箱 + 验证码、手机号 + 密码登录；刷新令牌 (访问 7 天 / 刷新 60 天，iOS 透明刷新，Keychain)；登录限流与锁定；发信 console / SMTP 可插拔 (Gmail 应用专用密码未配置，验证码目前在 `backend/data/server.log`)。本机库已迁到 v9，迁移前备份 `backend/data/verabot.db.bak-before-v9-20261003-154936`。`auth_test.py` 现为 18/18 (含邮箱认领)。**Web 落后**：Web 登录页仍是用户名 + 密码，没有刷新令牌 (7 天后要重新登录)、没有邮箱 / 手机号 / 验证码登录和邮箱验证 (冻结；旧接口兼容，不报错)。见 [AUTH_REFACTOR.md](design/AUTH_REFACTOR.md)。
- **邮箱认领 (2026-10-03)**：验证码登录认领未验证邮箱时，同一事务清空密码 (`password_hash=''`)、`token_version + 1`、吊销全部刷新令牌并写审计 `account_claimed_by_email_code`，再发新令牌。已验证邮箱的验证码登录不变。API 字段未改，iOS 未改，schema 仍是 v9。**仍在**：手机号抢注 (没有短信验证，见 [AUTH_REFACTOR.md](design/AUTH_REFACTOR.md) §5.2)。
- **账号隔离 · HTTP 缓存 (2026-10-03)**：审计结论服务端隔离完好 (136 次跨账号请求全部 404 / 422)；修复设备侧两处：后端所有 `/api/*` 带 `Cache-Control: no-store` (头像 `private, no-store`)，iOS API 改走无缓存的 `APITransport.session`，退出 / 登录 / 升级后首次启动清 `Cache.db`；异步资料 / 头像结果按登录会话代号丢弃。`cache_headers_test.py` 8/8、Kit `swift test` 112/112；模拟器验证换账号后 Cache.db 无 API 响应。**Boss 于 2026-10-04 验收通过。**邮箱抢注已另修 (见上一条)。**Web 落后**：Web 端自己不缓存 API，后端头对它同样生效，无需改。
- **主题色 (2026-10-03)**：iOS 改为「薰衣草 × 青绿」(Boss 选定试色方案 C，替换上午的纯青绿主题 `502e11e`)：品牌主色浅色 `#6461D1` / 深色 `#D7D7FF`，用户气泡 `#D7D7FF` / `#3F3D9E`，主按钮 `#6461D1` / `#4B48B8`，开关与置顶用青绿 `#3D7A8C` / `#4E9AAE`、`#5FA3B6`。只改 Theme 语义色、AccentColor 和用户气泡，见 [ARCHITECTURE.md](design/ARCHITECTURE.md) 色板。**Web 落后**：仍是旧的 `#0F766E` (冻结)。
- **插件 P1（schema v10，2026-10-03）**：设置「MCP 服务」改为「插件」。页内两组「内置」（天气、提醒，不可卸载、无需同意）和「外部」（已安装的 Microsoft Learn / AWS Knowledge）。新账号不预装外部插件。用过的老数据迁成已安装（演示账号已同意的 Learn 仍在）；没用过的不写卸载墓碑。卸载会清同意并从所有 Bot 去掉工具，iOS 先确认。设计 [PLUGIN_DESIGN.md](design/PLUGIN_DESIGN.md) v1.0。本机升级前备份 `backend/data/verabot.db.bak-before-v10-<时间戳>`。`plugin_test.py` 通过。iOS 未在本环境编译。**Web 落后：插件 P1 没有 Web 对应**（`frontend/web` 冻结；`/api/mcp/*` 仍可用，`/api/tools` 多了可忽略的 `plugin_id`）。
- **提醒与推送 R1（schema v11，2026-10-03）**：设计 [REMINDER_PUSH_DESIGN.md](design/REMINDER_PUSH_DESIGN.md) v1.0。提醒状态机、30 秒调度与睡眠补跑、CRUD、三个 Bot 工具、收件箱、通知偏好、iOS 本地通知。SQL 在 `db/reminder_store.py`。APNs 不做。升级前备份 `backend/data/verabot.db.bak-before-v11-<时间戳>`。`reminder_test.py`、`notify_test.py` 用假时钟、不访问外网。合并复核（Boss 的 Mac）修了 Swift 6 并发编译错误和两处 Kit 测试，`swift test` 140 通过、`xcodebuild` 成功；模拟器验证了提醒 / 通知分段、设置 › 通知、本地通知按时弹出及「完成」「稍后 10 分钟」、免打扰不影响提醒。之后发现复核时的并发修复让通知代理在非主线程回调 completionHandler，点通知后切后台会崩溃，已改为在主线程回调（修复 PR 见 CHANGELOG）。APNs 和真机未验证。**Web 冻结**：没有新的提醒界面；`POST /api/reminders/{id}/done` 和列表里的 `content` / `done` / `bot_name` / `due_at` 仍可用。
- **模型 P0 (2026-10-03)**：后端默认模型 `deepseek-chat` (官方已停用的旧名) → `deepseek-flash`，请求体固定 `thinking: {"type":"disabled"}` (`VERABOT_DEEPSEEK_THINKING=0`)。`.env` 未覆盖模型、未改；`/api/health` 现为 `deepseek-flash`。`llm_body_test.py` 5/5；模拟器普通对话与工具调用 (天气 + Learn) 正常。
- **图片附件 P1（schema v12）**：按已批准的 [ATTACHMENTS_DESIGN.md](design/ATTACHMENTS_DESIGN.md) 与 [ATTACHMENT_STORAGE_RESEARCH.md](design/ATTACHMENT_STORAGE_RESEARCH.md) 完成并合入主线（PR #14）；图片与拍照验收于 2026-10-07 通过。实现边界与 ATT-LIVE-01 实测记录见下方功能表与测试记录。
- **需授权 MCP 连接器 P1（schema v13）**：GitHub / Linear 只读连接器已通过 PR #24 合入主线。真实冒烟 CONN-LIVE-01~06 仍待令牌与测试仓库；Web 无连接器界面（冻结）。
- **修复回复开头黑色竖条**：已通过 PR #23 合入主线；生成中等待首个 token 时显示系统 `ProgressView`。Boss 于 2026-10-07 确认回复加载状态通过。
- **图片附件 P2 拍照**：系统相机 `UIImagePickerController` 已在主线（commit `601ca39`）；图片与拍照验收于 2026-10-07 通过，详情见 ATT-CAM-01~03。
- **图片附件 P1（schema v12）**：已通过 PR #14 合入主线，数据库迁移为 v11 → v12；附件目录 `backend/data/attachments/` 与数据库需一起备份（FileVault 需在 Mac 上确认已开启）。`attachments_test.py` 28/28。Boss 于 2026-10-07 确认图片附件和拍照验收通过；ATT-LIVE-01 同日真实 `deepseek-flash` 带图请求通过（临时隔离库，caption 持久化）。限制：带图轮次写操作用文字「确认」代替确认卡片；Web 冻结，不能发送或查看图片。
- **待办**：
  1. **执行状态机**：v1.1 已接到对话页导航栏头像（见 [EXECUTION_STATE.md](design/EXECUTION_STATE.md)）。首页列表只显示静态形象。`completed` 后 1.5 s 回空闲。先前三处遗留已修：68pt 角标符号、滚出屏幕后循环不停、`reset` 取消受阻计时。
  2. **头像动画**：采用头像实验室的五款形象和系统 `phaseAnimator`，不采用另一套自定义卡通动画。有相册照片时仍显示照片。
  3. **仓库清理记录**：`frontend/ios/VeraBot/File.txt` (QA 遗留，内容「QA回归」) 已在 `c5529ce` 删除，工作区无残留 (见 TEST_CASES NEW-03)。

## 📍 当前进度 (Current progress) — main 工作区 (2026-10-07)

v0.1.0 之后的已合并改动都在 `main`，尚未发版 (见 [CHANGELOG.md](CHANGELOG.md) [Unreleased])。`main` 与 `origin/main` 当前同为 `61b9b4f`；数据库迁移已到 **schema v14**：v3 头像 / 昵称、v4 记忆 M1、v5 标签、v6 置顶、v7 MCP、v8 MCP 同意 / 同步 / 熔断、v9 账号、v10 插件、v11 提醒与通知、v12 图片附件、v13 授权连接器、v14 记忆 M2。iOS 版本仍为 `0.1.0 (1)`。当前没有开放 PR；PR #30 的 MCP M3 已合入。M3 后端 23/23、MCP / 插件 / 并发回归通过、Kit `swift test` 156/156，iPhone 12 Pro Max 目标构建通过；设备启动和确认卡片手工验收待 Boss 在 Xcode 完成。提醒编辑逻辑修复与 Xcode 编译修复保留在本地未提交；其他未提交改动也保持原样。

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
| **MCP M1** (schema v7；Learn 默认开、AWS 默认关；Bot / 设置里按服务开关只读工具) | 见 CHANGELOG | 后端 `mcp_test.py` 本地假服务器通过；真实公网用例默认跳过。iOS 未在本环境编译。Web 无界面 | MCP-01、MCP-02、MCP-04~08、MCP-25、MCP-CONTRACT、MCP-HTTP、MCP-LIVE |
| **MCP M3 HITL** (写工具确认卡片；复用 v7 `pending_actions`) | PR #30，合并提交 `61b9b4f` | `mcp_m3_test.py` 23/23；MCP / 插件 / 并发回归通过；Kit `swift test` 156/156；iPhone 12 Pro Max 目标构建通过；真机交互验收待 Boss | MCP-10~13、M3-UI |
| **MCP M4 OAuth 2.1 + Google**（不升 schema） | 合并提交 `ed52159` | OAuth 假服务器与 MCP / 插件回归通过；Kit `swift test` 157/157；main 验收地址为 `127.0.0.1:8000` | MCP-20~21、刷新 / 撤销子集；真实 Google OAuth 待手工验收 |
| **MCP M2** (schema v8；按服务同意、会话复用、审计、后台同步、重试与熔断) | 见 CHANGELOG | 后端 `mcp_test.py` 本地假服务器通过（含 v7→v8）；真实公网用例默认跳过。iOS 未在本环境编译。Web 冻结，无对应界面 | MCP-CONSENT、MCP-SESSION、MCP-AUDIT、MCP-SYNC、MCP-RETRY、MCP-BREAKER、MCP-CONTRACT |
| **Bot 详情 / 创建页改版** (顶部卡片弹窗编辑头像 / 昵称 / 标签且「保存」才提交、「默认形象」分组、人设 / 指令独立分组、界面去英文、协作记录本地时间；仅 iOS) | 见 CHANGELOG | `swift test` 53/53；AV/NK 21/21；模拟器已构建 / 安装 / 启动；详情/创建 UI 验收延期 | DETAIL-UI-01~09 |
| **头像实验室** (独立页面；五款角色、八种状态、三种尺寸、按状态机演示；不写入 Bot 资料) | `7ebe99d`、`a29536f` 及之后 | 离屏检查 13/13；模拟器截图 / 录屏通过 (浅色 / 深色、演示、减弱动态效果)；Boss 于 2026-10-07 确认观感通过 | AVLAB-01、AVLAB-02、AVLAB-T01~T14 |
| **默认 Bot 形象** (实验室五款；照片优先；对话导航栏按 10 个执行状态动画，完成后 1.5 s 回空闲；首页 / 详情静态) | 见 CHANGELOG | 后端 AV-18。Kit 用例 EXEC-34~40 已加。iOS 模拟器未在本环境编译 | AV-18、EXEC-34~40、AVFIG-UI |
| **图片附件 P1 + 拍照 P2** (schema v12；PhotosPicker / 系统相机、磁盘存储 + SQLite 元数据、GIF、按需召回、委派带图、带图写操作需确认) | 主线已合入（附件 PR #14；拍照 commit `601ca39`） | Boss 于 2026-10-07 确认图片附件及拍照验收通过；后端附件用例 28/28，ATT-LIVE-01 真实 `deepseek-flash` 带图请求与 caption 持久化均通过 | ATT-01~18、ISO-ATT-01、ATT-CONTRACT、ATT-UI-01~04、ATT-CAM-01~03、ATT-LIVE-01 |
| App 图标、主屏显示名「Vera Bot」 | `b5eccd9`、`d824796` | 已构建 | — |
| 去掉列表数量页脚、账号信息并入设置、移除「恢复默认头像」入口 | `8794552` 等 | 对应 UI 验收延期 | UI-01~03、UI-10 |

### 暂停 / 延期 (Paused / deferred)

| 项 | 状态 |
|---|---|
| MCP M5~M7、Gmail 邮件工具 | OAuth 连接已实现；邮件工具、变更审阅、自定义 URL / stdio 仍按设计稿待做 |
| 以记忆为核心的 Bot 成长体系 M2~M5 (摘要、风格校准、隐式候选、成长界面、向量检索) | M2–M5 已合入本地 main；M3/M4 页面及 M5 真实语义与协作体验待手工验收 |
| 首页搜索扩展 (完整聊天历史搜索、搜索历史) | ⏸ 延期到后续迭代；当前只过滤已加载列表 |

### 已知遗留 (Known leftovers)

- **提醒编辑页旧缺陷**（2026-10-05 代码审查发现；本地实现已更新，iPhone 目标构建通过，尚未安装运行 / 手工验收）：修正了仅改标题仍回传旧排程、使用 snooze 时间、冲突重载不刷新版本、删除缺确认 / 吞错误、时间格式和原时区、日期 / 时间状态混用、关闭日期未清全天字段、重复出现时覆盖编辑态、打开日期后时间过期、备注清空、无日期开启日期默认全天，以及自定义 RRULE 丢失等路径；行内标签改为按钮。逐项验收仍待进行，尤其 DST、跨时区与点击命中区域。
- **相对时间解析**（实现已更新，尚未验证）：创建提醒时，对用户原话中可解析的中文秒 / 分 / 小时 / 天相对时间按服务器时钟重算并向上取整到分钟；范围仅覆盖明确数字或中文数词加「后」的表达。
- **改进建议：点按提醒通知先进只读详情页**：现在点按提醒通知直接进「编辑提醒」。建议改为先看详情 (标题、时间、来源、「查看对话」)，再从详情进编辑。路由规则不变 (仍不直接进对话，见 [REMINDER_PUSH_DESIGN.md](design/REMINDER_PUSH_DESIGN.md) §9.5)。
- **Web 客户端落后于 iOS**：没有迭代 2 的 iOS UI，也没有 2026-10-01 之后的全部 iOS 改动 (见 §2 第一条)。**默认 Bot 形象没有 Web 对应** (Web 冻结)：iOS 无照片时画五款实验室形象，`bots.avatar` 可能是 `veraBean` 等 id；Web 仍把该字段当文字 / 表情显示，不播状态动画。`/api` 未新增字段。**设置 › 用量「已用 N%」没有 Web 对应** (Web 冻结；Web 用量页仍是原有额度进度条，`/api/quota` 未变，不受影响)。**Bot 标签与置顶没有 Web UI** (Web 冻结；后端字段向后兼容)。**Bot 详情改版 (卡片弹窗编辑、默认形象分组、去英文、协作记录本地时间) 没有 Web 对应** (Web 冻结；未改 API)。**记忆 M1 没有 Web UI**：Web 不显示确认卡片 (记忆工具结果显示为普通工具卡片，无法在 Web 确认)，没有记忆页与 `memory_access` 设置；后端接口向后兼容，Web 现有功能不受影响。**MCP M1 / M2 没有 Web UI**（`frontend/web` 冻结，落后于这项功能）：没有服务列表、同意开关、同步状态、熔断状态或工具开关。`/api/mcp/servers` 多了 `consent_at` / `sync_status` / `circuit_state` 等字段，`/api/tools` 的可选字段仍可忽略。对话若模型调用了 MCP 工具，Web 仍只显示普通工具卡片。**插件 P1 没有 Web 对应**（`frontend/web` 冻结）：没有插件页。`/api/plugins/*` 是新接口；`/api/tools` 增加可忽略的 `plugin_id`；`GET /api/mcp/servers` 不再自动补未安装的目录行。
- **设计稿中的 schema 版本号**：v3 = 头像 / 昵称、v4 = 记忆、**v5 = Bot 标签**、**v6 = Bot 置顶**、MCP 表是 **v7**，M2 的同意 / 同步 / 熔断列是 **v8**，账号邮箱 / 手机号是 **v9**，插件安装表是 **v10**。Gmail 设计稿仍写与 MCP 共用 v7 表。

## MCP M1 已实现；M2 起与 Gmail 仍待做

Boss 决定把 MCP (Model Context Protocol) 作为 VeraBot 的一等能力，Gmail 优先通过 MCP 接入。两份设计稿已于 2026-10-01 由 Boss 批准为 **v1.0**。以记忆为核心的 Bot 成长体系方案 v1.0 已批准，记忆 M1 已实现。

| 能力 | 设计文档 | 状态 | 需要 Boss 做的事 |
|---|---|---|---|
| MCP M1（Client、目录、只读工具开关、防注入） | [MCP_CAPABILITY.md](design/MCP_CAPABILITY.md) §18 | ✅ 已实现（schema v7） | 验收设置页与 Bot 详情的 MCP 开关。真实公网用例需 `VERABOT_MCP_LIVE_TESTS=1` |
| MCP M2（同意时间、会话复用、审计、后台同步、重试与熔断） | 同上 §18.3 | ✅ 已实现（schema v8） | 验收设置页的同意 / 同步 / 熔断。`frontend/web` 冻结，没有对应界面 |
| MCP M3（pending_actions、写操作确认卡片、工具调用记录） | 同上 §7 / §15 / §18.5 | ✅ 已实现并由 PR #30 合入 `main`（复用 v7 表，不升版本） | `mcp_m3_test.py` 23/23；Kit 156 项；iPhone 目标构建通过；真机卡片交互待 Boss 验收 |
| 插件 P1（安装关系、内置 / 外部入口、卸载） | [PLUGIN_DESIGN.md](design/PLUGIN_DESIGN.md) v1.0；进度见 MCP §18.4 | ✅ 已实现（schema v10） | 新账号不预装。验收设置 › 插件、内置详情的工具权限导航、卸载确认。`frontend/web` 冻结，插件 P1 没有 Web 对应 |
| MCP M4（OAuth 2.1 + Google 连接） | 同上 §15 / §18.6 | ✅ 已合入 `main`，不升 schema | 真实授权需 Google Cloud OAuth 客户端、测试用户与 Workspace Developer Preview；由 Boss 手工完成 |
| MCP M5~M7（Gmail 工具、变更审阅、自定义 URL / stdio） | 同上 §15 | 未实现 | 按设计稿后续推进 |
| Gmail (主路径：Google 官方 Gmail MCP；备用：直连 Gmail API) | [GMAIL_CAPABILITY.md](design/GMAIL_CAPABILITY.md) | ✅ v1.0 已批准，未实现 | 同上，在 M4 之前 |
| 以记忆为核心的 Bot 成长体系 | [MEMORY_GROWTH.md](design/MEMORY_GROWTH.md) | ✅ v1.0 已批准，M1 已实现 | 按 MEM-UI-01~12 验收 M1；决定是否开始记忆 M2 |

**MCP M1–M4 已实现**，其上的 **插件 P1 已实现**（schema v10）。M4 仅提供 OAuth 连接，不提供 Gmail 邮件工具；M5~M7 未实现。原 M0 / G0 技术验证已取消。记忆 M1 占用 schema v4，Bot 标签占用 v5，Bot 置顶占用 v6，MCP 表占用 **v7**，M2 列占用 **v8**，账号占用 **v9**，插件安装表占用 **v10**。`frontend/web` 冻结。

## 1. 已完成功能 (Features done)

| 模块 | 状态 | 说明 |
|---|---|---|
| 账号 Accounts | ✅ | 注册 / 登录 (bcrypt + JWT)，Token 持久化，失效自动退出，设置页底部退出登录 (二次确认)。昵称 `PATCH /api/me`（设置页可编辑；首页与对话读同一 `AppState`） |
| 租户隔离 Isolation | ✅ | 所有查询带 `user_id`，越权 (IDOR) 返回 404 |
| Bot 管理 | ✅ (API) / 🟡 (标签部分 UI 延期) | 创建 (＋)、编辑 (Bot 详情 / 长按「编辑与权限」)、左滑删除；置顶支持左滑 / 长按，置顶项优先排序且 Boss 已验收；标签 UI 与 Bot 详情/删除流程验收延期；软上限 20 (`MAX_BOTS_PER_USER`)；名称右侧显示标签，行右上角显示最后消息时间；搜索只过滤已加载的 Bot 名称与最后消息预览，完整聊天历史搜索、搜索历史等延期 |
| 流式对话 SSE | ✅ | 逐 token 渲染、工具卡片、交接 Trace 卡片、错误气泡 |
| 记忆 Memory | ✅ | 显式长期记忆 M1、每 Bot 记忆分组、最近 20 条对话窗口；M1 UI 验收延期，M2+ 摘要 / 向量检索尚未开始 |
| 工具 Tools | ✅ | 天气 (Open-Meteo)、创建 / 查询提醒、`ask_bot`；外部插件（Learn / AWS）需先安装并同意，再在 Bot 里单独打开 |
| 多 Agent 协作 | ✅ | 工具白名单、委派白名单、接受委派、上下文隔离、深度 / 环路 / 单轮上限 / Token 预算、审计日志、协作记录页 |
| 每日 Token 预算 | ✅ | 超额 429，委派也被拒 |
| 提醒 Reminders / 用量 Quota | ✅（R1，模拟器已验证，Boss 2026-10-04 验收；真机未测） | 提醒 Tab 分段「提醒 / 通知」；服务端到时与补跑；本地通知；APNs 未做。用量看板从设置页「用量」进入 (不再是 Tab)，不显示账号分组。Web 冻结，没有新界面 |
| 语音输入 Voice input | ✅ (Boss 手工验收通过) | Web `/api/transcribe`；iOS Speech 框架。启动失败、页面消失、进入后台时释放麦克风和音频会话（修复疑似闲置高 CPU，待观察） |
| 语音播放 TTS | ✅ | 用户 + Bot 气泡 🔊，本机 TTS；设置里可关闭 |
| 设置页 Settings | ✅ | 首页头像入口（2026-10-04 起点头像弹出自定义底部面板：2026-10-05 起为悬浮圆角卡片（四角 36、距边 8pt、顶端在导航栏下方约 88% 屏高），弹簧动画弹起、背景变暗，点空白、下拉把手或左上角 xmark 关闭；`Core/UI/BottomPanel.swift`）；账号 → 用量 → 记忆 → 插件 → 通用 (外观 / 通知 / 触感反馈 / 语言) → 语音 → 关于 → 退出登录 (最底部)。右上角 🐞 进入「调试」页：服务器地址、健康检查、版本 / 构建信息。插件页界面验收未做 |
| 照片头像 Avatars | ✅ | 用户与每个 Bot：相册设置、更换（iOS 不再提供「恢复默认」入口，后端 DELETE 保留）；服务端 512 JPEG、按用户隔离。Boss 已验收头像与昵称相关 iOS 流程 |
| 导航 Navigation | ✅ | 二级页面隐藏 Tab 栏；对话标题 → Bot 详情 sheet；首页原生圆形按钮；头像统一正圆 (`CircleAvatar`)；工具栏取消 / 关闭为系统圆形 X (`DismissToolbarButton`) |
| 键盘 Keyboard | ✅ | 输入栏随键盘上移、点空白 / 下拉收起、表单 next、多行人设 / 指令、sheet 保存后布局正常 |
| 视觉风格 Visual style | 🟡 部分验收 | 白底 + 灰分组、iOS 26 Liquid Glass (旧系统回退)、主题语义色集中在 `Core/UI/Theme.swift`、深色模式；未覆盖页面验收延期 |
| 输入栏 Composer | ✅ | 浮动玻璃：圆形 ＋ (附件占位菜单) + 胶囊输入框 + 🎙；无发送按钮，return 发送；Boss 已验收 |
| 消息富文本 Rich messages | ✅ | Markdown 排版、自动识别网址 / 电话 / 邮箱、网页在 App 内打开、长按复制；解析有单元测试，Boss 已验收 |
| App 图标 / 名称 | ✅ | 主屏「Vera Bot」；AppIcon 1024 单尺寸 |
| 附件 Attachments | 🟡 部分 | ＋ 菜单：「图片」(PhotosPicker，P1) 与「拍照」(系统相机，P2，2026-10-04；无相机设备不显示) 可用；「文件」已启用 iOS 系统文件选择器；PDF/TXT/MD/CSV/DOCX/XLSX、10 MB、单消息一个；真实设备验收待做 |

## 2. 已知限制 (Known limits)

- **iOS 与 Web 不对等**：Web SPA 没有迭代 2 的 iOS UI 改动 (权限编辑、协作记录、设置页、TTS)，也没有 2026-10-01 之后的改动 (昵称编辑、照片头像、调试页、通用设置、列表时间 / 搜索、Liquid Glass 视觉、浮动输入栏、富文本 / App 内网页、MCP 服务开关、M2 的同意 / 同步 / 熔断)，只作为 API 验收客户端。`frontend/web` 冻结，落后于 MCP M2。**Web 暂不支持删除单条消息**（iOS 长按「删除」，接口 `DELETE /api/bots/{bot_id}/messages/{message_id}`；Web 只有清空整段对话）。
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
| 真机 (Real device) | iPhone 12 Pro Max 目标构建已通过；尚未安装 / 启动。M3 确认卡片及提醒编辑交互仍待 Boss 在 Xcode 手工验收 |
| 昵称 / 照片头像的 iOS 界面 | Boss 手工验收通过 (2026-10-01) |
| 首页正圆头像、圆形 X 取消 / 关闭、行时间、首页搜索 (UI-11~14) | Boss 手工验收通过 |
| iOS 17 / 18 旧系统 | 未测 (`defaultScrollAnchor` 等 iOS 18+ API 已做版本判断) |
| 白底 + Liquid Glass、深色模式 (UI-16~19) | 首页、设置、对话、主要列表已验收；新建 Bot / 提醒 / 登录 / 调试页验收延期 |
| 浮动玻璃输入栏 (UI-20)、return 发送 | Boss 手工验收通过 |
| 消息富文本 / App 内网页 / 长按复制 (MSG-01~04) | 解析 `swift test` 通过；Boss 手工验收通过 |
| 动态字体 (Dynamic Type)、iPad | 未测 |

## 4. 下一步 (Next steps)

1. **真机手工验收**：Boss 在 Xcode 将当前 `main` 运行到 iPhone 后，验收 MCP 确认卡片和提醒编辑保存 / 删除 / 时区行为，并记录结果；提醒页视觉修复已通过。
2. **M4 真实 OAuth 手工验收**：需配置 Google Cloud OAuth 客户端、测试用户和 Workspace Developer Preview；完成授权、取消、重启保持、scope step-up、失效刷新及断开 / 撤销验收后，再推进 Gmail 工具。
3. **完成剩余手工验收**：记忆 M1、用量、Bot 标签、详情 / 创建页、单条消息删除、MCP / 插件页面，以及尚未覆盖的视觉页面；按 [TEST_CASES_v0.1.md](testing/TEST_CASES_v0.1.md) 的待验收项逐项记录。
4. **连接器真实冒烟**：CONN-LIVE-01~06 需要 GitHub / Linear 测试令牌与测试仓库；连接器 UI 验收也仍待完成。
5. **记忆成长验收**：M2–M5 已实现；完成 M3/M4 页面和 M5 语义召回、授权共享、反馈提示的手工验收，按 [MEMORY_GROWTH.md](design/MEMORY_GROWTH.md) 记录结果。
6. **平台覆盖**：APNs 尚未实现；iOS 17 / 18、Dynamic Type、iPad 等覆盖仍未验证。路线图见 [ROADMAP_NEXT.md](ROADMAP_NEXT.md)。
