# 更新日志 (CHANGELOG)

## 2026-10-19 · 游乐场推荐卡片 + 「空间」

- iOS 游乐场：`PlaygroundFeature.all` 驱动的横向分页卡片（`FeaturedGamesCarousel`），数独 / 推箱子 / Bot 漂流瓶（即将推出）；推箱子不再出现在下方列表。
- 「探索」Tab 与导航标题改为「空间」，tag 与路由不变。

## 2026-10-19 · 隐藏二十问入口

- iOS 游乐场列表过滤 `.twentyQuestions`；`TwentyQuestionsGameView` 等代码保留。助手开场与 FEATURES 去掉二十问入口描述。

## 2026-10-19 · 探索页过滤已实现想法

- iOS `ExploreIdea.groups` 移除 `games`（已由游乐场实现）；其余想法保留。

## 2026-10-19 · 底部 Tab 调换

- iOS `MainTabView`：「发现」移到第 2 位、「安排」移到第 4 位；tag 不变，其余不变。

## 2026-10-19 · 游戏计划执行后进度核对（仅文档）

- 核对DeepSeek Harness执行后的代码/提交和原三项计划：掌机与音效首版已进main，完整计划仍有差异，云端未见仓库交付；分别记录构建声明、测试覆盖、设备安装与验收状态。
- 从stash仅恢复6份缺失计划文档，更新[总账](tasks/2026-10-18-game-upgrade-progress.md)、原方案入口与[核对记录](tasks/2026-10-19-game-plans-progress-audit.md)。未改产品代码或运行服务，未提交/推送。

## 2026-10-19 · 「安排」页小标题

- iOS `RemindersView` 导航标题 `.large` → `.inline`；其余不变。

## 2026-10-19 · 「安排」API 501 阴影修复

- `VeraBotAPI` 扩展不再用带默认参数的 501 占位阴影 `APIClient+Items`；改为更少参数的便利重载转发完整协议要求。安排列表 / 创建 / 完成 / 推迟 / 删除 / 清单 / 任务操作在 `any VeraBotAPI` 上可真正发请求。
- 回归：`ItemsAPIDispatchTests.existentialItemsOmittingArgsHitsAPIClientNot501Placeholder`。


## 2026-10-18 · 「安排」P2：交给 Bot 执行

- 后端：`POST /api/items` 支持可选 `task`（once/repeat→scheduled、owned→owned），同请求关联 `task_kind/task_id` 并复用 Idempotency-Key；操作代理 `/api/items/{id}/task/{pause|resume|run|stop|continue|input}` 不暴露 step/lease/token/trace；`services/items/sync.py` 写回同步（owned 完成→事项自动完成、任务删除/停止→解除关联标注「任务已结束」、scheduled 推进→事项 due 跟随 next_run）；`propose_task` 工具走 `pending_actions` 确认卡片，确认后才建任务+事项；`DELETE /api/items/{id}?task=stop|keep`。
- iOS：编辑器「交给 Bot 执行」开关（选 Bot / 指令 / 一次·周期·持续，持续无权限给原因+设置入口）；详情任务区块（状态胶囊 / 下次执行 / 最近结果+查看全文 / 执行记录 / 等你处理内联问答 / 任务操作 / 删除并停止）；通知点按聚焦回答区块；下线 `TaskListView` 并清理工程引用。
- 测试：`unified_items_p2_test.py` P2-01~10 全绿；`unified_items_test.py` 无回归；`swift test` 388/388；`xcodebuild`（iPhone 17 模拟器）BUILD SUCCEEDED。见[任务记录](tasks/2026-10-18-unified-items-p2.md)。

## 2026-10-18 · 俄罗斯方块掌机按键 v2

- 五键横排改为：左侧一体十字（左/右移动、向下缓降；上方向留空不绑定）+ 右侧斜排圆形 A(旋转)/B(直接落下) + 下中 START(暂停/继续)/SELECT(菜单，重开收进菜单)。受掌机启发、非 1:1 复刻；命中区≥44pt、按压行程+触感、长按连续移动、遵守触感开关与减少动态效果。见[任务记录](tasks/2026-10-18-tetris-controls-v2.md)。

## 2026-10-18 · 游戏音效 v1

- 俄罗斯方块 + 贪吃蛇共用 `GameSoundPlayer`（有限 AVAudioPlayer 池 + `.ambient` 会话，遵守静音、可混音、不启用后台音频）；10 个短音由 `frontend/ios/Tools/gen_game_sounds.py` 用标准库确定性合成（单声道 44100Hz 16bit，约 65KB，自行合成无第三方授权）。
- 会话协调：录音/朗读优先，游戏只在未占用时播放；中断/耳机断开/后台/锁屏立即停声不补播。独立「游戏音效」设置（默认开启）+ 游戏内扬声器快捷开关。见[任务记录](tasks/2026-10-18-game-sound-effects.md)。

## 2026-10-18 · 集成修复与收尾

- 修复 v34 迁移 `row['payload']` 对 tuple 取值导致的升级崩溃；修正 STATUS 文档漂移（P1 已部署/已验证、Feed 已合入 main）。补齐 P2 的 `VeraBotAPI` 协议声明与默认实现（`itemTaskAction`/`deleteItem`）、修正 `GameButtonStyle` 参数顺序。

## 2026-10-18 · 游戏按钮增加实体按键触感

- 贪吃蛇和俄罗斯方块操作按钮接入 `GameButtonStyle`：按下短震、轻微下压、底座与边缘反馈、松手弹回；硬降使用更强 impact。
- 现有触感包装支持条件触发，默认调用保持原行为；游戏键只在按下沿且启用时触发，遵守统一触感开关和减少动态效果。游戏规则与动作触发逻辑未改。见 [任务记录](tasks/2026-10-18-game-button-haptics.md)。

## 2026-10-18 · 新增贪吃蛇备用游戏

- 游乐场在俄罗斯方块后增加贪吃蛇；独立离线规则、20×20 棋盘、滑动与方向键、增长计分、逐档加速、暂停/继续、重开及结束/满盘结算。
- 转向队列限制为每步一次且禁止反向；正确处理腾出蛇尾与食物空格。后台/离页暂停，旧计时任务按代次失效；本机最佳记录按账号和后端隔离。
- 规则专项测试 10/10 通过，无后端修改、新依赖或 Bot 陪玩。交付与验收见 [任务记录](tasks/2026-10-18-snake-game.md)。

## 2026-10-18 · 俄罗斯方块陪玩 Bot 右侧在场

- 移除棋盘上方陪玩卡片，头像、短回应、名字、聊天及陪玩选项改到棋盘右侧中下部；下个方块保留在右上，暂停/重开并排位于右下。复用当前 Bot 形象与表情，小屏使用紧凑尺寸。
- 游戏主区按剩余空间计算棋盘，暂停/结束说明与气泡预留稳定空间。保留五个操作键和现有规则、聊天、换伙伴、安静模式及错误重试；未接入云端代玩。验证见 [任务记录](tasks/2026-10-18-tetris-companion-right-side.md)。

## 2026-10-18 · 「安排」P1：提醒 / 待办 / Bot 任务统一事项

- 后端 schema **v37**：`reminders` 增加 `task_kind` / `task_id` / `source_kind` / 清单计数；新表 `reminder_checklist`；回填未删除周期任务与未挂周期的持续任务各一条关联事项（幂等）。迁移前自动 `.bak-before-v37-*`。
- 新 API `/api/items`（列表 view、详情、创建待办/提醒+清单、complete/reopen/snooze/skip、清单 PUT/PATCH）；任务摘要只暴露业务词。`/api/reminders` 仅附加字段。Bot 工具 `create_reminder` / `manage_reminder` 支持无时间待办与 checklist，`source_kind=chat`。
- iOS Tab「提醒」→「安排」；分组 今天/计划/待办/Bot 任务；先看后改详情；编辑支持日期开关与清单；对话/Bot 编辑「任务」跳转安排并按 Bot 筛选；任务结果通知优先开事项详情。VeraBotKit：`Item` / checklist / 任务摘要、`APIClient+Items`。
- 文档与测试：`unified_items_test.py`；部署前备份正式库，重启 API 应用 v37。见[方案](plans/2026-10-18-reminders-todo-tasks-unified.md)。未跑 git / xcodebuild / swift test。

## 2026-10-17 · 游乐场接入 Bot 旅行；发现与探索 Tab 对调

- iOS：Bot 旅行从「探索」想法详情迁入「游乐场 → 挑一个玩法」（`PlaygroundGame.travel` → `BotTravelStartView`）；探索列表移除 travel 项及详情特殊入口；游乐场底部「卡住时…」占位卡删除，游戏助手头像保留。
- 底部 Tab 视觉顺序改为 助理 · 提醒 · 游乐场 · 发现 · 探索；`selectedTab` tag 不变（发现=5、探索=4）。未跑 git / xcodebuild / swift test。

## [Unreleased] · 2026-10-18 发现页紧凑卡片

- 移除顶部大标题与导航栏留白，卡片左右外边距缩为8pt；管理菜单移入筛选栏。
- 新闻图文、短帖正文、视频封面/时长、音频节目分别设计；每条右下角增加可切换Bot与Discuss，直达引用草稿。见[记录与截图](tasks/2026-10-18-feed-cards.md)。

## [Unreleased] · 2026-10-17 Bot 个性化 Feed

- 新增个人Feed后台、关注计划/记忆权限内选源建议、公开RSS/Atom/播客适配、来源管理、阅读与收藏/负反馈状态及问Bot引用草稿。
- v36新增Feed独立表和待发布候选；按来源分配每日20条上限，304可跨日续发，按稳定发布ID分页并保持批内最新优先。独立worker含租约/权限重验和固定公网连接、有界gzip/XML读取；本机fake-IP DNS可显式启用公网DoH。
- iOS底部新增第五项「发现」，实现阅读/筛选/收藏、计划/来源管理和用户确认发送的引用草稿。元数据读写与反馈错误分别处理；共享草稿跨入口修复见 `858d368`；ChatView body 拆分以通过类型检查。
- 终轮：`validate_url`/`public_ip` 拒绝歧义数字主机与 IPv4-mapped/6to4/NAT64 私网嵌入；Feed 单测 32/32。未迁正式库、未起 feed worker、未合入 main。见[交付记录](testing/2026-10-17-personal-feed.md)。

## 2026-10-16 · 附件直接发送、多图堆叠与短回复不折叠（Codex 交付，2026-10-17 合入最新 main）

- iOS 私聊/群聊：附件选完自动上传并发送，移除发送前预览；相册最多 9 张合为一条堆叠消息（卡片 67.5%、下层真实图片、各层可独立点开对应页），查看页完整等比显示、底部固定页码。批次上传支持失败重试与取消（取消清理未发送的服务器附件），文字草稿保留。
- 后端：私聊、群聊请求 `attachment_ids` 上限调整为 9，图片顺序保持；无数据库迁移。新增 `multi_attachment_test.py`。
- 长回复折叠：不超过 500 个非空白字素的回复始终完整展示，更长回复沿用原 28 行 / 500 加权字阈值。
- 版本号 0.1.0 (2026101609)。与 #52–#57（头像、标题胶囊、隐藏待同步文案）无冲突。详见 docs/tasks/2026-10-16-*.md。

## 2026-10-17 · 隐藏对话内待同步提示文案

- iOS：私聊恢复/观测失败不再把 notice 设为「待同步；已接收的回复会继续执行。」（仍 `scheduleRecovery`）；群执行状态去掉「进度待同步」行（`executionSyncPending` 逻辑保留）；MCP/插件 `syncStatusText` 在 pending（及 MCP 缺省 pending）时返回 nil，详情「同步」行整行省略，`statusText` 不再显示「等待同步」。内部 `error.contains("待同步")` 与「连接有点慢」横幅未改。未跑 git / xcodebuild / swift test。

## 2026-10-17 · 会话列表隐藏「待同步」行标

- iOS 会话列表（`BotRow`）：预览下方不再渲染灰色「待同步」caption，行高恢复为名称 + 预览两行（另有进行中项时仍可多一行）。`activityNeedsSync` 等内部同步逻辑与顶部「连接有点慢」横幅不变。群行此前已无该标。未跑 git / xcodebuild / swift test。

## 2026-10-17 · 对话标题胶囊与侧栏按钮等高

- iOS 私聊 / 群聊导航栏标题胶囊（头像 26pt + 名称）：不再用 `.glass` 按钮样式叠 `minHeight: 44`（系统内边距会让胶囊高于两侧 44pt 圆形玻璃按钮）。iOS 26 改为 plain 按钮 + label `height: 44` + `.glassEffect(.regular.interactive(), in: Capsule())`（水平约 12pt）；旧系统保留 bordered 胶囊。点击目标、无障碍文案、头像与字体不变。
- 主 Bot 紫星角标：小头像（如标题胶囊 26pt）去掉 `max(14, …)` 下限，改为约 38% 直径并略偏右下，避免盖住脸；列表 44pt 观感不变。

## 2026-10-17 · 首页头像与右上角 ＋ 对称对齐

- iOS 首页左上角设置头像：外径改为与系统工具栏圆形玻璃按钮一致（44pt，此前误用 44pt），去掉 `-14` 水平偏移，左边距与右侧 ＋ 的右边距同为系统约 16pt，垂直中心与 ＋ 同线；保留白环（单侧 2.5pt）+ `.glassEffect` / 旧系统材质回退。不改搜索 / ＋。旧系统仍 30pt。

## 2026-10-17 · 首页头像白玻璃底 + 内嵌白环

- iOS 首页左上角设置头像：外圆尺寸与位置不变，照片/首字内缩约 2.5pt，嵌在与 `JumpToLatestButton` 同款的圆形白玻璃底上（iOS 26 `.glassEffect`，旧系统 `.ultraThinMaterial`），露出可见白环，与右侧搜索 / ＋ 圆形玻璃按钮同族。不改搜索 / ＋ 及其图标色。仅改 `HomeAvatarLabel` / 相关注释，无其它 UI 变动。

## 2026-10-16 · 资料库 SQL 分层收尾

资料库残留在 `services/library.py`、`services/attachments/repo.py`、`agents/tool_router.py` 的直连 SQL 已迁入 `db/library_store.py` / `db/attachment_store.py`（及既有 `bot_store`）；查询、事务边界与返回形状不变。`sql_layer_check` SQL-LAYER-01/02 通过。见 [STATUS](STATUS.md)、[集成记录](tasks/2026-10-16-main-integration.md)。

## 2026-10-16 · Main 集成

合并本地资料库及界面调整与远端长回复折叠、过时任务标记、trace 瘦身；解决 schema v33 重号，统一升级到 v35，补充远端 v33 资料库回填与幂等回归。详见 [集成记录](tasks/2026-10-16-main-integration.md)。

## 2026-10-15 · 资料库预览下载及 Bot 页面调整

全局资料库移至头像设置，图片增加独立鉴权预览和缓存；手动下载改用前台会话并可接替自动任务。Bot 详情恢复原表单，设置/文件/图片并列，移除多余入口，合并主 Bot 操作并压缩形状选择区。见 [修复记录](testing/2026-10-15-library-follow-up.md)。

## 2026-10-15 · 暂时隐藏小岛 Tab

- iOS 底部导航隐藏「小岛」入口；小岛页面代码保留，后续可重新接回导航。

## 2026-10-15 · 全局资料库与 Bot 文件中心

新增独立资料库、Bot 文件/图片 tab、资料关联和显式共享；清空对话保留资料。新增本地目录与原件校验缓存、Wi-Fi 自动下载及蜂窝手动下载。schema v33 建立独立资料索引，v34 校正旧 TXT 现存文件元数据。见 [交付记录](testing/2026-10-15-independent-library.md)。

## 2026-10-15 · 快捷提问背景与间距

- 私聊底部快捷提问取消横向滚动区域的视觉裁切，避免胶囊阴影被切成矩形色带；按钮统一放入玻璃容器，保留 8pt 横向间距并增加上下各 4pt 留白。点按仍只填入输入框。
- 构建和视觉核对见 [快捷提问检查](testing/2026-10-15-quick-prompts-layout.md)。

## 2026-10-15 · 断网进入对话不等待后端

- 私聊与群聊在本地恢复完成后立即显示并定位消息；活动摘要并行刷新，不阻挡 SQLite 读取。
- 群聊本地翻页使用独立加载状态；移除 SQLite 同步路径里重复拉取群历史的请求，刷新保留已展开消息。验证见 [离线进入记录](testing/2026-10-15-offline-chat-entry.md)。
## 2026-10-15 · 后端：过时的失败任务不再充当会话状态、工具 trace 瘦身（schema v33）

- 会话摘要：失败／中断的私聊回复或主动任务，之后同一会话里有正常完成的回复（或主动任务完成）时标记 `superseded_at`，`/api/conversations/activity` 的 `work_items` 不再包含它，列表行不再因旧记录显示「工作暂未完成」。真正最新的一次失败照常上报。触发器维护标记，v33 迁移一次性回填存量任务，不删除任何消息。
- 工具 trace：`messages.traces`、回复事件与 SSE `tool_result` 落库／下发前瘦身——`read_file` 去掉文件原文，只留文件名、offset、length、总字数、`has_more` 等；其他工具结果的长字符串截到 2000 字并标 `…[truncated]`，原长度记在 `trace_truncated`。模型在本轮仍拿到完整工具结果。v33 迁移改写存量行，迁移前备份 `verabot.db.bak-before-v33-<时间戳>`。
- iOS：MCP 卡片「约 N 字」改读 `trace_truncated.content`（`MCPTraceText.contentLength`）；`read_file` 卡片无需改动。
- 测试：`backend/scripts/test/stale_work_trace_slim_test.py`；Swift `slimmedReadFileTraceFromBackendDecodesAndSummarizes`、`slimmedMCPTraceKeepsOriginalContentLength`。详见 [known-issues](testing/2026-10-14-known-issues.md)。`frontend/web` 未动。

## 2026-10-15 · 保存工作区改动

- iOS 助理列表移除顶部重复的「主 Bot：名称」导航行；Bot 仍通过原会话列表进入，主 Bot 身份与任务能力保留。
- 主工作区及工作树盘点见 [提交记录](testing/2026-10-15-workspace-submit.md)。


## 2026-10-15 · 长回复折叠按手机高度判定、trace 不再铺文件原文

- iOS 私聊：折叠阈值从「1500 字或 40 个 `\n` 行」改为按手机上的排版高度估算——超过约一屏（估算 28 行）或 500 加权字（中文 1、ASCII 0.5）即收起。估算按气泡宽度（约 15 个中文字一行）折行，标题、空行、表格行、代码行分别计高。预览改为 ≤ 200 字且 ≤ 8 行，去掉末尾标题和没有数据行的表头。「思考助手」594 字 / 716 字的标题 + 表格 + 列表回复（1.5～2 屏）现在会折叠，329 字的回复（不到一屏）不折叠。
- 工具 trace 卡片：`read_file` 结果（最多 3 万字文件内容）原先被整段拼进卡片、无行数限制地排版；现在只显示「已读取「文件名」第 a–b 字，共 N 字」。其他工具的兜底说明限 160 字（`ToolTraceSummary`），`ask_bot` 回答先截断再解析 Markdown。
- 回归测试 `LongReplyCollapseTests`（真实形状样例 + 新阈值 + trace 说明，未运行）。规格 [long-reply-collapse](specs/long-reply-collapse.md)，根因见 [known-issues](testing/2026-10-14-known-issues.md)。`frontend/web` 未动。

## 2026-10-15 · 私聊长回复折叠

- iOS 私聊：Bot 回复超过 1500 字或 40 行时默认收起，气泡只渲染截断预览（≤ 300 字 / 10 行，底部渐隐），点「展开 / 收起」切换。收起时不解析、不排版全文 Markdown，缓解超长回复导致的卡顿。展开状态按消息保留到离开对话页。用户消息与流式中的回复不折叠。
- 阈值与截断（行尾优先、不切代码块、不切字素）抽为 `VeraBotCore.LongReplyCollapse`，测试 `LongReplyCollapseTests`（未运行）。规格 [long-reply-collapse](specs/long-reply-collapse.md)。`frontend/web` 未动。

## 2026-10-15 · 创建群聊去掉说明文案、选择行紧凑化

- iOS `CreateGroupSheet`：去掉选择区 footer「每个群聊需要选择 2～5 个 Bot」，弹窗内不再有任何说明文案；2～5 选择校验保留（满 5 个禁用未选行、不足 2 个或超过 5 个时「创建」不可用、提交前二次校验）。`BotProductLimits.groupSelectionHint` 已删除，`BotProductLimitsTests` 仍覆盖 2～5 边界。
- Bot 选择行对齐群设置成员行与「添加成员」弹窗：头像 30、间距 10、`listRowInsets(top: 2, leading: 20, bottom: 2, trailing: 20)`。其他 UI 未改。

## 2026-10-15 · 「回到最新」按钮显隐修正

- 私聊 / 群聊：「回到最新」按钮原来显隐完全反了（贴底时显示、上滑时隐藏）。现在只在滚离底部时显示，贴底或接近底部（40pt 内）时隐藏；新消息自动跟随同样使用该判定。贴底判定抽为 `VeraBotCore.ScrollBottomDetector`，回归测试 `ScrollBottomDetectorTests`。

## 2026-10-15 · Bot 动态开场词 Phase 1

- 规格：[bot-opening-message](specs/bot-opening-message.md)。空对话开场气泡不再硬编码「石家庄天气…」功能清单。
- 后端 schema v32：`bots.opening_templates`；创建 Bot / 改人设后后台用 DeepSeek 一次生成人设模板；`POST /api/bots/{id}/opening-templates/ensure` 懒生成；失败不阻断，客户端兜底。公开字段增加 `opening_templates`、`opening_address`（记忆轻量称呼）。
- iOS：`OpeningMessageComposer` 按时段、周一/周五/周末、节假日、二十四节气、关系阶段与称呼本地组装；深夜追加「早点休息」。无 UI 布局改动；`frontend/web` 未动。
- 测试：`opening_message_test.py`（mock 模型）；Swift `OpeningMessageTests`（本 Linux 环境未跑）。

## 2026-10-15 · 对话「回到最新」按钮

- 私聊 / 群聊：列表滚离底部时，在输入栏上方右侧显示圆形玻璃「向下」按钮（仅 SF Symbol，无文案、无未读数）；点按动画滚到最新消息，贴底时淡出隐藏。规格见 [chat-continuity](superpowers/specs/2026-10-14-chat-continuity-design.md)。

## 2026-10-15 · 会话列表在正常回复后不再显示「工作暂未完成」

- iOS：服务端活动摘要会保留本代对话历史上失败/中断的任务，最新一轮完成后行状态落回旧记录，列表一直显示「工作暂未完成」与警告头像。现在最新消息有正文时按空闲处理、显示最新回复预览；只有完全没有可读消息时才显示「工作暂未完成」。内部重试阶段 `retry_wait` 显示为「正在思考」。完成动画不会在本轮失败时播放。仅改 iOS，后端未改。回归 `listRowShowsReplyPreviewOverStaleInterruptedWork`，根因见 [known-issues](testing/2026-10-14-known-issues.md)。

## 2026-10-15 · 回复中输入栏只显示停止按钮

- 私聊：回复排队或生成中，输入栏右侧改为纯停止按钮（`stop.circle.fill`，与其他停止按钮同样式），去掉转圈；点按停止本次回复，无障碍标签「停止回复」。
- 群聊：可停止时显示停止按钮；回复中但暂不可停止时显示同样式的置灰禁用停止按钮（无障碍标签「正在回复」），不再显示转圈。

## 2026-10-15 · 会话列表未读点对齐

- 未读点移入尾列、时间正下方：右缘与时间右缘对齐，垂直居中于预览行（私聊与群聊行）。

## 2026-10-15 · Bot 回复对齐、回复中输入栏忙碌态、打开即已读

- 私聊 Bot 回复：气泡、中断提示与操作行（朗读 / 👍👎）改为左对齐，短气泡不再被操作行推离头像。
- 输入栏：私聊回复排队或生成中，右侧麦克风换成忙碌态停止按钮（转圈 + 停止方块），点按停止本次回复；此时不能发送新消息，去掉「排队中 / 取消排队 / 正在回复」状态行（「等你补充 / 待你确认」保留）。群聊回复中同样禁止发送，可停止时显示停止按钮，否则显示转圈。完成或失败后恢复麦克风。
- 已读：进入对话、从后台回到前台、离开对话时把该对话全部未读回复写入本地已读队列并上报服务端（`AppState.markConversationRead`，`ConversationActivity.entryReadBatch`），列表圆点与「新」分隔线随之清除；之后只有离开期间新到的回复才会再提示。

## 2026-10-15 · Worker 环境变量、SSE 事件派发与新消息提示

- 后端：独立启动的 worker（`python -m verabot.services.chat_tasks` / `owned_tasks` / `scheduled_tasks`）此前不读取 `backend/.env`，缺少 `DEEPSEEK_API_KEY` 时每条私聊回复都失败，并显示「⚠️ 模型没有返回内容（已自动重试）」。新增 `verabot/core/envfile.py`，三个入口在导入配置前加载 `.env`（不覆盖已导出变量），缺少 Key 时直接退出并给出提示。回归 `scripts/test/worker_env_test.py`。
- iOS：持久事件流不再用 `bytes.lines`（会丢弃 SSE 事件结束用的空行，事件一直不派发），改为按字节切行；解析器在下一事件开始时兜底派发上一事件。修复任务已失败/完成而对话仍停在「排队中 / 取消排队」。
- iOS 新消息提示：只在进入对话或从后台回到前台时，于当时第一条未读回复上方显示一次细蓝线「新」；正在看对话时到达的回复不显示；看过后再次进入不再显示。去掉头像上方「新消息」标签与「有新回复 ↓」按钮；会话列表未读数字改为小圆点。规格见 [chat-continuity](superpowers/specs/2026-10-14-chat-continuity-design.md)。

## 2026-10-14 · 群成员移除确认与动画

- 修复左滑 `role: .destructive` 导致确认前行被系统移走的问题；改为非 destructive + 显式 `.tint(.red)`，确认「移除」后才调 API，并以 `withAnimation` 从数据源移除该行。取消保留原行。
- 添加成员 sheet：去掉底部说明；改为多选确认「添加」；顺序 POST，部分失败保留已成功成员并提示。规格变更记录见 [group-member-edit](superpowers/specs/2026-10-14-group-member-edit.md)。
- 添加成员 sheet：列表行对齐群设置成员行（头像 30、间距 10、相同 `listRowInsets`），行高一致。
- 私聊/群聊未读分隔线：多条未读时改为浅蓝发丝线 + 居中「新」（无胶囊底）。见 [chat-continuity](superpowers/specs/2026-10-14-chat-continuity-design.md)。
- 群设置页：顶部居中群头像；去掉「群聊名称」标题；群名输入居中加粗并大一号字。
- 群聊：`await_user` 且 `missing_information` 为空时，若正文已有追问则不再把步骤标失败（校验放宽 / 有内容时 coerce）；避免完整回复下方误显示「回应暂未完成」。
- 群聊公开消息原则：编排内部失败/中断不得对用户露出；有非空正文的 bot 消息对外为 `completed`（`_public_message_status`），iOS 仅在无可用正文时显示「回应暂未完成/再试一次」。

## 2026-10-14 · 群聊成员增删（PR #37，已合入）

- 群设置页支持添加 / 移除 Bot 成员（Boss 参考：同卡「添加成员」、左滑 minus.circle、确认「移除 {Name}？」）。
- API：`POST/DELETE /api/groups/{id}/members`；服务端仅归属与防空群校验；产品 2～5 仍由 `BotProductLimits` UI 约束。规格见 [group-member-edit](superpowers/specs/2026-10-14-group-member-edit.md)。

## 2026-10-14 · Bot 数量限制与创建群聊 UI 跟进

- PR #35（已合入）：iOS UI 层落实账号最多 10 个 Bot、群聊创建选择 2～5 个 Bot；上限集中在 `BotProductLimits`，不改 Runtime / DB / API。规格见 [bot-limits](superpowers/specs/2026-10-14-bot-limits.md)。
- PR #36（已合入）：按 Boss 去掉助理列表「我的 Bot（n/10）」展示（保留上限校验与提示）；创建群聊页去掉底部提示卡片，说明改到选择区 footer。变更细节见规格「变更记录」。

## 2026-10-14 · 离线提示统一（PR #34，已合入）

- 各主页面统一用单个 `ConnectionNotice` / 连接横幅展示失败，避免助理页双条提示。
- `AppState.message(for:)` 对传输失败与 HTTP 5xx 返回友好文案「暂时连接不上」，未知错误为「这次没能完成，请稍后再试。」；已是中文的服务端文案原样保留。登录 / CreateBot / BotEdit / AvatarPicker / NoticeLab / 后端未改。

## 2026-10-14 · SQL 分层收尾（PR #33，已合入）

- 将 services / routes / actions 中剩余直连 SQLite 查询迁入 `backend/verabot/db/` 各 store；行为与 schema 不变。
- `sql_layer_check.py` 恢复严格：`db/` 以外出现 `.execute` 或 SQL 字符串即失败；离线 `run_offline.py` 在合入时通过。遗留说明见 [known-issues](testing/2026-10-14-known-issues.md)。

## 2026-10-14 · 对话持续执行与本地通知（集成分支，未合并）

- 普通私聊改为持久回复任务：离开页面不取消已接收的工作，列表显示工作状态和未读。
- 提醒继续由本机预排程；Bot 回复和任务结果写入可增量同步的通知事件。不接 APNs。
- schema v31。验证范围见 [集成记录](testing/2026-10-14-integration.md)。

## 2026-10-13 · 主 Bot 第一版（本地main，未发布）

- 账号级主Bot、独立主动授权/预算、统一徽章和快捷入口。
- 明确交办/周期任务管理，持久步骤、求助回答、有限咨询、停止/继续/移交与SSE快照。
- MCP冻结确认、权限/版本复验、加密结果检查点和未知动作防重放。
- 来源与验证边界见[交付记录](testing/2026-10-13-primary-bot.md)；2026-10-14已合入本地main（b68dfc4）；不包含APNs/生产部署。


## 2026-10-13 · 主 Bot 实施前复核与计划

- 确认群接力已经合入本地main，基线`b81caed`/schema v25；原开发库与真实交互验收独立跟踪。
- 定时任务36项、群咨询/交接10项在新基线通过；没有全套/真实模型/设备验收。
- 用户已确认主Bot首版，新增具体P0–P3计划，待审阅后编码；不将计划文档标为产品实现。

## 2026-10-13 · 群聊意图路由与任务交接（隔离 worktree，未部署）

- 移除群聊默认回应者。每条输入建立持久任务；按群内上下文选择 Bot，信息不足时动态选澄清负责人并保持同一位，Bot 可咨询其他成员后返回，或明确交接任务。
- 新增协议 v2 提交回执、幂等 UUID、快照/事件游标、停止/继续/失败步骤重试和单进程后台 worker；旧群写入口返回 426，历史仍可读。
- iOS 接入 v2 输入、事件观察、澄清状态、多人点名顺序、消息回复、离开后恢复和旧偏好清理；SQLite 原子保存执行快照和消息。
- 尚未合并、推送或迁移正式数据库。自动测试和假服务通过不代表真实模型或设备交互验收；见 [实现记录](testing/2026-10-12-group-intent-and-handoff.md)。

## 2026-10-13 · 功能盘点与主 Bot 方案文档

- 校正 README 的 MCP/记忆“未实现”描述，同步主线 v23 定时任务、群附件/语义路由及独立群 v2 工作树进度。
- 明确排程恢复与业务步骤恢复、私聊工具与后台授权、现有通知与 APNs 的区别；保留真实模型和设备验收边界。
- 当前 main 定时任务 36 项、群路由 2 项离线回归通过；本轮没有重跑全套或交付新设备包。
- 新增主 Bot 接入讨论稿、修改范围/粗估和验收条件；仅文档更新，未实现主 Bot。

## 2026-10-12 · 全工作区与定时任务整合

保存全部未提交代码并整合到本地 main；加入 iOS SQLite 离线列表/历史/草稿，以及服务端定时任务 API、持久队列和独立 Scheduler/Worker。迁移统一 v23；修复同步快照一致性、离线删除和账号作用域等整合问题。代码集成提交 `eb67ff9`；iOS build 2026101201 已安装模拟器与备机，模拟器已启动；备机用户解锁后启动成功。设备交付、当前测试结果和验收边界见 [本轮记录](testing/2026-10-12-main-integration.md)。

## 2026-10-12 · 群聊 @ 输入与键盘联动修复

点击成员后在光标处插入带专用字色的 @ 标记；修复键盘焦点、光标保持、中文组合输入、成员列表点击区域以及发送失败后的标记保留。列表采用液态玻璃样式，最多显示五项，超出可滚动。25 项编辑器回归通过，用户确认本轮验收通过，详见 [检查记录](testing/2026-10-12-group-mention-keyboard.md)。

## 2026-10-12 · 十一种头像形状正式接入

创建和编辑 Bot 增加锁定形状选择与预览；形状通过现有外观模板字段保存，正式头像统一复用表情、执行状态与天线。照片头像继续优先。皮肤与配饰仍保留实验室。详见 [形状落地](design/2026-10-12-avatar-shapes-production.md)。

## 2026-10-11 · Bot 群聊 G3

新增隔离模拟提供者服务与真实 socket 联调脚本，覆盖顺序发言、停止、失败重试、断流恢复及清空/删除；记录分项验收证据。 [G3 验证与验收交付](testing/2026-10-11-bot-group-chat.md)。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/)，版本号遵循 [SemVer](https://semver.org/lang/zh-CN/) (见 [CONTRIBUTING.md](../CONTRIBUTING.md))。时间为北京时间 (UTC+8)。

## [Unreleased]

### 全工作区整合 — 2026-10-12

- iOS 离线持久化、群聊交互/附件/路由、头像形状、朗读与通知资料，以及服务端定时任务纳入 main。
- 修复离线同步并发、删除、账号作用域和恢复终态保存问题；迁移统一 v23。验证与设备证据见 [交付记录](testing/2026-10-12-main-integration.md)。

### 群聊正式功能 — 2026-10-11

- 移除首页群聊预览入口、模拟数据/回复与预览页，启动直接进入正常账号流程。
- Debug/Release 都使用持久群聊 API；建群、默认回应、点名、顺序讨论、停止与单成员重试保持正式链路。

### iOS 对话朗读生命周期 — 2026-10-11

- 返回列表、进入后台 / 锁屏及开始录音时停止朗读，再次进入不自动恢复；滚动和临时弹层继续播放。
- 主动停止、自然结束及取消时释放朗读音频会话，恢复其他音频；旧完成 / 取消回调不再清除新消息或同一消息重播的状态。
- 规则、实现决策与待验收用例见 [对话朗读生命周期](design/CHAT_SPEECH_PLAYBACK.md)。

### 群聊 G2 顺序发言与正式接线 — 2026-10-11

- 新增群模型执行、独立上下文、预算/超时、停止、断线/重启恢复和原问题单人重试；真实 iOS 群列表、创建、聊天、历史与管理接入 API。
- 保留 G0 Debug 预览；正式功能使用服务端消息身份与成员快照，不生成假回复。既有私聊模型调用默认参数保持兼容。
- 后端 74/74、Swift 211 项与模拟器构建通过，尚未部署生产或验收真实模型体验。详见 [G2](testing/2026-10-11-bot-group-chat-g2.md)。

### 群聊 G1 数据与协议基础 — 2026-10-11

- 独立工作树新增 v20 群存储、管理 REST、历史分页、成员快照和轮次幂等/并发限制；不写私聊历史。
- 新增 Swift 群协议、SSE parser/reducer 与账号代次检查；401 重发保持 UUID，409 查询原轮次恢复快照。
- 临时库测试 13/13、相关后端回归 45/45、Swift 206/206 和模拟器构建通过。真实发言及正式 UI 尚未接入；详见 [G1 记录](testing/2026-10-11-bot-group-chat-g1.md)。

### 群聊 G0 界面预览 — 2026-10-11

- 独立工作树新增 Debug 群聊预览：创建、独立头像与消息、点名、顺序讨论、停止、失败重试、重命名和清空/删除确认。
- 明确标记模拟数据，使用内存示例，不接后端、不调用模型、不修改真实 Bot；正式群聊尚未实现。
- 预览入口：助理页「＋ → 群聊预览」，或 Debug 启动参数 `--group-chat-preview`。

### 进度与验收文档对齐 — 2026-10-11

- 记忆 M3/M4 用户验收通过；M3-05 委派复测通过；M5-02/03、记忆卡片缺失及回复省略问题复测通过，M5-04 服务层降级验证通过。
- MCP M3 确认卡片模拟器实际操作通过：显示、取消、重启恢复、执行一次、重复确认拒绝、协作记录。按用户指定标准标记通过，布局不纳入此次验收。
- 校正 Keychain / 刷新 / 登录限流、本地通知、图片附件、schema v19 和未推送提交状态；保留历史测试快照，不将旧记录当作当前全量回归。完整盘点见 [项目盘点](testing/2026-10-11-project-inventory.md)。


### iOS 游乐场游戏助手 — 2026-10-10

- 游乐场大标题左侧与右侧 Bot 头像放在同一行，点击头像打开游戏助手对话。
- 首次点击为当前账号创建游戏助手预设，之后复用已有 Bot；本机按服务器和账号保存关联 ID，修改昵称后继续保留关联，已删除时重新创建。同名 Bot 保留原有配置。
- 助手支持规则讲解、玩法推荐和分步提示，沿用现有模型对话与历史记录；局面信息由用户提供，不自动读取或操作游戏。助手作为普通 Bot 显示在列表中，遵循数量上限和默认权限。

### iOS 创建页与协作记录显示 — 2026-10-10

- 创建 Bot 页移除底部工具与委派默认状态的说明分区。
- 协作记录标题使用当前 Bot 名称，协作双方只显示实际名称，避免将头像形象名称（如「V豆」）显示为 Bot 身份。

### 修复 — iOS 登录结果被丢弃 — 2026-10-10

- 修复未登录时点击登录后仍停留原页的问题：登录 / 注册 / 验证码请求只检查会话代号是否变化，不再要求已有登录令牌。
- 登录成功可进入首页，密码错误与连接失败可正常显示提示；账号数据请求仍要求有效登录态，换账号后继续丢弃旧请求结果。
- 原请求 401 后的刷新 / 重试检查会话代号，换账号后不借用新账号令牌重试旧请求。
- 后端账号读写使用即时事务，修复并发错误计数覆盖、重复注册内部错误、刷新令牌多次消费；注册密码超过 bcrypt 的 72 UTF-8 字节上限时返回可读的 422 提示。
- 新增未登录请求与会话切换回归检查；验证记录见 [登录恢复排查](testing/2026-10-10-login-recovery.md)。

### iOS Bot 创建 / 详情头像布局 — 2026-10-10

- 两页头像行去掉额外底部内边距，保留分区间距；详情页昵称/标签之间的系统分隔线按行内容两侧边距对齐。
- 创建 Bot 页将头像单独放在顶部，昵称和标签移到头像下方；Bot 详情页头像单独展示，昵称与标签共用一个分区，人设恢复独立分区。
- 创建与详情页共用一张选色卡，合并原头像主色与 Bot 选色卡；移除新版机器人相关说明，头像菜单可选择相册照片或恢复默认形象。
- 两页昵称和标签输入居中，昵称使用原来的常规字号，去掉标签标题和昵称必填提示；人设恢复到选色卡下方的独立分区。

### iOS 头像实验室入口调整 — 2026-10-10

- 调试页移除旧版头像实验室入口，只保留新版实验室；入口和页面标题统一为「头像实验室」。

### iOS 对话页更多按钮 — 2026-10-10

- 对话页导航栏右上角新增三点「更多」按钮，沿用系统原生圆形工具栏按钮样式；当前为空操作。

### 新增 — 聊天文件附件 — 2026-10-10

- iOS「＋」菜单启用系统文件选择器，保持图片和拍照入口；支持 PDF、TXT、MD、CSV、DOCX、XLSX，单文件 10 MB、每条消息最多 1 个附件。
- 后端 schema v19 增加私有原文件与文本 sidecar 存储、安全抽取和 `read_file` 按需分段能力；iOS 增加文件卡片与 Quick Look。设备级和真实模型验收仍待完成。
- 扫描件 OCR、PPTX、多附件、Share Extension 和 Web 文件附件不在首期范围。

### 新增 — 记忆成长 M5 — 2026-10-10

- 新增可选本地 BGE-small-zh 向量索引与关键词 / 语义混合召回；依赖缺失或推理失败时回退关键词。
- 委派记忆共享按双方权限、记忆状态与敏感度过滤；成功委派的反馈可产生有限分类提示，不会修改权限。
- 迁移顺延为 v19（v15 Bot 外观、v16 M3、v17 M4、v18 M5、v19 文件附件）；保留既有记忆任务、建议与月度回顾数据。
- 本次只新增后端 M5 能力，没有新增 iOS / Web 界面。M5 分支既有自动验证记录保留，主线整合后尚未重跑。

### 新增 — 记忆成长 M3 / M4 — 2026-10-10

- M3 隐式候选、主动建议与快捷提问；候选经用户确认后才进入记忆，建议不会自动改动提醒或委派权限。
- M4 Bot 成长统计、月度回顾、JSON 导出与回答记忆引用；回顾只使用安全聚合和符合条件的记忆。
- 数据库迁移顺序校准：当前 v15 为 Bot 外观，M3 使用 v16，M4 使用 v17，保留既有 v14 记忆任务迁移和数据。
- iOS 增加建议卡片、成长与月度回顾、记忆导出、引用查看；Web 仍冻结。M3/M4 自动检查与模拟器构建结果沿用分支记录，M3-01～05、M4-01～05 已于 2026-10-10 由用户验收通过。

### 俄罗斯方块 Bot 陪玩首版 — 2026-10-09

- 选择现有 Bot，记住伙伴；棋盘上方显示形象与简短回应，消行有表情反馈。
- 主动回应每局最多三次、至少间隔 30 秒；可切换安静陪伴。点头像暂停聊天，可自由输入或一起看看局面；离开、重开、切换伙伴后丢弃旧回应。
- 新增鉴权陪玩接口，复用服务端模型调用与用量预算，无工具执行、无长期记忆写入。网络失败仍能本地玩。验证见 [陪玩验收](testing/2026-10-09-tetris-companion.md)。

- iOS 登录：成功登录后用本机钥匙串按服务器记住账号／密码，下次自动填回；可从登录页清除，验证码不保存。

### iOS 启动、连接提示、登录与外观同步 — 2026-10-09

- 冷启动增加本地 3 个 Bot 的欢迎动画，约 1.5 秒；后台返回不重复，减少动态效果时显示静态角色。
- 首页区分加载、空列表和连接失败：首次失败显示 Bot 默认页，已有内容保留并显示紧凑提示；重试复用等待动作，断网 / 超时复用警告，服务不可达 / 5xx 复用系统错误动作。账号错误与网络错误分开，网络失败不会清除登录态。
- 登录页改为 Bot 小队欢迎 + 简洁表单，默认邮箱密码，其他登录方式展开；服务器编辑、健康检查、错误详情与构建信息移到右上角调试入口。登录请求期间禁用调试修改，迟到的旧服务器 / 旧会话响应不再应用。
- 修复已打开弹窗停留在旧主题：使用所属窗口同步浅色 / 深色 / 跟随系统，覆盖 SwiftUI 和 UIKit 呈现；内置网页品牌色同步刷新，不通过重建页面切主题。
- 检查范围、复现证据和验收结果见 [本次验收记录](testing/2026-10-09-startup-connection-appearance.md)。保留工作区已有头像 / 游乐场改动；未改后端和 Web。

### 新增 (Added) — MCP M4 OAuth 2.1 + Gmail 授权入口（不升 schema）

- **后端**：用 MCP SDK OAuth provider 执行 PRM / 授权服务器发现、PKCE S256、`resource` 与 `iss` 校验；OAuth state 按用户 / 服务绑定、加密保存、一次性消费并过期。Token 与客户端信息按 issuer 隔离并 Fernet 加密；支持刷新、scope 不足状态、撤销和本地断开清理。新增授权 start / callback / cancel / disconnect API，响应不包含 Token。
- **iOS**：Gmail 插件详情增加连接 / 重新授权 / 扩权 / 断开及账号和 scope 状态；用 `ASWebAuthenticationSession` 接收授权回调。连接前说明 Google 登录及 DeepSeek 数据流；未同意数据使用说明时不开放连接。
- **范围**：当前只提供 Gmail OAuth 连接入口，未开放邮件工具。Web 冻结。真实 Google 登录需测试客户端、测试用户和 Workspace Developer Preview。
- **验证**：OAuth 假服务器用例、MCP / 插件回归通过；Kit `swift test` 157/157；iPhone 17 模拟器构建 / 启动，实测登录、安装 Gmail、详情说明及默认关闭的 DeepSeek 同意门控。真实 Google 浏览器授权待手工验收。

### 新增 (Added) — MCP M3：通用 HITL 确认卡片（复用 schema v7 `pending_actions`，不升版本）

- **后端**：按 [MCP_CAPABILITY.md](design/MCP_CAPABILITY.md) §7 / §15 M3。非只读 MCP 工具（及 `confirm_policy=always` 的只读工具）不再直接拒绝，而是冻结参数写入 `pending_actions`（Fernet，`VERABOT_ACTION_ENC_KEY` / `data/.action_key`，默认 15 分钟过期）、审计 `mcp_action_requested`，工具结果 `{status:pending_confirmation, action_id, …}`，SSE 另发 `confirmation_required`。`POST /api/pending-actions/{id}/confirm|cancel`、`GET /api/pending-actions`；确认后执行冻结参数、写结果摘要进对话历史、**不**自动再调 LLM。确认前工具变更 / 服务断开 → 409；过期 → 410；他人 → 404；重复 → 409。确认接口在事务内原子检查 TTL 并条件更新状态，避免过期时间边界竞态。单轮待确认上限 `VERABOT_MCP_PENDING_PER_TURN`（默认 2）。`PATCH /api/mcp/tools/{id}` 仅接受 `always`/`default`，拒绝 `never`/`auto`（MCP-13）。跨服务读→写时卡片带警告。协作记录新增 `GET /api/bots/{id}/tool-calls`。过期 pending 由调度器标 `expired`（不再直接删）。
- **iOS**：`ToolConfirmationCard`（服务 / 工具 / 风险 / 参数表 / 警告 / 执行·取消）；`ChatEvent.confirmationRequired`；Kit `PendingAction` / `ConfirmationRequired`；打开对话恢复 pending；协作记录页增加「工具调用」分段。
- **Web 冻结**：无确认卡片界面。
- **测试**：`mcp_m3_test.py` 23/23（MCP-10~13、过期、pending 上限、跨服务警告、契约键）；MCP / 插件 / 并发回归通过；Kit `swift test` 156/156；iPhone 12 Pro Max 目标 `xcodebuild` 编译与签名通过。2026-10-11 确认卡片已按用户指定的模拟器标准验收通过，见 [专项记录](testing/2026-10-11-mcp-m3-simulator.md)。

### 新增 (Added) — 记忆 M2：滚动摘要 + 风格校准（schema v14）

- **后端**：按 [MEMORY_GROWTH.md](design/MEMORY_GROWTH.md) §11.1。新表 `memory_jobs`、`message_feedback`（`SCHEMA_VERSION=14`，幂等）。对话落库后入队摘要；进程内单 worker（启动恢复 `running`→`pending`，关闭时取消）。窗口外未覆盖消息满 20 条才压缩成每个 Bot 一条滚动摘要（≤ 400 字，不经确认）；用量 `kind=memory`；预算 ≥ 90% 或积压不够则 `skipped`；失败最多再试 2 次。清空对话删除摘要、保留已确认记忆。用户消息命中「再短一点」等短语，或 14 天内 3 次 👎 `too_long`，只生成 style 提议。`POST / DELETE /api/messages/{id}/feedback`；消息列表回显 `feedback`。审计和日志不写正文。
- **iOS**：Bot 回复气泡在朗读旁增加 👍 / 👎（👎 选原因，选中为填充图标，再点撤销）；风格提议用既有确认卡片，标题「以后都这样回答吗？」。
- **Web 冻结**：没有反馈和摘要界面。
- **测试**：`memory_m2_test.py`（MEM-40~49）。iOS 未在云端编译。

### 变更 (Changed)

- **iOS · 设置面板改为悬浮卡片**（Boss 2026-10-05，取代同日的 60% 屏高）：四角圆角 36、距左右下边 8pt，顶端停在首页导航栏下方（约 88% 屏高，导航栏一行仍露出并变暗）；左上角圆形 xmark 关闭按钮，无标题；仍为自定义 BottomPanel（`topInset` 取代 `heightFraction`），不用系统 sheet。

### 修复 (Fixed)

- **iOS · 提醒编辑页「日期」「时间」各出现两行**（Boss 2026-10-04 验收 R1 时发现）：开关行和选择器行用了同一个标签「日期」/「时间」，看起来像重复行。两个 `DatePicker` 改用 `.labelsHidden()`（含义由上方开关行提供），并设区分开的 `accessibilityLabel`（「提醒日期」「提醒时间」）避免 VoiceOver 里重复播报；两个开关同时改用全 App 统一的 `CompactToggle`（85% 青绿，THEME-03 / UI-23 此前未覆盖本页）。设计稿 §10.2 已同步。仅 iOS；无新测试（纯视觉）。
- **MCP 内嵌资源正文丢失**（Boss 2026-10-05）：GitHub `get_file_contents` 等工具把文件正文放在 `{type:"resource", resource:{uri, mimeType, text|blob}}` 里，`result_text` 只读块顶层的 uri/name，正文被丢掉，模型只看到「下载成功 + SHA」。现在内嵌资源输出 `[资源] uri mime` 标题加正文；`blob` 为文本类 mime 时解码，否则只注明类型与字节数；总长度仍由 `VERABOT_MCP_MAX_RESULT_CHARS` 截断。测试 MCP-RES。

### 变更 (Changed)

- **iOS · 设置页改为自定义底部面板**（Boss 2026-10-04）：首页点头像不再 push 设置页，改为圆角卡片从底部以弹簧动画弹起（约 70% 屏高，背景变暗），点空白处或下拉顶部把手关闭；面板内自带 NavigationStack，用量 / 插件 / 调试等二级页照常 push。新增通用修饰符 `.bottomPanel(isPresented:heightFraction:content:)`（`Core/UI/BottomPanel.swift`，fullScreenCover 承载以盖住 Tab 栏，关闭系统动画、透明背景）。仅 iOS，后端与 Web 未改。

### 新增 (Added) — 需授权 MCP 连接器 P1（schema v13）

- **后端**：按 [MCP_AUTH_CONNECTORS_PLAN.md](design/MCP_AUTH_CONNECTORS_PLAN.md) v1.0（Boss 2026-10-04 决定 D1–D11 全部按建议）实现 P1：授权抽象 `AuthProvider`（`none` / `static_bearer`，`services/mcp/auth.py`）；目录新增 GitHub（`/mcp/readonly` + `X-MCP-Readonly / Toolsets / Lockdown`，15 个只读工具白名单）与 Linear（`/mcp/readonly`）两个只读连接器；`PUT / DELETE /api/plugins/{id}/credential`（只接受本机回环或 HTTPS，校验后 Fernet 加密写 `mcp_credentials`，新密钥 `VERABOT_TOKEN_ENC_KEY` / `data/.token_key`）；`needs_auth` 状态流（无凭据不调度同步、401 回到 `needs_auth` 不重试不计熔断、网络错误 `network_unreachable` 保留凭据、工具级越权 `mcp_permission_denied`）；日志脱敏（`core/log_redact.py`）；D7「接受工具更新」`POST /api/plugins/{id}/accept-tool-changes`；迁移 v13（`mcp_credentials` 加 `kind / token_hint / last_verified_at`，`mcp_servers.auth_error`，新表 `mcp_oauth_clients`）。`.env` 未改，新变量只写进 `.env.example`。新测试 `connector_test.py`（CONN-01~12、SEC-01、D7、CONTRACT）；其他套件的版本断言改为 13。
- **iOS**：插件详情新增「账号」分组与令牌 sheet（系统 `Form` + `SecureField`，Keychain 暂存、上传成功即删除）、「工具更新」分组（D7）；目录显示「需要令牌」；Bot 编辑页提示「需先在插件页连接」；Kit `Plugin` 新可选字段、`needs_auth` 文案、`authErrorText`，Trace 错误文案 `mcp_auth_required / mcp_permission_denied`，GitHub 工具中文名；`VeraBotAPI.setPluginCredential / deletePluginCredential / acceptPluginToolChanges`。
- **Web 落后**：`frontend/web` 冻结，没有连接器界面。

### 修复 (Fixed)

- **iOS · Bot 开始回复时开头出现黑色竖条**：根因是 `MessageRow.swift` 在生成中给正文追加光标字符「▍」(U+258D)，首个 token 到达前气泡里只有这个字符，显示成一根黑色竖条。去掉该字符；等待首个 token 时气泡里显示系统 `ProgressView`，之后正文照常逐字出现。仅 iOS。
- **iOS · GIF 在发送前的预览里不动**（Boss 2026-10-03 模拟器验收附件 P1 第 2 项：对话里的 GIF 会动，预览时不动）：输入栏上方的待发送缩略图用 `UIImage(data:)` 解码，只得到第一帧，又用 SwiftUI `Image` 显示（SwiftUI `Image` 本来也不播放 GIF）。修复：`ComposerAttachmentModel` 在后台压缩之后，用对话气泡同一个 `AttachmentImageDecoder` 逐帧解码，新增 `isGIF`；`ComposerAttachmentChip` 对 GIF 改用气泡同一个 `AnimatedImageView`（`UIImageView` 播放，系统「减弱动态效果」打开时只显示第一帧）。解码挪到后台线程，静态图同样受益。Quick Look 全屏查看：原来就写原图字节（不重新编码），但扩展名取自服务器返回的 `mime`；现改为按文件头取（`AttachmentLimits.fileExtension(for:)`：GIF → `.gif`、PNG → `.png`、其他 `.jpg`），保证交给 Quick Look 的一定是带 `.gif` 扩展名的原 GIF（顺带修正透明 PNG 被写成 `.jpg`）。后端未改。Kit 新增测试 `previewFileExtension`（ATT-K-02）。
- **iOS · 点通知后切到后台崩溃**（PR #9 合并复核时的修复 `ccbd00c` 引入；模拟器崩溃报告 2026-10-03 20:22、20:37，`SIGABRT`）：`NotificationCoordinator` 用的是 async 版本的 `UNUserNotificationCenterDelegate` 方法，编译器生成的 `@objc` thunk 在协作线程池里调用系统的 completionHandler，UIKit 随后在该线程执行 `-[UIApplication _updateSnapshotAndStateRestorationWithAction:]`，触发「必须在主线程」断言。修复：改用 completionHandler 版本（`willPresent…withCompletionHandler:` / `didReceive…withCompletionHandler:`），在 `nonisolated` 方法里取出 Sendable 的值，`Task { @MainActor in … }` 里处理完，再在主线程调用 completionHandler；所有 `AppState` / UIKit 操作都在主线程。
- **iOS · 语音输入失败后音频会话不释放（疑似闲置时 CPU 196% 的原因）**：`SpeechEngine.start()` 先激活 `AVAudioSession`、装 input tap，`engine.start()` 抛错或无输入时直接抛出，session 和 tap 留着，CoreAudio IO 循环一直空转（旧进程日志 21:05–21:15 持续 `HALC_ProxyIOContext::IOWorkLoop: skipping cycle due to overload`）。修复（`Services/Speech/SpeechInput.swift`）：启动各步放进 do/catch，失败时完整清理再抛出；清理幂等（只释放确实占用的 tap / session，`engine.stop()`、`removeTap(onBus: 0)`、`setActive(false, options: .notifyOthersOnDeactivation)`）；新增 `cancel()`（停止采集并取消识别任务）；识别回调带轮次号，上一轮的迟到回调不会拆掉新一轮的音频。`ChatView` 消失和进入后台（scenePhase `.background`）时调用 `cancel()`。196% 未能复现，修复后待 Boss 观察。
- **iOS · 对话页底部没有滚动边缘效果（Scroll edge effect）**：消息滚到浮动 Liquid Glass 输入栏下方时没有顶部导航栏那样的渐隐模糊。原因：输入栏挂在 `safeAreaInset(edge: .bottom)` 上，iOS 26 里 safeAreaInset 的内容不参与滚动边缘效果。修复：`Theme` 新增 `bottomBar { }`，iOS 26 用 `safeAreaBar(edge: .bottom)`（系统在栏后方绘制底部滚动边缘效果，同工具栏），iOS 17–25 回退 `safeAreaInset`；`ChatView` 改用它。纯系统默认（`scrollEdgeEffectStyle` 保持 automatic），不手写渐变 / 模糊；键盘避让逻辑不变。
- **提醒 R1 · iOS 编不过、Kit 测试编不过**（PR #9 合并复核，Boss 的 Mac，Xcode / Swift 6）：`NotificationCoordinator` 的 `UNUserNotificationCenterDelegate` 方法改为 `nonisolated`，先取出 `Sendable` 的 `NotificationTap`，再回主 actor 执行 `handleWillPresent` / `handleResponse`（原来跨 actor 传非 Sendable 的 `UNNotification`，Swift 6 严格并发报错）。`ReminderTests` 构造参数顺序改正（`repeatLabel` 在 `status` 前）；`NotificationSchedulerTests` 断言改为 `allSatisfy { $0.repeats }`。`backend/requirements.txt` 恢复「由 uv.lock 导出」的文件头。修复后 `swift test` 140 通过、`xcodebuild` 成功；模拟器上本地通知按时弹出，「完成」「稍后 10 分钟」可用，免打扰时段内提醒照常弹出（D8）。
- **插件 · 卸载时进行中的调用要等满 MCP 超时**（PR #7 合并复核发现，`PLG-14` 在 Boss 的 Mac 上失败）：卸载会关掉池里的 httpx 客户端，但 macOS 上关闭套接字不会唤醒另一线程里阻塞的读取，进行中的调用要等 15 s 超时才返回 `plugin_uninstalled`。`services/mcp/service.py` 新增 `_interruptible`：单次调用放到后台线程，每 0.1 s 检查服务行，没了就立刻按「已发出」返回（只读 → `plugin_uninstalled`，非只读 → `result_unknown`，规则不变），后台线程结果丢弃。`plugin_test.py` 全部通过（PLG-14 卸载 < 0.5 s 返回）。
- **MCP · 后台同步把「已停用」改回已连接 / 错误**（PR #11 拆分时在 `mcp_test` MCP-06 偶发失败中发现；box 压满 CPU 时 main 15 次失败 2 次，Boss 的 Mac 上 10/10 通过）：`services/mcp/sync.py` 的 `_sync_body()` 先读服务行、再按读到的状态写结果。用户在「读完、写之前」停用，同步结果就会覆盖 `disabled`。共有三个窗口：成功分支（改回 `connected`，最严重：已停用的服务重新出现在模型可用的工具里）、失败分支（改成 `error`）、未配置地址分支（改成 `error`）。`schedule_sync()` 后台线程兜底的「同步失败」写入也有同样的问题。
  - 修复：`db/mcp_store.py` 新增 `update_server_unless_disabled()`，检查和写入放在同一条 SQL 里（`UPDATE … WHERE id=? AND user_id=? AND status!='disabled'`，返回是否写入）。上面四处写入都改用它。没有写入（已停用）时调用新的 `settle_disabled_sync()`，把 `sync_status` 从 `syncing` 收回 `pending`，与 `_sync_body()` 开头「已停用」分支的处理一致；这次同步的结果（`last_synced_at`、`last_error`、`url`）不写进服务行。
  - 有意的小变化：以前停用发生在成功分支读取之前时，已停用的行会被写成 `sync_status='ok'` 并更新 `last_synced_at`；失败分支提前返回时，`sync_status` 会停在 `syncing`。现在两种情况都统一为 `pending`。`mcp_tools` 仍照常写入：停用本来就不删除工具，模型能否调用由服务 `status='connected'` 决定（`connected_tool_rows()`、`tool_router` 的 `not_connected`），所以不会让工具「复活」。熔断计数（`_record_success` / `_record_failure`）不受影响。
  - 不改 schema，不改 iOS。`status` 和 `sync_status` 的取值集合不变。
  - 测试：新增 `scripts/test/mcp_disable_race_test.py`，共 MCP-RACE-01~08。假 MCP 服务器的 `tools/list` 阻塞在事件上，测试在同步卡住时停用、再放行；「旧快照」模式让停用恰好落在读和写之间，覆盖成功、失败、未配置地址和后台意外异常四种情况，另有对照组和重新启用后的同步。修复前有 6 条失败，修复后全部通过。
- **安全 · 邮箱抢注：验证码登录认领未验证账号** (此前在账号隔离审计里按当时决定延后，本次按 Boss 选定的修法落地)：
  - 问题：未验证邮箱可以注册并正常使用。真正的主人之后用验证码登录时，`login_with_code` 只把邮箱标为已验证并进入同一个账号，抢注者的密码和已发出的访问令牌、刷新令牌仍然有效，能读到主人之后写入的私密数据。
  - 修复：认领「邮箱尚未验证」的账号时，在同一个事务里把 `password_hash` 写成空字符串 (列是 `NOT NULL`，空字符串不是合法 bcrypt，密码登录失败)、`token_version` + 1、吊销该用户全部未作废的刷新令牌、写入审计 `account_claimed_by_email_code`，然后再签发新的令牌对，并把邮箱标为已验证。认领后没有密码，只能用验证码登录。未验证账号在被认领前仍可正常使用。已经验证过的邮箱，验证码登录不改密码、不吊销其他会话。API 响应字段不变，iOS 未改。不升 schema (仍是 v9)。
  - **仍不能修**：手机号抢注。短信验证 (AUTH-M3) 之前没有持有者证明，只记为已知限制。
  - 测试：`auth_test.py` 新增 AUTH-17 (认领后抢注者密码登录 401、旧访问令牌 401、旧刷新令牌 401、主人新会话可用)、AUTH-18 (已验证账号的验证码登录不受影响)，共 18/18。见 [AUTH_REFACTOR.md](design/AUTH_REFACTOR.md) §5.2。
- **安全 · 账号隔离：HTTP 缓存与换账号竞态** (2026-10-03 隔离审计发现的漏洞 2 + 建议 #3；邮箱抢注问题按当时决定延后，已由上一条修复)：
  - 问题：iOS 所有请求走 `URLSession.shared` (默认 URLCache)，后端又不发缓存头，登录 / 刷新响应 (访问令牌 + 刷新令牌)、聊天记录、已解密的健康记忆被明文写进 `Library/Caches/com.verabot.app/Cache.db`，退出登录、换账号后仍在 (界面不显示，属于设备上的数据残留)。另外 `refreshProfile` / 头像下载只判断「有没有登录」，A 的请求在 B 登录后才回来时，可能把 A 的资料或头像写到 B 的界面上。
  - 后端：新中间件 `core/http_cache.py` (纯 ASGI，不缓冲 SSE)：所有 `/api/*` 响应 (含错误、CORS 预检、SSE) 带 `Cache-Control: no-store` + `Pragma: no-cache`；SSE 原来的 `no-cache` 换成 `no-store`。头像接口从 `private, max-age=86400` 改为 **`private, no-store`**：头像是用户照片，`/api/me/avatar` 的 URL 人人相同，不能进 HTTP 缓存；iOS 本来就按账号缓存在 `Caches/verabot-avatars`，退出时整个删除，所以不影响加载速度。`/`、`/static`、`/docs` 不变。
  - iOS Kit：新 `APITransport.session` (ephemeral，`urlCache = nil`，`reloadIgnoringLocalCacheData`，不存 cookie / 凭据)，`APIClient` (JSON、上传、头像下载、SSE 聊天) 和 `AuthSession` 刷新令牌都改用它 (可注入，便于测试)；`HTTPCachePurge` 清 `URLCache.shared` 并删除 `Caches/<bundle id>/` 下的 `Cache.db`、`-shm`、`-wal`、`fsCachedData` (Metal 缓存、头像目录不动)；`AuthSession.generation` / `isCurrent(_:)` 登录会话代号 (每次 `set` 加 1，透明刷新不变)。
  - iOS App：退出登录、登录 (含换账号) 时清缓存；升级后首次启动清一次 (标记 `vb_http_cache_purged_v1`)；启动时把 `URLCache.shared` 换成 0 容量兜底。`refreshProfile`、修改昵称、上传头像、验证邮箱在 await 回来后检查会话代号，不是同一次登录就丢掉结果；旧会话的 401 不再把新账号踢下线。`AvatarStore` 加 `epoch`，`clearAll` 之后回来的 Bot 头像下载不写内存也不写磁盘。
  - 测试：后端 `cache_headers_test.py` CACHE-01~08；Kit `CacheIsolationTests.swift` CACHE-K-01~07 (共 112 项)。模拟器：升级后 `Cache.db` 里 49 条 API 响应清零，之后 demo → boss → 手机号 → demo 切换，每一步 `Cache.db` 都没有 API 响应，界面只显示当前账号数据。见 [AUTH_REFACTOR.md](design/AUTH_REFACTOR.md) §5.1。
- **iOS · 头像实验室三处遗留**：68pt 状态角标符号过小（改为按角标直径 70% 的 `resizable` 符号，68pt 约 12.4pt）；普通 ScrollView 把预览滚出屏幕时循环不停（iOS 18+ `onScrollVisibilityChange`，离开视口就卸掉 `phaseAnimator`；离开页面 / 退后台仍停）；`reset` 不取消受阻计时（`ExecutionAvatarController` 发出 `cancelBlocked`，`ChatViewModel` 取消对应 `Task`，过期触发不再改状态）。
- **iOS · 主题改为「薰衣草 × 青绿」(Lavender Teal Duo)**：Boss 反馈上午的青绿主题 (`502e11e`) 和旧色太像、看不到薰衣草、显得老气，从三套试色里选了方案 C。薰衣草 `#D7D7FF` 家族做品牌主色，Vera 青绿 `#3D7A8C` 做第二强调色。`Color.brand` / `AccentColor` 浅色 `#6461D1`、深色 `#D7D7FF`；`brandFill` (主按钮、默认头像) `#6461D1` / `#4B48B8`；新增 `userBubble` `#D7D7FF` / `#3F3D9E` + `userBubbleText` `#1B1A3A` / 白 (用户气泡从白字实色底改为薰衣草浅底)；`brandText` `#2A2870` / `#D7D7FF`；`brandSoft` `#EEEEFF` / `#26254A`；新增 `brandAccent` (= `brandLight`、`pinTint`) `#3D7A8C` / `#5FA3B6` 和 `toggleTint` `#3D7A8C` / `#4E9AAE` (所有开关)；页面背景深色 `#0B0B14`，分组底 `#F2F2F8` / `#1C1B2E`；`prominentButtonStyle` 显式用 `brandFill`。对比度：主色白底 5.0:1、白字 / `#4B48B8` 7.2:1、深色主色 14:1。只改 `Core/UI/Theme.swift`、`AccentColor`、`MessageRow` 用户气泡，全部是系统组件。Web 未改 (冻结)。
  - 原条目 (已被替换)：**iOS · 主题色改为 Vera 青绿**：Boss 选定 Vera CLI 横幅的青绿和文字色。替换原品牌色 `#0F766E`：`Color.brand` / `AccentColor` 浅色 `#3A7485`、深色 `#548EA0`；新增 `brandFill` (白字实色底：用户气泡、默认头像，浅色 `#3A7485` / 深色 `#3D7A8C`) 和 `brandText` (浅色 `#1A2B36` / 深色 `#D7E4EE`，用于登录页标题和设置里的账号名)；`brandLight` `#548EA0`/`#5B9BB0`、`brandDark` `#2F6F82`、`brandSoft` `#E7EEF3`/`#1A3144`。数值来自 `~/Vera/src/vera/terminal/theme.py` (accent / logo / text_primary)，对比度见 [ARCHITECTURE.md](design/ARCHITECTURE.md) 主题表。系统控件样式不变；Bot 自身颜色选项与 Web 未改。
- **iOS · 首页置顶动画卡顿 + 置顶图标**：原因是先等 `PATCH /api/bots/{id}` 返回再重排 (点按后要等一次网络往返才动)，而且重排正好撞上左滑按钮收起的动画，录屏里被移动的行会空白约 0.5 s 再跳到新位置。改为乐观更新：等滑动按钮收起 (0.25 s) 后立即 `withAnimation(.snappy)` 用系统 List 行移动，再同步服务端；返回后只校正 `pinned_at` (顺序没变就不再动画)，失败时动画回滚并显示错误；同一 Bot 同步中忽略重复点按。`ForEach` 仍以 `bot.id` 为身份。新增 `BotOrdering.togglingPin` / `replacingPinnedAt` / `pinTimestamp` (与后端 `now_iso()` 同格式，本机时钟偏慢时取已有最新置顶 +1 s)。图标改为 `pin.fill` / `pin.slash.fill`：「置顶」按钮品牌色 `Color.pinTint`，「取消置顶」系统灰 `Color.unpinTint`，行内置顶标记由灰色改为 `pinTint` (出现 / 消失带缩放淡入)。后端未改。Kit 测试 94/94。
- **iOS · 首页左上角头像左边距**：隐藏共享玻璃底后头像仍按玻璃按钮内边距排版，左边距约 30pt，右侧＋按钮右边距约 16pt；iOS 26 分支左移 14pt，两侧现在都约 16pt。
- **iOS · 设置 › 账号**：去掉单独的「昵称」输入行和「保存昵称」按钮；点头像仍从相册更换，点昵称弹出系统输入框「修改昵称」(取消 / 保存，规则与接口不变)。头像和昵称是两个独立的点按区域。
- **iOS · 登录页**：Logo 由「V」字方块改为 App 图标 (新 `AppLogo` 图片集，含深色外观变体)；登录 / 注册中按钮保持品牌色，显示白色转圈 +「正在登录…」/「正在注册…」(之前按钮被禁用变灰，灰色转圈几乎看不见)，加载中不可重复提交、不可切换注册。
- **iOS · 对话里的 MCP 工具调用**：之前 Trace 标题显示 `🔧 mcp__learn__microsoft_docs_search`，下面直接铺出最长 8000 字的外部原文 (含 `<untrusted_tool_result>` 标记和转义字符)；工具自身错误时把外部原文当错误显示。现在标题为「🔌 Microsoft Learn · 搜索微软文档」，正文只显示一行「已读取外部资料（约 N 字，已截断）」，错误按 code 显示固定说明 (`VeraBotCore.MCPTraceText`)。后端 `label_for` 优先用目录里的中文名 (Learn 服务器自带英文 title，之前界面显示英文)。Kit 测试 93/93。
- **iOS · 头像实验室**：深色模式状态角标几乎看不清 (改为实色底 `avatarMarkFill` + 角色背景色描边 + 阴影)；角标挡住 V豆 顶部圆点和星点的星光 (移到右下角，尺寸 0.26)；「按状态机演示」停止后马上再开始可能两轮叠加、按钮状态错乱 (加运行令牌，手动选状态也会停止演示；演示帧事先由真实 `ExecutionStateMachine` 算好 `AvatarLabDemo.frames`)；角色固定 hex 色改为 `Theme.swift` 头像语义色 (浅色 / 深色各一套)。文档里演示顺序更正为 思考 → 委派 → 思考 → 执行 → 阻塞 → 思考 → 回复 → 完成 → 空闲。
- **工具**：新增 `frontend/ios/Tools/AvatarLabHarness/run.sh` (Mac，离屏渲染 + 检查 AVLAB-T01~T13，输出浅色 / 深色对照图)，不进 App target。iPhone 17 模拟器截图 / 录屏复测 (AVLAB-02、T14)。

### 内部重构 (Internal refactoring)

只搬代码、不改行为。全部自包含测试、依赖 :8000 端口的脚本改动前后逐条结果一致。

- **记忆服务拆出包入口**（PR #10）：`services/memory/__init__.py` 的业务逻辑移到 `services/memory/service.py`，`__init__.py` 只 re-export 原有名称，调用方不变。两处重复的 `INSERT INTO delegations`（`agents/delegation.py`、`agents/tool_router.py`）合并到新的 `db/delegation_store.insert()`，写入的行逐字段不变。
- **MCP 服务按职责拆分**（PR #11）：`services/mcp/service.py`（695 行）拆成 `presenter.py`（展示 / 序列化）、`sync.py`（并入后台同步调度 `schedule_sync` / `sync_server` / `_sync_body`）、`invoke.py`（工具调用）、`resilience.py`（重试 + 熔断、调用中的卸载检测）、`audit.py`（调用审计）。`service.py` 作为门面只留服务管理，并 re-export 原有公开名称。
- **SQL 收进 `db/*_store.py`、迁移拆成 `db/migrations/`**（后端审计第 ③ 步）：
  - services / api 里的 91 处 `execute(`（`auth` 23、`memory/repository` 15、`attachments/repo` 13、`avatars` 9、`memory/service` 8、`quota` 7、`routers/bots` 7、`users` 3、`routers/chat` 3、`bots` / `routers/voice` / `deps` 各 1）全部移到 `db/`：新增 `auth_store`、`user_store`、`memory_store`、`attachment_store`、`avatar_store`、`bot_store`、`message_store`、`usage_store`，`delegation_store` 加 `list_for_bot()` / `count_for_user()`，`repository` 加 `audit_in()`（同一事务写审计，原来三处同样的 INSERT 合成一处）。SQL 文本逐字不变（只少了这几处重复）；事务边界不变：store 函数第一个参数是调用方的连接，`db.tx()` 和中途的 `c.commit()` 留在原处。
  - 对外名字不变：`services/memory/repository.py` 与 `services/attachments/repo.py` 保留全部函数名（`repo.py` 继续负责规则、文件和事务，SQL 交给 `attachment_store`）；`services.users.USER_SQL` 仍可导入。
  - 迁移：`db/schema.py` 的 DDL 与 `init_db()` 正文按原语句顺序拆到 `db/migrations/`（`v001_base` … `v011_reminders`、`tags_coerce`、`v012_attachments`）。`schema.py` 只保留入口，re-export `SCHEMA` / `SCHEMA_VERSION` / `ALL_TOOLS_V2` / `init_db` 等；`db/attachment_schema.py` 留作兼容 re-export。schema 仍是 v12；新库和从 v1 / v2 / v5 / v10 / v11 升级的库，`sqlite_master` 与数据导出跟改动前逐字节一致。
  - 新增 `scripts/test/sql_layer_check.py`（SQL-LAYER-01/02，AST 静态扫描）：`db/` 以外出现 `execute(` 或 SQL 语句字符串就失败。目前没有例外。

### 新增 (Added)

- **iOS · 图片附件 P2：拍照**：＋ 菜单「拍照」→ 系统相机 `UIImagePickerController(sourceType: .camera)`（`UIViewControllerRepresentable` + `.fullScreenCover`，系统默认界面），拍到的图与相册选图走同一路径（`ComposerAttachmentModel` / `ImagePreparer`：每条 1 张、再拍替换、长边 2048、JPEG 0.8、不带 EXIF / GPS、上传中不能发送）；无相机设备（含模拟器）不显示该项；新增 `NSCameraUsageDescription`（中 / 英），拒绝权限时弹系统 alert「前往设置」。后端未改。保存到相册、OCR 仍待做。 新文件 `Features/Chat/CameraPicker.swift`（文件夹同步组，不改 `project.pbxproj`）；`Config/Info.plist`、`InfoPlist.xcstrings` 只加 `NSCameraUsageDescription` 一项。用例 ATT-CAM-01~03。
- **删除单条消息**：iOS 对话页长按用户 / Bot 气泡，在「复制」旁新增「删除」(`Button(role: .destructive)`，系统 `confirmationDialog` 二次确认)，只删这一条，不连带同一轮的另一条。欢迎语、正在生成的回复不显示删除。SSE `done` 新增 `user_message_id`（仅追加字段，旧客户端 / Web 忽略）；iOS 把 `message_id` / `user_message_id` 写回刚收到的回复与刚发出的用户消息，回复结束即可删除两者，不用重新进入对话。长按菜单挂在整条 Bot 回复上（气泡 + 工具卡片），只有工具卡片、没有正文的回复也能删除（无正文时不显示复制）。用户气泡原来没有长按菜单，现在与 Bot 气泡一致（复制 / 复制链接 / 删除）。后端新接口 `DELETE /api/bots/{bot_id}/messages/{message_id}` → `{ok: true}`，物理删除，按 `user_id` + `bot_id` 限定，他人 / 不存在 / 不匹配一律相同的 404；引用该消息的记忆、通知、提醒按既有外键 / 触发器置 NULL，**已提取的记忆不删除**。无 schema 变更（随 main 为 v12，本功能不升版本）。iOS `VeraBotAPI.deleteMessage(botID:messageID:)`。测试：`message_delete_test.py` 10/10（含带图删除 MSG-DEL-10）、`attachments_test.py` ATT-17 改为走接口、`MessageDeleteTests` 3 个。带图消息（v12）：同一事务删 `attachments` 行，提交后立即删除原图、缩略图（GIF 另有第一帧），与清空对话同序（设计稿 Q12）。Web 未接入（见 STATUS 已知限制）。
- **图片附件 P1（schema v12，在 v11 提醒 R1 之后）**：按 [ATTACHMENTS_DESIGN.md](design/ATTACHMENTS_DESIGN.md) v1.0 + [ATTACHMENT_STORAGE_RESEARCH.md](design/ATTACHMENT_STORAGE_RESEARCH.md) 实现，范围只有图片。`frontend/web` 未改（冻结）。
  - 数据：新表 `attachments`（`db/attachment_schema.py`；`storage_backend` 默认 `local`、`storage_key` / `thumb_key` 相对路径、`caption` / `caption_status`、`status` pending / attached、`expires_at`），`message_id` / `bot_id` / `user_id` 级联删除，索引 `idx_att_user`。`SCHEMA_VERSION = 12`，迁移 v11 → v12（已 rebase 到含提醒 R1 的 main `f9e39c6`），放在 v11 提醒迁移之后。
  - 存储（`services/attachments/store.py`）：薄接口 `AttachmentStore` + `LocalStore`；`DATA_DIR/attachments/u<user>/<id 前 2 位>/att_<id>.<ext>`，缩略图 `_thumb.jpg`，GIF 另存第一帧 `_still.jpg`（给模型）；目录 0700、文件 0600；tmp → fsync → `os.replace`，插库失败删文件；读取前 `resolve()` 必须在根目录内（防路径穿越）。
  - 处理（`images.py`，Pillow，无新依赖）：按文件头识别 JPEG / PNG / WebP / GIF / HEIC（HEIC 仅装有 pillow-heif 时），其他 415；单张 ≤ 10 MB（413）、≤ 4000 万像素（400）、每人每天 50 张（429）、每人 500 MB（413）。`exif_transpose` → 长边 2048 → JPEG q85（不写 EXIF，保留 ICC）；带透明 PNG 保持 PNG；缩略图 320 px q75。GIF 原样保存全部帧，只去掉注释块和 NETSCAPE / ANIMEXTS 以外的应用扩展（XMP 等），每边 ≤ 2048、≤ 500 帧。
  - API（`api/routers/attachments.py`）：`POST /api/attachments`（multipart `file`，可选 `bot_id`，201）、`GET /api/attachments/{id}`、`GET .../content`、`GET .../thumb`（`FileResponse`，`Cache-Control: private, no-store`、`X-Content-Type-Options: nosniff`）、`DELETE /api/attachments/{id}`（只删未发送的，已发送 409）。他人 / 不存在 404，文件丢失 410「图片已删除或无法加载」。不用签名 URL。`POST /api/bots/{id}/chat` 增加 `attachment_ids`（最多 1 个，多了 422；有图时 `message` 可为空）；发送前校验归属 / 状态 / 过期 / Bot（404 / 409 / 410 / 422，都不调用模型）。`GET /api/bots/{id}/messages` 每条增加 `attachments`。
  - 看图与召回（`vision.py`，runtime 只加少量调用）：本轮 user 消息为 `[text, image_url(base64)]`，GIF 给模型第一帧 JPEG（Boss 2026-10-03 决定，替代设计稿「原样发 GIF、出错改第一帧」）。回复 `done` 之后用一次无工具调用生成 ≤ 200 字中文描述存 `caption`（用量记 `caption`）。之后的轮次历史里旧图只发「[图片 att_x：描述]」；用户回指旧图时重发原图：模型调用新工具 `view_image`（`kind="attachment"`，只在对话里有图时暴露，不进 `allowed_tools`，被委派时禁止），或关键词兜底（那张图 / 刚才的图 / 截图 / 照片 / 图里…，本轮没有新图时附最近一张；以「确认」开头的消息不触发）。每轮最多重发 1 张。
  - 看图失败不降级：SSE `error` 带 `code` = `vision_unsupported`（模型说不支持图片）/ `vision_failed`，文案「当前模型无法识别这张图片：<原因>」。
  - 委派：本轮图片（新图或召回的图）按同一 `attachment_id` 转给被委派 Bot（`run_once` 的 user 消息带 base64），`ask_bot` 结果带 `attachment_ids`，审计 `delegation_attachments`。被委派方仍看不到对话历史。
  - 带图轮次写操作需确认：`TurnState.image_tainted` 时 `create_reminder`（及 R1 的 `manage_reminder`）返回 `image_needs_confirmation` 并写审计，不执行；模型按 prompt 把内容写清楚，请用户回复「确认」，下一条不带图的消息里执行。**限制**：P1 没有确认卡片，用的是文字确认；记忆提议本来就要点确认，非只读 MCP 本来就被拒绝。
  - 删除：清空对话、删除 Bot 先删库行再删文件；删除单条消息（`DELETE /api/bots/{bot_id}/messages/{message_id}`，见上方「删除单条消息」）同样先删行再立即删原图 / 缩略图；删除账号（目前没有接口）靠级联删行 + 对账删文件。对账（启动时一次、之后每 24 小时）：pending 超过 24 小时删除；磁盘有库里没有且超过 1 小时的文件删除；库有磁盘无只记告警。启动时清空 `tmp/`。
  - iOS：Kit 新增 `Attachment`、`ChatRequest`（`attachment_ids`）、`AttachmentLimits`，`ChatMessage.attachments`（旧后端缺键为 `[]`），`VeraBotAPI.uploadAttachment / attachmentContent / attachmentThumb / deleteAttachment / chatStream(…attachmentIDs:)`（`APIClient+Attachments.swift`）。App：＋ 菜单「图片」打开系统 PhotosPicker（单选，再选替换；相机 / 文件仍禁用）；本机后台压缩（长边 2048、JPEG 0.8、CGImageDestination 不带元数据，透明图 PNG，GIF 原样）；输入栏上方缩略图（处理中 / 上传中转圈、失败重试、移除即删服务器上的未发送图），上传完成前不能发送，可以只发图片；用户气泡显示真实图片（最宽 240，GIF 用 ImageIO 逐帧 + `UIImage.animatedImage` 播放，「减弱动态效果」时显示第一帧），点按 Quick Look 全屏（自带分享）；图片只缓存在内存（`AttachmentImageStore`，退出 / 换账号清空，连同预览临时文件）。系统默认样式 + Theme 语义色，无自定义动画。新文件：`VeraBotCore/Attachment.swift`、`VeraBotNetworking/APIClient+Attachments.swift`、`Services/Attachments/{AttachmentImageStore,ImagePreparer}.swift`、`Features/Chat/{ComposerAttachmentModel,AttachmentViews}.swift`（工程用文件夹同步组，不改 `project.pbxproj`）。
  - 测试：新增 `attachments_test.py` 28/28（ATT-01~18、ATT-MIG、ISO-ATT-01、ATT-CONTRACT）；Kit `AttachmentTests.swift` 4 项（Linux 上单独编译 Core + Networking 跑通；App target 未编译）。回归（rebase 到 `f9e39c6` 后）：auth 18/18、avatar_profile 22/22、bot_pin、bot_tags 10/10、cache_headers 8/8、llm_body 5/5、mcp 失败 0、memory 36/36、multi_agent 25/25、plugin 失败 0、reminder、notify、status_event 8/8 全部通过（auth / plugin / reminder 里的版本断言改为 12）。

- **提醒与推送 R1（schema v11）**：设计见 [REMINDER_PUSH_DESIGN.md](design/REMINDER_PUSH_DESIGN.md) v1.0（D1–D18 已批准）。`frontend/web` 未改。
  - **行为变化：`list_reminders` 不再返回该用户的全部未完成提醒。** 现在只返回这个 Bot 自己创建的（`bot_id`）或用户指派给它的（`assignee_bot_id`）提醒，已取消的不返回。越权时工具结果是「提醒不存在」，并写 `audit_log` `tool_denied` / `reminder_scope`。
  - 时间解析失败不再把原文存进 `due_at`，接口与工具返回错误。排序键是 `due_utc`。iOS 按日期格式化，不再切字符串。
  - 数据：提醒状态机列、`reminder_events`、`notifications`、`notification_deliveries`、`notification_prefs`、`push_devices`、`idempotency_keys`。从 v10 升级前备份 `verabot.db.bak-before-v11-<时间戳>`。提醒相关 SQL（含调度清理）集中在 `db/reminder_store.py`；路由和服务不写这些 SQL。
  - API：提醒 CRUD 与 complete / done / snooze / reopen / skip / restore / events；通知列表、已读、未读、全部已读、删除、投递回报；通知偏好；设备注册与注销。写提醒认 `Idempotency-Key`。字段对照见设计 §8。
  - Bot 工具：`create_reminder`、`list_reminders`、`manage_reminder`（单条 update / complete / snooze / reopen / skip；取消和批量留到 R2）。被委派的 Bot 不能使用这三个工具。新 Bot 不会自动获得 `manage_reminder`。
  - 调度：启动后每 30 秒一轮，并立刻跑第一轮。睡眠或重启后的下一轮处理全部积压：刚好到期记一次 `fired` 并通知一次；错过多次只记一条「错过 N 次」，推进到下一个未来时间，不补发通知。`VERABOT_SCHEDULER=0` 关闭循环。
  - R1 不创建 `channel=apns` 的投递。退出、全部退出、`revoke_for_email_claim` 会禁用该用户的设备。邮箱验证码认领未验证账号（`_claim_unverified_email`）在同一事务里禁用设备，不另开 `logout_all`。
  - iOS：提醒 / 通知分段、设置 › 通知、本地通知类别 `VB_REMINDER`（完成、稍后 10 分钟）、离线队列、深链接。本环境未编译、未跑模拟器。
  - 测试：`reminder_test.py`、`notify_test.py`（假时钟，无外网）。Kit：`ReminderTests`、`NotificationSchedulerTests`、`DeepLinkTests`（本环境未跑）。
- **插件 P1（schema v10）**：用户看到的是「插件」，MCP 仍是实现。设计见 [PLUGIN_DESIGN.md](design/PLUGIN_DESIGN.md) v1.0。Q4 / Q7 按建议采纳；**Q6 改为新账号不预装任何插件**（含 Microsoft Learn）。`frontend/web` 未改。
  - 数据：新表 `user_plugins`（只记安装关系）；`mcp_servers.plugin_id`。启用、同意、同步、熔断仍在 `mcp_servers`。迁移把用过的目录服务（`consent_at`、`last_synced_at`，或任一 Bot 白名单含 `mcp__{slug}__`）记为 `installed`；没用过的不写 `uninstalled` 墓碑。演示账号已同意的 Learn 因此保持已安装。`plugin_default_installed()` 返回空集。`VERABOT_MCP_*_ENABLED` 不再预装（只改了 `.env.example` 注释）。
  - API：`GET /api/plugins/catalog`、`GET /api/plugins`、`GET /api/plugins/{id}`、`POST .../install`（201，已安装 409）、`DELETE`（清同意、从所有 Bot 和工具缓存去掉工具）、`PATCH {enabled}`、`POST .../consent`、`GET .../tools`、`POST .../sync`（停用时 409）。`GET /api/plugins` 含内置天气 / 提醒和已安装的外部插件，不在请求里联网。`/api/tools` 每项增加 `plugin_id`。缓存沿用 main 上的 `NoStoreAPIMiddleware`（`/api/*` 一律 `Cache-Control: no-store`）；iOS 插件方法都走 `APIClient.call`，使用 `APITransport.session`。
  - `/api/mcp/*` 保留并标为已弃用。`GET /api/mcp/servers` 不再补未安装的目录行。`POST /api/mcp/servers` 改为走插件安装（已添加 → 409「已经添加过这个服务」）。
  - 卸载与进行中调用：先删服务行再关会话。只读调用返回 `plugin_uninstalled`（不重试、不计熔断、不污染本轮）；审计 `status=cancelled`。同一轮再次调用也是 `plugin_uninstalled`。后台同步若服务行已没了，只记调试日志，不把外键错误打成 ERROR。
  - 重新同步不再把本服务已有的工具名当成冲突而改掉 `full_name`。
  - iOS：设置「插件」（已安装 N 个，只数外部插件）→「内置 / 外部 / 浏览插件」。内置详情说明开关在「工具权限」，并可前往该 Bot。卸载前系统确认框。Bot 详情分组改名「插件」。界面不出现「MCP」。Kit 增加 `PluginTests.swift`。本环境没有 Swift / Xcode，未编译。
  - 测试：`plugin_test.py`（进程内假 MCP，无外网）PLG-01～15 与契约通过。回归 `mcp_test`、`auth_test`、`bot_pin_test`、`bot_tags_test`、`memory_test`、`avatar_profile_test`、`status_event_test`、`multi_agent_test` 通过。本机库升级前请备份 `backend/data/verabot.db.bak-before-v10-<时间戳>`。
- **iOS · 默认形象合并复核 (PR #6)**：Xcode 26 / Swift 6 下 `AvatarGlobalFrameKey.defaultValue` 是可变静态属性，编译报错 (not concurrency-safe)，改为 `static let`；首页列表 / 消息里的静态形象对 VoiceOver 隐藏 (行本身已读 Bot 名，之前每行多读「方糖，空闲」)，对话导航栏的动画形象仍读姿态。Mac 上 `swift test` 126/126、xcodebuild 通过，模拟器看过首页、创建页、Bot 详情、对话导航栏 (已完成 → 空闲)。
- **iOS · 默认 Bot 头像改为头像实验室形象**：没有相册照片时，首页列表、对话页导航栏、Bot 详情（以及消息气泡、用量、记忆、委派列表里的同一个 `LiveBotAvatar`）用 V豆 / 芽芽 / 星点 / 云朵 / 方糖，不再用表情加底色圆。照片优先。创建页和详情「默认形象」改为这五款；选中的 id 写入已有 `avatar`（`veraBean` 等，均不超过 8 字），不新增接口。旧表情仍能对应到一款形象，不强制改写。对话页导航栏按 SSE 已有事件驱动的 10 个执行状态动画（复用实验室的 `phaseAnimator`，没有新动画框架）；首页和详情只显示静态空闲形象。正常结束后「已完成」保持 1.5 s 再回空闲；等你确认和整轮失败不自动回空闲。后端 `status` 字段未改。`frontend/web` 未改（冻结；形象 id 会当文字显示）。测试：`avatar_profile_test.py` 22/22（新增 AV-18），`status_event_test.py` 8/8；回归 PIN 8/8、TAG 10/10、AUTH 16/16、MEM 36/36、MA 25/25、MCP 本地用例失败 0。Kit 新增映射 / 计时用例（EXEC-34~40）。Linux 上 `swift test` 仍因既有 `MessageMarkdown.swift`（swift-corelibs-foundation 没有 `NSDataDetector`）编不过整个包；排除该文件后 Core 类型检查通过，并用与这些用例相同的断言跑通映射和计时。iOS 模拟器未编译、未点按。
- **账号 v9：邮箱 / 手机号登录 (AUTH-M1，schema v9)**：按 Boss 决定实现 [AUTH_REFACTOR.md](design/AUTH_REFACTOR.md) v1.0。
  - 登录方式：邮箱 + 密码、邮箱 + 验证码 (新邮箱首次登录自动建号)、手机号 + 密码 (自动规范成 E.164，暂不发短信)。用户名保留在数据里，界面不展示；demo / verabot2026 继续可用 (邮箱框填 demo)。
  - 后端：`users` 加 `email`、`email_verified_at`、`phone`、`token_version`、`failed_logins`、`locked_until`；新表 `auth_codes`、`auth_refresh_tokens`。新接口 `/api/auth/refresh`、`/logout`、`/logout-all`、`/email/send-code`、`/email/login`、`/api/me/email/send-verification`、`/api/me/email/verify`；`register` / `login` 兼容旧的 `{username,password}`。访问令牌 7 天 (JWT 加 `tv`、`typ`)，刷新令牌 60 天、每次轮换、复用即吊销全部。连续 5 次密码错误锁 15 分钟；IP / 邮箱发码限流。`/api/me` 新增 `email`、`email_verified`、`phone`。
  - 发信可插拔 (`services/mailer.py`)：默认 `console` (验证码写进后端日志)，配置 `VERABOT_MAIL_BACKEND=smtp` + `VERABOT_SMTP_*` 后走 SMTP；Gmail 应用专用密码还没有，所以现在仍是 console。
  - iOS：登录页分段控件「邮箱 / 验证码 / 手机号」(系统样式，验证码 60 秒倒计时)；设置 › 账号显示邮箱 / 手机号，邮箱未验证时显示「邮箱未验证 · 验证」(未验证也能正常使用)；令牌改存 Keychain (自动迁移旧的 UserDefaults `vb_token`)；`AuthSession` + `APIClient` 在 401 时透明刷新一次并重试 (并发请求只刷新一次，含上传 / 图片 / SSE 聊天)，刷新失败回到登录页；退出时吊销刷新令牌。
  - 测试：新增 `auth_test.py` AUTH-01~16 (迁移、三种登录、锁定、刷新轮换 / 复用 / 过期、退出、验证码限流 / 过期 / 次数、邮箱验证、IP 限流、发信后端、iOS 契约)；Kit `AuthTests.swift` (共 105 项)。全部后端回归通过。Web 冻结，未改。
- **MCP M2 (schema v8)**：在 M1 上补产品确认的五项。不改已有 Bot 的 `allowed_tools`，也不把 M1 里已经连上的服务当成已经同意。`frontend/web` 未改，仍然没有 MCP 界面。
  - **D4 同意**：按服务器记录 `consent_at`（不是全账号一个时间，因为决定写的是「每连接一个服务」）。`POST /api/mcp/servers/{id}/consent`，正文 `{"granted": true|false}`。未同意时工具不进模型 schema；若仍被调用，返回 `mcp_consent_required`，不访问网络。可撤回。iOS 设置详情用系统开关显示状态和同意时间。
  - **会话**：按用户和服务复用连接与 `Mcp-Session-Id`。HTTP 404（带了会话号）时重新 initialize 并再试一次。
  - **审计**：每次调用写 `mcp_tool_call`（成功、超时、错误、未同意、熔断），含工具、服务、耗时、`status` / `error_class`、起止时间、`user_id` / `bot_id`、`call_id`。不存外部原文。
  - **同步**：`GET /api/mcp/servers` 不再在请求里连外网。后台同步，`sync_status` 为 `pending` / `syncing` / `ok` / `error`，并带 `last_synced_at`。手动刷新仍是 `POST .../sync`。
  - **重试与熔断**：超时、5xx、429、连接错误才重试，默认再试 2 次，退避 `0.5,2` 秒加抖动。工具 `isError` 和 4xx 不重试。非只读且未标幂等的传输失败返回 `result_unknown` 且不重试。连续 5 次传输失败打开熔断 60 秒；到期后探测一次。字段 `circuit_state` / `circuit_open_until` / `consecutive_failures`。配置键见 `.env.example`。
  - 合并评审 (2026-10-03)：`VERABOT_MCP_RETRY_MAX=0` 时非只读工具的传输失败漏成普通超时 / 不可用，改为一律 `result_unknown`，并补用例。Mac 上全部后端用例、`VERABOT_MCP_LIVE_TESTS=1` (Learn / AWS 公网通过)、`swift test` 95/95、xcodebuild 通过。
  - 测试：`mcp_test.py` 假服务器增加 404、5xx 和超时；v6→v8、空库 v8、已有 v7 库升级。公网用例仍要 `VERABOT_MCP_LIVE_TESTS=1`。字段对照见 [MCP_CAPABILITY.md](design/MCP_CAPABILITY.md) §18.3。
- **方案文档**：[design/AUTH_REFACTOR.md](design/AUTH_REFACTOR.md) 账号体系改为邮箱 / 手机号登录的方案草案 (现状审计、目标模型、分阶段流程、demo 迁移、API 与 iOS 同步、限流等安全措施、里程碑、待 Boss 决定事项)，未改代码。(已于同日定稿为 v1.0 并实现，见上方「账号 v9」)
- **MCP M1 (schema v7)**：后端作为 MCP 客户端，连接免授权的公网服务。默认 Microsoft Learn（`VERABOT_MCP_LEARN_URL`，开）；备用 AWS Knowledge（`VERABOT_MCP_AWS_URL`，默认关，不访问网络）。地址可改，见 `backend/.env.example`。不改已有 Bot 的 `allowed_tools`。
  - 传输：自研 Streamable HTTP（`Accept` 同时接受 JSON 与 SSE；有 `Mcp-Session-Id` 才回传；接受服务器协商的更低 `protocolVersion`，之后放进 `MCP-Protocol-Version`）。超时 `VERABOT_MCP_TIMEOUT` 默认 15 秒。工具级 `isError`（`mcp_tool_error`）与 JSON-RPC `error`（`mcp_rpc_error`）分开。官方 SDK `mcp==2.2.0` 已锁定，握手不用它的自动模式。
  - API：`GET /api/mcp/catalog`、`GET/POST /api/mcp/servers`、`PATCH/DELETE /api/mcp/servers/{id}`、`POST /api/mcp/servers/{id}/sync`、`GET /api/mcp/servers/{id}/tools`、`POST /api/mcp/tools/{id}/accept-change`。`GET /api/tools` 增加 `source` / `server` / `server_id` / `risk` / `requires_confirmation` / `delegable` / `status`，并附上已连接且 active 的 MCP 工具；此接口不连外网。公开 JSON 不返回原始 URL。
  - 权限：命名空间 `mcp__{slug}__{tool}`；每 Bot 最多 20 个 MCP 工具；被委派不能调用；读过 MCP 结果的轮次不能 `ask_bot`；非只读工具不执行，返回需要确认。结果清洗后包在 `<untrusted_tool_result>` 里。
  - iOS：设置 › MCP 服务（用量 / 记忆之后）；Bot 详情「MCP 服务」分组开关和「开启全部只读」。Web 未改。
  - 测试：`backend/scripts/test/mcp_test.py`（本地假服务器覆盖 JSON / SSE、会话号、协议降级、两种错误；v6→v7 与全新库）。真实 Learn / AWS 用例默认跳过，`VERABOT_MCP_LIVE_TESTS=1` 才跑。回归 PIN-01~08、MEM 36/36。字段对照见 [MCP_CAPABILITY.md](design/MCP_CAPABILITY.md) §18.2。
  - 合并评审 (2026-10-03)：tool 消息里 MCP 结果不再按 6000 字截断 (会切掉结束标记)；设置页说明「工具返回的内容会发送给 DeepSeek」(D4)；新增 MCP-CALL-LONG 与 Kit `MCPTests` (共 92)。与 main 的 SSE `status` 事件合并：外层 MCP 调用也走 `_run_tool_streaming`。中国大陆网络实测 Learn / AWS 可用，单次调用约 2.4–2.9 s。
- **执行状态机 v1.1 (前后端)**：后端 SSE 新增 `status` 事件 `{phase, depth, bot_name, tool, parent_id}`：`recalling` (每轮召回记忆前，仅开启记忆时，depth 0)，以及被委派 Bot 的 `thinking` / `tool` (经 `TurnState.status_queue` 实时转发，位于外层 `tool_start` 与 `tool_result` 之间，`parent_id` = 外层 tool id，支持多跳 depth)；不写入 traces，旧客户端 / Web 忽略。iOS：`VeraBotCore.ChatStatus`、`ChatEvent.status`；`ExecutionState` 新增 `recalling`、`delegating(botName:progress:)`、`blocked(code:message:)` (tool_result 带 `error` 时短暂受阻，`ChatViewModel` 1.2 s 后发 `blockedElapsed` 回到原流程，整轮失败仍是 `failed`)。头像实验室：新增「委派中」「回复中」两种状态 (共 8 种)，`AvatarLabState(ExecutionState)` 映射，思考 / 执行 / 委派 / 回复在可见且前台时用系统 `phaseAnimator` 循环、离屏停止，减弱动态效果时静态，「遇到阻塞」改为轻摇一次，新增「按状态机演示一轮对话」。对话界面未改。测试：`status_event_test.py` STAT-01~08、`swift test` 新增 14 个 (共 88)。设计见 [design/EXECUTION_STATE.md](design/EXECUTION_STATE.md) v1.1。
- **iOS Core · 执行状态机**：`VeraBotCore/ExecutionState.swift` 新增 `ExecutionState` (idle / thinking / callingTool / delegating / replying / awaitingConfirmation / completed / failed)、`ExecutionEvent` 与值类型 `ExecutionStateMachine`，由现有 SSE 事件 (delta / tool_start / tool_result / error / done) 加客户端事件 (发送、流结束、记忆卡片处理、重置) 推导；`ask_bot` → 委派，记忆提议卡片 → 等你确认，error 后的 done 保持出错，迟到事件忽略。`VeraBotNetworking` 新增 `ChatEvent.executionEvent`。`ChatViewModel` 只读暴露 `executionState`，**界面未改、后端未改**。设计与转移表见 [design/EXECUTION_STATE.md](design/EXECUTION_STATE.md)。`swift test` 新增 19 个 (共 74/74)，用例 EXEC-01~19。
- **iOS · 头像实验室 (独立试验页)**：在「设置 › 调试 › 头像实验室」加入五款可交互角色预览（V豆、芽芽、星点、云朵、方糖），可切换六种状态、三种尺寸并重播状态动作；本页选择仅用于预览，不会写入 Bot 头像或资料。云朵从参考图提取轮廓并去除原图蓝色背景，使用实验页配色与柔和高光。仅影响独立实验页，不改现有 Bot 头像方案；iPhone 17 模拟器构建、安装、启动通过，视觉手工验收待进行。
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

- **iOS · 提醒页整页滚动、大标题收起**：「提醒／通知」分段控件原来放在列表上方的 `VStack` 里，列表不是导航栏下的主滚动视图，大标题「提醒」不随滚动收起。现在分段控件是列表第一个分组的头（`Section { } header:`，提醒与通知两个列表都是），位于大标题下方、随列表一起滚动；上滑时大标题收进导航栏中间（`.navigationBarTitleDisplayMode(.large)`）。（PR #21 初版用 `safeAreaBar(edge: .top)` 吸顶，会盖住大标题，已改掉。）行、左右滑操作、下拉刷新、空状态、工具栏按钮不变。
- **后端 · P0 模型迁移：`deepseek-chat` → `deepseek-flash`，关闭思考模式** (Boss 2026-10-03 定为 P0；附件设计 Q1)：官方变更日志写明旧名 `deepseek-chat` 已于 2026-07-24 停用 (此前仍被转发)，`deepseek-flash` (DeepSeek-V4.1-Flash) 是现行模型并支持看图。`core/config.py` 默认 `DEEPSEEK_MODEL=deepseek-flash`；`services/llm.py` 请求体加 `"thinking": {"type": "disabled"}` —— `deepseek-flash` 默认开启思考，带 `tools` 的多轮请求若不回传 `reasoning_content` 会 400，而我们不保存它。新增 `VERABOT_DEEPSEEK_THINKING` (默认 0；设 1 只是去掉该字段，需先实现 `reasoning_content` 回传)。本机 `.env` 没有覆盖模型，未改 `.env`。`/api/health`：迁移前 `deepseek-chat`，迁移后 `deepseek-flash`。新测试 `llm_body_test.py` LLM-01~05；模拟器实测普通对话 + 一轮天气 + Microsoft Learn 工具调用 (带工具结果的第二次请求 200)。`.env.example`、`backend/README.md`、`RUN_LOCAL.md` 同步。
- **iOS · 去掉界面残留英文 tokens**：对话委派 Trace 行「协作记录 #N · M tokens」→「协作记录 #N · 用量 M」(与协作记录页一致)；用量看板「今日 Token 额度」→「今日额度」，「a / b tokens · 今日请求 N 次」→「用量 a / b · 今日请求 N 次」，「输入 / 输出 / 总 Tokens」→「输入用量 / 输出用量 / 总用量」，「近 7 日 Tokens」→「近 7 日用量」，按 Bot「N 次 · M tokens」→「N 次 · 用量 M」；额度用完的本地提示「今日 Token 额度已用完」→「今日额度已用完」。仅文案，后端未改。用例 UI-EN-01。
- **文档 · 与代码对齐 (2026-10-03)**：backend README / MULTI_AGENT_DESIGN 的「当前 schema v3」改为 v6；docs/README 中 MEMORY_GROWTH 状态改为 v1.0 已批准、M1 已实现；FEATURES 补删除二次确认、置顶、首页头像 44pt；RUN_LOCAL 补 v5 / v6 升级说明；STATUS 交接更新 HEAD、置顶提交号与 `File.txt` 清理记录。仅文档。
- **iOS · App 图标支持亮色／暗色模式**：沿用现有图形，仅调整配色（亮色：浅底深靛蓝剪影；暗色：深底浅银白剪影）。`AppIcon.appiconset` 新增 `AppIcon-1024-dark.png`（luminosity = dark），未加 tinted 变体。
- **iOS · 首页左上角头像恢复正圆**：iOS 26 会给工具栏项套一层 Liquid Glass 共享底（按内容计算的胶囊，比 30pt 头像大），头像外面看起来不是圆的。`BotListView` 左上角 `ToolbarItem(.topBarLeading)` 在 `if #available(iOS 26.0, *)` 内加系统 `.sharedBackgroundVisibility(.hidden)`，只显示正圆头像，尺寸改为 44pt，与右侧搜索 / ＋ 圆形玻璃按钮等大；iOS 17~18 不变 (30pt)。`HomeAvatarLabel` 新增 `size` 参数。仅 iOS，后端未改，无自定义动画。用例 UI-11b。
- **文档 · Bot 置顶规格与交接**：新增 [design/BOT_PIN.md](design/BOT_PIN.md) (Boss 批准，预留 schema v6；后已在 `c5529ce` 实现，见「新增」)；MCP / Gmail 设计稿迁移版本改为 **schema v7**；STATUS 新增交接一节 (HEAD、勿提交文件、规则、待办、启动命令)。仅文档。
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

### G3 首轮验收修复

- 顶部 Bot 头像交由外层点名按钮接收点击，显示选中背景。
- 更改群默认回应者后同步当前目标，避免旧 A 点名覆盖新默认 C；重命名保留当前点名。
- 新增默认切换/改名保留目标回归，用户点名交互待复测。

## 2026-10-13 群聊意图/接力复审整改（隔离工作树）

修复多成员队列、澄清/补充/换题、咨询返回栈及合同、调用级预算/取消/记账、真实SSE合同、未确认UUID持久恢复、清空/冲突/停止/继续与历史重试。v25迁移保护游标及删除群后的调用身份。已准备iPhone17和8094隔离手动测试环境；真实模型质量与用户设备交互仍待用户验收。
