# 功能清单与 API 摘要 (Features & API) — v0.1.0 + 未发布改动 (Unreleased)

## Bot 个性化 Feed（2026-10-17，未发布工作区）

后端v36提供 `/api/feed/plan`、`/plan/suggest`、`/catalog`、`/sources`、`/refresh`、`/items`、`/items/{id}/state`、`/items/{id}/context`。一个用户Feed、多个Bot推荐关联，四类内容统一模型；来源简介/实际订阅正文证据分开，原文/媒体在原站查看。收藏引用独立于来源启用状态保存，不自动复制资料库。关注计划显式启用，记忆建议同时受账号/Bot/计划/请求开关限制。

独立worker增量读取公开来源，公开主题目录匹配为首版选源方式；不使用私人记忆做外部查询。每天最多20个新链接，按来源份额发布；预算跳过的候选有界保留，304仍能续发。原生「发现」Tab正在接入。正式库/主线不由本任务更新；平台账号连接、模型摘要、转写、全网发现、完整播放器后续评估。见[设计与JSON契约](../superpowers/specs/2026-10-17-personal-feed-design.md)、[验证状态](../testing/2026-10-17-personal-feed.md)。

## 2026-10-16 主线集成补充

当前源码与本机部署 schema v38（2026-10-19：v36 Feed、v37 统一事项「安排」、v38 俄罗斯方块代玩会话）。早先：资料库使用 v33/v34，旧任务标记与 trace 瘦身统一使用 v35；兼容此前远端 v33。下方部署与验证信息按日期保留，不能视作本轮已部署。详见 [集成记录](../tasks/2026-10-16-main-integration.md)。

## 会话点击与图片预览（2026-10-16）

群列表不再显示等待用户补充的状态文案；列表行与会话顶部头像/名称区域扩大点击范围。资料图片点击直接全屏预览，阻止重复打开，资料详情移至长按菜单。见 [验证记录](../testing/2026-10-16-conversation-interactions.md)。

## 群资料分页（2026-10-16）

群设置新增设置/文件/图片分页，复用资料库列表、预览及本地缓存，只显示本群来源的资料。原群设置布局与操作保留，无新增后端接口或迁移。见 [验证记录](../testing/2026-10-16-group-library-tabs.md)。

## 独立资料库（2026-10-15）

当前源码与已部署后端 schema v34。全局汇总私聊/群聊文件与图片，Bot 主页提供概览/文件/图片；资料生命周期独立于对话。支持来源跳转、Bot 关联/解除、显式共享、全局删除及本地下载。下载原件支持离线复用，Wi-Fi 自动、蜂窝手动。详见 [交付记录](../testing/2026-10-15-independent-library.md)。

## 对话离线阅读补充（2026-10-15）

进入私聊/群聊时先展示本机已保存的历史与草稿，并完成初次滚动定位；后端慢或不可达不妨碍翻阅已保存的历史。历史同步继续使用修订号，未变化时不重传整段历史。未下载内容与附件原始文件不因此自动具备离线能力。

## 2026-10-15 当前主线补充

2026-10-15 资料库集成前为 schema v32；群聊 v2、主 Bot、私聊持续执行与通知事件均已合入 main。下方各日期章节保留历史实现范围。助理列表移除独立的「主 Bot：名称」快捷行，通过原 Bot 会话行进入；主 Bot 身份徽章及详情/对话中的任务入口保留。

## 对话持续执行与本地通知（2026-10-14，集成分支）

普通发送创建持久回复任务，不要求先设主 Bot。服务端接收后由独立 chat worker 执行；旧 `POST /api/bots/{id}/chat` 仍在，同一会话已有新任务时返回忙碌冲突。列表未读按已发布 Bot 消息计算，进入对话并真正看到回复后才上报已读。

通知仍不发 APNs。`GET /api/notification-events` 提供账号级增量；提醒由本机排程，Bot 新消息和 `task_result` 由 App 前台同步后显示。源码 schema v31。实现边界见 [集成记录](../testing/2026-10-14-integration.md)。

## 主 Bot 第一版（2026-10-14，本地main）

每账号可选零或一个主Bot，身份不自动启用主动任务；统一头像右下角徽章与助理页快捷入口，不改变置顶或群路由。Bot详情可设置身份，详情/对话更多菜单进入任务。用户确认目标、完成标准和预算后交办，可安排周期、查看历史/状态、补充回答、批准写操作、停止/继续或移交。已有排程默认只读，新模式owned使用独立业务Worker；后台需要常驻，APNs未接入。

新增API：GET/PATCH `/api/primary-bot`；POST/GET `/api/owned-tasks`，详情/inputs/stop/continue/transfer/events/events/stream；scheduled-tasks创建可选execution_mode。JSON字段与Swift PrimaryBotSettings/OwnedTask/ScheduledTask各自CodingKeys一致，requestKey由Idempotency-Key头传递，修改/回答均带expected_version；旧User缺primary_bot_id仍可解码。源码schema v29，新增能力已实现、2026-10-14已合入本地main（b68dfc4），真实验收待完成，见[交付](../testing/2026-10-13-primary-bot.md)。


> 能力进度于 2026-10-12 对齐，详细实现与验收边界见 [项目盘点](../testing/2026-10-11-project-inventory.md)。标注「待 Boss 验收」的界面效果见 [STATUS.md](../STATUS.md)。`frontend/web` 冻结，没有 MCP / 确认卡片界面。

> 能力进度于 2026-10-13 对齐，主线/工作树与验收边界见 [当前盘点](../testing/2026-10-13-project-inventory.md)。标注「待 Boss 验收」的界面效果见 [STATUS.md](../STATUS.md)。`frontend/web` 冻结，没有 MCP / 确认卡片界面。

## 2026-10-13 执行能力边界

> 本日稍后复核：`a01b2d7`群v2已合入main，源码schema v25；已移除默认回应者并具备持久澄清/接力，真实交互仍待用户验收。下方“独立工作树、未合入”属于早先盘点，群当前能力见[最新交付](../testing/2026-10-13-group-intent-handoff-repair.md)。主Bot设计已确认、具体计划待审阅，尚未编码。

- 定时任务 v1 的后台只读执行已实现；36 项离线回归本轮通过。任务需要独立后台进程，API 启动不等于任务后台部署；无 iOS 任务管理页或 APNs。
- 当前后台不支持委派、附件、写操作或等待用户后恢复，也未开放私聊已有的 web_search/web_read_result。排程 resume 只恢复未来排程，不恢复一次执行的中间进度。
- 群意图/澄清/持久接力在独立工作树开发并交付手动测试，尚未合入 main；主线仍保留默认回应者。账号级主 Bot、徽章、默认任务负责人及通用确认续跑未实现，方案见 [讨论稿](../superpowers/specs/2026-10-13-primary-bot-design.md)。
- 本文下方旧日期界面描述保留原范围；头像十一种形状、群附件与语义路由以当前增量和最新章节为准，不把早期正圆/纯文字限制当当前全部功能。

## 2026-10-12 当前整合增量

- iOS SQLite 本地库保存 Bot/群列表、完整分页历史、草稿与未确认消息；账号和服务器隔离，网络失败保留缓存，私聊不自动重发。
- 定时任务由后端 API + 独立 Scheduler/Worker 执行，支持周期、暂停、手动运行、历史、租约、预算与结果投递；当前没有任务管理 iOS 页面或 APNs。
- 群聊任务 v2 已在隔离 worktree 实施：按意图选择负责人、动态澄清并保持负责人、结构化咨询/交接；创建与设置不再配置默认回应者。
- 主工作区仍以 schema v23 和 [Main 集成交付](../testing/2026-10-12-main-integration.md) 为准；schema v24 的构建与待用户验收项见 [群任务实现记录](../testing/2026-10-12-group-intent-and-handoff.md)。

## 功能 (Features)

> **2026-10-09 · iOS 体验更新**：本地 Bot 冷启动欢迎、连接失败默认页 / 保留内容提示、登录页重设计及已打开弹窗的主题同步。复用现有 Bot 动作；浅 / 深 / 跟随系统由整个窗口统一传递。详见 [验收记录](../testing/2026-10-09-startup-connection-appearance.md)，真机验收状态单独标注。

| 模块 | 说明 |
|---|---|
| 账号 (Accounts) | 邮箱 + 密码、邮箱 + 验证码 (新邮箱自动建号)、手机号 + 密码注册 / 登录 (默认邮箱密码，其他方式展开选择)；老的用户名账号 (demo) 仍可在邮箱框登录，界面不展示用户名；bcrypt 哈希；访问令牌 JWT 7 天 + 刷新令牌 60 天 (轮换，iOS 透明刷新，Keychain 保存)；连续 5 次密码错误锁 15 分钟；邮箱未验证可正常使用，设置页提醒验证；失效自动退出；设置页底部退出登录 (二次确认)。昵称可在设置页点按昵称弹窗修改（1–32 字，去空白），首页左上角和对话里的用户名立刻更新 |
| 租户隔离 (Per-user isolation) | 所有查询带 `user_id`；访问他人资源统一返回 404 (防枚举)。设备侧缓存：后端 `/api/*` 带 `Cache-Control: no-store`，iOS API 走无缓存会话，退出 / 登录清本机 `Cache.db`（缓存修复，Boss 于 2026-10-04 验收通过） |
| Bot 管理 | emoji 头像 + 颜色 + 昵称 + 人设 (多行) + 指令 (多行) + 标签 (最多 3 个，每个最多 4 个字，逗号 / 顿号 / 空格分隔；创建页一个输入框，Bot 详情点卡片上的标签行弹窗修改；首页行名称后显示为一个浅灰圆角矩形「搜索, 查询, 调研」，Bot 详情卡片名称下方一行)；＋ 创建 (达到上限时 ＋ 置灰；列表不显示数量页脚)、Bot 详情编辑、长按「编辑与权限」、左滑删除 (系统确认框二次确认，说明删除 / 保留的数据)、左滑 / 长按置顶 (品牌色实心 pin 图标，点按后行立即用系统动画移到新位置，再同步服务端，失败回滚)；软上限 20 (`MAX_BOTS_PER_USER`)。列表每行名称右侧显示标签（放不下时尾部截断），右上角显示最后消息时间（今天 HH:mm / 昨天 / 本周星期几 / M/d / 非今年 yyyy/M/d，无消息回退创建时间）；首页不显示大导航标题；右上角放大镜点按后才出现系统搜索栏（平时不显示搜索框，下拉也不出现；取消后收起并清空），当前只过滤屏幕上已加载的列表（Bot 名称和最后一条消息预览）；完整聊天历史搜索、搜索历史等移至后续迭代。所有头像（用户 / Bot，照片或表情 / 首字）都显示为正圆。用户和每个 Bot 都可以另设一张圆形照片头像（相册选择、可更换；Bot 可在详情页点头像选「使用默认形象」移除照片，用户头像不提供该入口）；表情字段保留，没有照片时继续显示。Bot 详情页：顶部单独显示头像 (点头像打开原生菜单，可从相册选择或恢复默认形象) → 昵称/标签分区 → 合并选色卡 → 人设分区 → 自定义指令 → 记忆 → 工具权限 (只显示中文名) → 委派 → 协作记录 (本机时间) → 清空对话；界面无英文 |
| Bot 头像操作 | 两页顶部无背景单独显示头像，昵称与标签在其下方分区居中，使用常规字号，不展示标签标题或昵称必填提示；共用合并选色卡，人设在选色卡下方独立分区编辑；详情页点昵称或标签弹窗修改，点头像打开原生菜单选择相册照片或恢复默认形象，变更在保存时提交 |
| 流式对话 (Streaming, SSE) | `POST /api/bots/{id}/chat` 返回 `text/event-stream`，逐 token 渲染；工具卡片、交接 Trace 卡片、错误气泡 |
| 游乐场游戏助手 | 游乐场大标题所在行的右侧显示 Bot 头像，点击打开游戏助手对话；首次点击创建当前账号的游戏助手预设，之后复用。助手是可编辑、可删除的普通 Bot，计入数量上限，提供数独、推箱子、俄罗斯方块、贪吃蛇、打地鼠（小 Bot 版）的规则和提示（新建助手预设；既有助手自定义指令不覆盖）；局面由用户提供，不自动读取或操作游戏。「挑一个玩法」含俄罗斯方块、贪吃蛇、打地鼠（小 Bot 版）与 Bot 旅行（本地原型，经该列表进入出发页与旅行相册）；顶部为可左右滑动的推荐卡片：数独、推箱子（已从列表上移）、Bot 漂流瓶（即将推出，规划中） |
| 打地鼠 · 小 Bot 版 | 离线九宫格小游戏，复用现有机器人形象；60 秒有效游玩时间，点中 +10，同一次探头只能计分一次，空点/漏掉不扣分。每 20 秒加快，最多同时 1/2/3 个；命中表情、缩回、轻触感与音效遵守设置/减少动态效果。开始/暂停/继续/重开；后台、玩法弹层与离页自动暂停；结算得分/命中率/本机最佳（服务器+账号隔离），关闭页面不保留本局。见[交付记录](../tasks/2026-10-20-whack-a-bot.md) |
| 对话页导航 | 中间标题（Bot 头像 + 名称）打开 Bot 详情；右上角三点「更多」按钮沿用首页「＋」的系统原生圆形工具栏样式，当前为空操作 |
| 消息富文本 (Rich messages) | iOS Bot 气泡支持 Markdown（标题 / 粗体 / 斜体 / 行内代码 / 代码块 / 引用 / 列表 / 表格 / 分隔线），自动识别网址 / 电话 / 邮箱；网页链接在 App 内 SFSafariViewController 打开，电话 / 邮件交给系统；长按气泡可复制全文或复制链接，用户 / Bot 气泡长按均有「删除」(系统确认框二次确认，只删这一条；欢迎语与正在生成的回复不显示)；`~` 按原文显示 (BUG-01) |
| 对话历史 (History) | 每个 Bot 独立保存历史，最近 20 条 (`VERABOT_HISTORY_WINDOW`) 注入上下文；清空对话 (二次确认：「仅清空对话」删除对话摘要、保留已确认记忆 /「清空对话和「X」的记忆」再删该 Bot 的记忆) |
| 长期记忆 (Memory, M1–M5) | **先确认、后保存**：Bot 用 `remember` / `forget_memory` 只生成提议，对话里出现「要我记住吗？」卡片 (记住 / 不用 / 编辑后记住)，确认后生效。作用域：所有 Bot 共享的「关于你」(global) 或仅某个 Bot；每个 Bot 的 `memory_access` (不使用 / 仅本 Bot / 本 Bot + 共享资料，默认后者)；每轮最多注入 12 条 / 1000 字，风格最多 3 条排在最前，委派不写目标记忆；M5 允许按双方权限显式共享普通已确认记忆，并给目标附加符合权限的 profile/style；敏感、摘要和非 active 记忆不共享。密码 / 验证码 / 密钥 / 证件号 / 卡号永不保存；健康、财务信息加密保存并标为敏感。**M2**：每个 Bot 一条滚动摘要（窗口外积压满 20 条才压缩，≤ 400 字，不经确认，清空对话时删除）；回复气泡可 👍 / 👎，「再短一点」或 14 天内 3 次「太长」只提议风格（「以后都这样回答吗？」），确认前不生效。设置 › 记忆：「Vera 了解的你」(查看 / 编辑 / 删除 / 手动添加 / 清空，首次打开说明会发送给 DeepSeek) + 「允许 Bot 记住」总开关。Bot 详情 › 记忆。方案与契约见 [MEMORY_GROWTH.md](../design/MEMORY_GROWTH.md)。Web 无记忆 UI |
| 工具 (Tool calling) | 可插拔注册表：`get_weather`、提醒三件套、`ask_bot`；记忆工具由 `memory_access` 控制。MCP 工具默认关闭；OAuth 远程连接（M4）使用 PKCE，Token 加密保存在后端。Gmail 目前只有连接入口，邮件工具尚未开放。**写 / 发送 / 破坏性**调用会弹出确认卡片（M3，`pending_actions`），确认后才执行冻结参数；只读可直接执行。委派深度 ≥ 1 不能用 MCP |
| 多 Agent 协作 | 工具 / 委派白名单、接受委派开关、上下文隔离、深度 / 环路 / 单轮上限 / Token 预算、审计日志、协作记录页 → [MULTI_AGENT_DESIGN.md](../design/MULTI_AGENT_DESIGN.md) |
| 每日 Token 预算 | 超额返回 429，委派也被拒 |
| 安排 / 用量 (Agenda / Quota) | Tab「安排」（原「提醒」），视觉顺序：助理 · 发现 · 游乐场 · 安排 · 空间（2026-10-19 调换；按 tag 路由）。顶部分段「提醒 / 通知」保留。事项分组：今天（含逾期）、计划、待办、Bot 任务、已错过/已完成；可建待办或带时间安排、一层清单；详情先看后改。API `/api/items`（schema v37）；旧 `/api/reminders` 兼容。到时本地通知；任务结果通知优先开关联事项详情。对话/Bot 编辑「任务」→ 安排 Tab 按该 Bot 筛选。用量看板仍在「设置 › 用量」。Web 无新界面。**R1 提醒于 2026-10-04 验收；安排 P1 待验收** |
| 语音输入 (Voice input) | Web：录音 → `/api/transcribe` (OpenAI) → 填入输入框；iOS：系统 Speech 框架 (zh-CN)；都不自动发送 |
| 语音播放 (TTS) | 用户消息和 Bot 回复下方 🔊，本机 AVSpeechSynthesizer；设置里可关闭；云端 TTS 占位。iOS：退出对话、后台 / 锁屏、开始语音输入时停止，不自动恢复；滚动和临时弹层继续。详见 [朗读生命周期决策](../design/CHAT_SPEECH_PLAYBACK.md)。 |
| 设置页 (Settings) | 首页左上角头像进入；账号 (点头像换照片、点昵称弹窗修改；下方显示邮箱 / 手机号，老账号显示用户名；邮箱未验证时显示「邮箱未验证 · 验证」) → 用量 (push 用量看板) → 记忆 (「Vera 了解的你」+「允许 Bot 记住」) → MCP 服务 (按服务启用、刷新、给某个 Bot 开只读工具) → 通用 (外观：跟随系统 / 浅色 / 深色；通知开关，开启时申请系统授权，被拒绝则回退并提供「前往设置」；触感反馈开关，控制 App 内所有 sensoryFeedback；语言：显示当前语言，点按打开系统设置中本 App 页面切换) → 语音 → 关于 (版本号) → 退出登录 (单独一组，位于最底部)。头像用系统 PhotosPicker，预览为圆形，确认后上传 |
| 调试页 (Debug) | 登录页 / 设置页右上角 🐞 (`ladybug`) 进入；未登录时可编辑服务器，登录后只读；包含外观切换、最近连接错误详情、后端健康检查 (`GET /api/health`)、版本 / 构建号 / Bundle ID / 系统版本 / 构建配置；另有唯一的「头像实验室」试验入口，包含状态演示、家族形象与配色、本机外观配置；支持深色模式与减弱动态效果 |
| 导航 / 键盘 | 二级页面隐藏 Tab 栏；对话标题为可点击的原生胶囊按钮（iOS 26 Liquid Glass，旧系统 bordered 回退；头像 + 名称，不显示标签）并打开 Bot 详情 sheet；首页原生圆形按钮（左上角头像为正圆，iOS 26 隐藏系统共享玻璃底 (`.sharedBackgroundVisibility(.hidden)`) 并放大到 44pt，与右侧圆形按钮等大，旧系统 30pt；右上角 放大镜 搜索 与 ＋ 创建 为两个独立圆形按钮，iOS 26 用 `ToolbarSpacer(.fixed)` 分开）；工具栏 / sheet 的取消、关闭为系统圆形 X（iOS 26 `Button(role: .cancel / .close)`，确认框里的取消仍是文字）；输入栏随键盘上移、点空白 / 下拉收起。对话输入栏为浮动 Liquid Glass：圆形玻璃 ＋ 附件按钮 + 胶囊玻璃输入框（占位「向 {Bot 名} 提问」，尾部 🎙 语音输入），无发送按钮，键盘 return 发送；iOS 26 输入栏用 `safeAreaBar(edge: .bottom)`，消息滚到输入栏下方有系统底部滚动边缘效果（渐隐模糊，与顶部导航栏一致），旧系统 `safeAreaInset` |
| 视觉风格 (Visual style) | 页面白底（深色黑底），分组 / 卡片 / Bot 气泡浅灰 `#EFEFEE` (RGB 239, 239, 238)（深色 `secondarySystemBackground`）；「助理」列表为白底全宽平铺、无分隔线；iOS 26 Liquid Glass（系统导航栏 / Tab 栏 / 工具栏按钮，`.glass` 胶囊、`.glassProminent` 主按钮，旧系统 bordered 回退）。颜色集中在 `Core/UI/Theme.swift` 语义色，设置 › 外观 切换时全局一致；所有开关为缩小 85% 的系统 Toggle (`CompactToggle`) |
| 附件 (Attachments) | **图片 (P1，schema v12)**：＋ 菜单「图片」用系统 PhotosPicker 选 1 张 (再选替换)，本机压缩后上传，输入栏显示缩略图 (上传中不能发送，可只发图片)；气泡始终显示真实图片，GIF 播放动画，点按 Quick Look 全屏 / 分享；模型 `deepseek-flash` 看图，之后按需召回 (描述 + `view_image` / 回指时重发原图)；委派时图片转给被委派 Bot；带图轮次创建提醒需文字确认；图片随清空对话 / 删除 Bot 删除。**拍照 (P2)**：＋ 菜单「拍照」打开系统相机 (UIImagePickerController)，拍到的图与相册同一路径 (1 张、再拍替换、压缩去 EXIF、上传中不能发送)；无相机设备 / 模拟器不显示；拒绝相机权限时提示「前往设置」。文件入口已启用（iOS 系统文件选择器，支持 PDF/TXT/MD/CSV/DOCX/XLSX，单文件 10 MB、每条消息 1 个）；后端按需读取文本并以 Quick Look 预览。设备级与真实模型验收待完成。Web 不支持 |
| App 图标 / 名称 (App icon & name) | 主屏显示名「Vera Bot」(`INFOPLIST_KEY_CFBundleDisplayName`，`InfoPlist.xcstrings` zh-Hans / en 均为「Vera Bot」)；App 图标为 `Assets.xcassets/AppIcon.appiconset` 单尺寸 1024×1024 (源图 `assets/brand/app-icon-source.png`)。设置 › 关于 中的应用简介仍写「VeraBot · 你的私人 AI 助理团队」 |
| Web 客户端 | 只作为 API 验收客户端，功能落后于 iOS (见 [STATUS.md](../STATUS.md) 已知限制) |

> **已实现**：Bot 置顶 (schema v6，`pinned_at` + PATCH `pinned`，首页左滑 / 长按「置顶」，置顶行浅灰底)，规格与测试见 [BOT_PIN.md](../design/BOT_PIN.md) 和 [STATUS.md](../STATUS.md)。

## API 摘要

登录结果在未登录状态下也会被正常处理；登录成功进入首页，账号 / 密码错误或连接失败显示提示。登录、注册和验证码请求在会话或服务器变化后丢弃旧结果；旧账号请求不借新账号令牌刷新 / 重试。后端账号操作使用即时事务，每台设备的会话独立，注册密码需满足 bcrypt 的 72 UTF-8 字节上限。2026-10-10 回归记录见 [登录恢复排查](../testing/2026-10-10-login-recovery.md)。

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
| GET / POST / PATCH / DELETE | `/api/reminders`、`/api/reminders/{id}`、`.../complete`、`.../done`、`.../snooze`、`.../reopen`、`.../skip`、`.../restore`、`.../events` | 提醒列表与单条操作。写接口认 `Idempotency-Key`。`/done` 仍是完成的别名。字段见 [REMINDER_PUSH_DESIGN.md](../design/REMINDER_PUSH_DESIGN.md) §8；v37 起附加 `task_kind` / `task_id` / `source_kind` / 清单计数 |
| GET / POST / PATCH | `/api/items`、`/api/items/{id}`、`.../complete`、`.../reopen`、`.../snooze`、`.../skip`、`PUT .../checklist`、`PATCH .../checklist/{cid}` | 统一事项（安排）。`view=today\|planned\|todo\|bot\|done`；详情含清单与只读任务摘要。P1 不通过此接口创建 Bot 任务。见 [统一事项方案](../plans/2026-10-18-reminders-todo-tasks-unified.md) |
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

## 2026-10-11 实现与验收补充

- 记忆 M3 候选 / 建议 / 快捷提问，M4 成长 / 搜索筛选 / 引用 / 月度回顾 / 导出已实现，M3-01～05、M4-01～05 已由用户验收通过。
- M5 使用 SQLite `memory_vectors` float32 BLOB 缓存、FastEmbed `BAAI/bge-small-zh-v1.5`（512 维）和本机余弦计算，不使用独立向量数据库。混合召回、共享权限和反馈提示已实现；M5-02/03 与两项修复复测通过，M5-04 降级服务层通过，真实向量语义召回未单独记录。
- MCP M3 确认卡片已按用户指定模拟器标准验收通过。MCP M4 OAuth 已实现，真实 Google 授权仍待验收；Google 身份登录 VeraBot 未实现。
- 文件附件已实现、待功能验收；图片和拍照已验收。旅行为 iOS 本地定时原型，无服务端旅行调度或推送；陪玩最终交互及旅行完整周期待验收。
- 账号后端已有 logout-all；设置入口、忘记密码和老账号绑定邮箱未完成。登录限流为单进程，Web 会话仍存 localStorage。

## Bot 群聊正式功能（2026-10-11）

助理页群聊使用正式服务接口。后续执行设计移除默认回应者；服务端按消息意图选负责人，信息不足时动态选澄清 Bot 并在同次澄清保持该负责人，支持结构化咨询返回与任务交接。iOS 协议 v2 使用回执和事件游标恢复执行，离开页面不停止任务，提供版本化停止/继续/失败步骤重试。当前代码仅在隔离 worktree，未合入、迁移主库或发布；真实模型体验和设备交互尚未完成，见 [实现记录](../testing/2026-10-12-group-intent-and-handoff.md)。

### 群聊 @ 输入交互（2026-10-12）

输入 @ 可筛选群成员或 everyone；列表采用液态玻璃样式，最多显示五项，超出滚动。点击成员在光标处插入带专用字色和成员身份的 @ 标记，继续输入使用普通字色；编辑标记内容后清除点名身份。支持中文组合输入、键盘焦点切换及正文中间插入，发送失败时保留草稿标记。25 项编辑器回归通过，用户已确认本轮交互验收通过，见 [验收记录](../testing/2026-10-12-group-mention-keyboard.md)。
