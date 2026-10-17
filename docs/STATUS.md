# 项目状态 (STATUS) — 2026-10-17

## 2026-10-17 · 隐藏对话内待同步提示文案

- iOS 私聊 notice / 群「进度待同步」/ MCP·插件「等待同步」对用户不可见；同步与恢复逻辑及「连接有点慢」横幅保留。未跑 git / xcodebuild / swift test。

## 2026-10-17 · 会话列表隐藏「待同步」行标

- iOS 会话列表 Bot 行去掉预览下灰色「待同步」标签，行高恢复正常；`activityNeedsSync` 与顶部连接横幅保留。群行本就无该标。未跑 git / xcodebuild / swift test。

## 2026-10-17 · 对话标题胶囊与侧栏按钮等高

- iOS 私聊 / 群聊标题胶囊外高改为固定 44pt（iOS 26：plain + glassEffect 胶囊；旧系统 bordered），与工具栏两侧圆形玻璃按钮垂直对齐。主 Bot 星标在小头像上按比例缩小并偏右下，列表 44pt 不变。未改其它 UI。未跑 git / xcodebuild / swift test。

## 2026-10-17 · 首页头像与右上角 ＋ 对称对齐

- iOS 首页左上头像外径 44pt（对齐系统工具栏玻璃圆）、去掉水平负偏移，左右边距与垂直中心与右侧 ＋ 对称；白环 + 玻璃观感保留。未改搜索 / ＋。未跑 git / xcodebuild / swift test。

## 2026-10-17 · 首页头像白玻璃底内嵌白环

- iOS 首页左上角头像：外圆尺寸/位置不变，照片内缩约 2.5pt 露出白环，玻璃底与 `JumpToLatestButton` 同款（对齐右侧搜索 / ＋ 观感）。未改搜索 / ＋。未跑 git / xcodebuild / swift test。

## 2026-10-16 · 资料库 SQL 分层收尾

资料库在 service / agent 层的直连 SQL 已全部下沉到 `db/library_store.py`、`db/attachment_store.py`；`sql_layer_check` 通过。相关资料库 / 附件 / 多代理回归见 CHANGELOG。未改 frontend，未跑 git。

## 2026-10-16 · Main 集成与迁移版本消歧

本地资料库等已提交内容与远端 PR #48–#50 集成，源码 schema v35。保留资料库 v33 / TXT 元数据 v34，旧任务与 trace 迁移改为 v35，兼容远端 v33 无资料库的升级路径。运行中服务及数据库未更新，设备交互未验收。验证与已知问题见 [集成记录](tasks/2026-10-16-main-integration.md)。

## 2026-10-15 · 资料库验收修复与 Bot 布局恢复

资料库入口已移至头像设置页；修复独立图片预览与下载，恢复 Bot 原表单并加入设置/文件/图片分页。按追加要求移除开始对话、提醒、协作记录入口，主 Bot 合入昵称标签卡片，形状网格压缩。0.1.0 (2026101503) 已安装模拟器和 iPhone 11，8 份原件下载校验通过；交互待用户验收。见 [修复记录](testing/2026-10-15-library-follow-up.md)。

## 2026-10-15 · 暂时隐藏小岛 Tab

- iOS 底部 TabBar 暂时移除「小岛」入口，页面实现保留；既有截图未更新。未运行构建或设备验收。

## 2026-10-15 · 独立资料库已部署并安装

独立资料库已合入本地 main，后端 schema v34 与三个 worker 已重启；7 份资料完整性检查通过。模拟器安装并启动，iPhone 11 安装成功、锁屏未自动启动。Swift Testing 325 项与现有 XCTest 1 项通过，模拟器/真机构建成功；交互验收由用户执行。见 [交付记录](testing/2026-10-15-independent-library.md)。

## 2026-10-15 · 快捷提问背景修复

- 模拟器复现快捷提问胶囊阴影被横向 ScrollView 裁切，背景呈矩形色带。取消裁切、增加玻璃容器与垂直留白；保留原输入交互。
- 验证与截图见 [快捷提问检查](testing/2026-10-15-quick-prompts-layout.md)。本轮未覆盖真机视觉验收。

## 2026-10-15 · 对话本地内容先展示

- 私聊/群聊在 SQLite 恢复完成后立即定位消息，不再等待活动摘要、历史同步或任务状态请求结束。群聊后台同步期间仍可翻阅更早的本地历史，刷新保留已展开的消息范围。
- Swift Testing 318 项及 XCTest 1 项通过，模拟器构建通过。设备交互与交付状态见 [离线进入记录](testing/2026-10-15-offline-chat-entry.md)。当前截图未更新。
## 2026-10-15 · 后端过时失败任务与 trace 瘦身（schema v33）

- `fix/backend-stale-tasks-slim-traces`：源码 schema 升到 v33。会话摘要排除已被后续完成回复取代的失败／中断任务（`superseded_at`）；工具 trace 落库与同步前瘦身，`read_file` 不再存文件原文。v33 迁移回填存量任务标记并改写存量 trace，迁移前自动备份。新脚本 `stale_work_trace_slim_test.py` 与 `sql_layer_check.py` 通过；未在运行中的数据库或真实模型上验证。详见 [known-issues](testing/2026-10-14-known-issues.md)。

## 2026-10-15 · 工作区提交盘点

- 本轮基线 main `0458189`（PR #47）；源码 schema v32。Git 仅注册主工作区，全部本地分支均已包含在 main 中。旧日期的「未合并」和 schema 说明属于历史快照，不代表当前基线。
- 保存助理列表移除重复主 Bot 快捷行的本地改动；身份徽章、任务管理及原会话入口保留。现有截图未更新，不代表此次最新列表。
- 本轮验证与提交范围见 [提交记录](testing/2026-10-15-workspace-submit.md)；未验证设备安装版本、运行中数据库或真实模型，不推送远端。


## 2026-10-15 · 长回复折叠阈值按手机高度重定

- `fix/long-reply-collapse-threshold`：折叠改为估算排版高度超过约一屏（28 行）或 500 加权字；预览 ≤ 200 字 / 8 行。「思考助手」594 / 716 字的 Markdown 回复会折叠，329 字的不折叠。`read_file` trace 卡片不再排版 3 万字文件原文。未构建、未跑 `swift test`、未在模拟器验收；后端仍把完整文件文本存进消息 traces（单条 32 KB）并随历史下发，未改。

## 2026-10-15 · 私聊长回复折叠

- `feat/collapse-long-bot-replies`：超过 1500 字或 40 行的 Bot 回复默认只渲染截断预览，「展开 / 收起」切换，规格 [long-reply-collapse](specs/long-reply-collapse.md)。未构建、未跑 `swift test`、未在模拟器验收。

## 2026-10-15 · 创建群聊去掉说明文案、选择行紧凑化

- `fix/create-group-compact`：创建群聊弹窗去掉「每个群聊需要选择 2～5 个 Bot」，2～5 校验不变；Bot 选择行与群成员行、添加成员行同高（头像 30、间距 10、相同行边距）。未在模拟器验收。

## 2026-10-15 · Bot 动态开场词 Phase 1

- 空对话开场词改为混合生成：后端一次出人设模板，iOS 本地按时段/日子/关系阶段组装。规格 [bot-opening-message](specs/bot-opening-message.md)；验证 [testing](testing/2026-10-15-bot-opening-message.md)。天气维度属 Phase 2。Web 冻结未改。

## 2026-10-15 · 列表行状态不再误显「工作暂未完成」

- 私聊发问后回到列表，Bot 已正常回复，列表行却显示「工作暂未完成」。根因是服务端摘要保留历史失败/中断任务，最新一轮完成后行状态落回旧记录。iOS 现以最新消息正文为准，隐藏过期终态与内部重试阶段；后端未改。VeraBotKit 300 项测试通过、模拟器构建通过，未在模拟器/真机手动验收。详见 [known-issues](testing/2026-10-14-known-issues.md)。

## 2026-10-15 · 回复中输入栏只显示停止按钮

- 私聊 / 群聊回复中，输入栏右侧只显示停止按钮，不再显示转圈；群聊暂不可停止时按钮置灰禁用。未构建、未在模拟器验收。

## 2026-10-15 · 回复对齐、忙碌态输入栏、打开即已读

- Bot 回复气泡与操作行左对齐；回复中输入栏显示停止按钮并禁止再次发送；打开对话即全部已读（修复「健康助手」再次进入仍显示未读）。详见 [known-issues](testing/2026-10-14-known-issues.md)。

## 2026-10-15 · Worker 加载 .env、事件流修复与新消息提示

- 根因：chat worker 由人工在 screen 中直接启动，未经 `start.sh` 导出 `.env`，`DEEPSEEK_API_KEY` 为空，私聊回复全部失败。现 worker 入口自行加载 `.env` 并在缺 Key 时拒绝启动。
- iOS 私聊事件流因空行被吞而不派发，失败任务停在「排队中」；已改为按字节读取。新消息只保留一次性的「新」分隔线，列表未读改为圆点。详见 [known-issues](testing/2026-10-14-known-issues.md)。

## 2026-10-14 · 群聊成员增删

- PR #37 已合入：已有群可增删 Bot 成员。跟进 `fix/group-member-remove`（PR #38）：左滑确认前不移走行（`.tint(.red)`）、成功后再动画移除；添加成员多选且无 footer；未读「新」分隔线样式；群设置顶栏头像/群名样式；群 `await_user` 空 `missing_information` 不再误失败完整回复；编排内部状态不对用户暴露（有正文则公开 `completed`，仅空正文显示未完成/重试）。规格 [group-member-edit](superpowers/specs/2026-10-14-group-member-edit.md)。

## 2026-10-14 · 今日已合入 main（文档同步）

- PR #33 SQL 分层收尾：直连查询迁入 `db/`，`sql_layer_check` 严格通过。见 [CHANGELOG](CHANGELOG.md)、[known-issues](testing/2026-10-14-known-issues.md)。
- PR #34 离线提示统一：单条 `ConnectionNotice` + `AppState.message(for:)` 友好文案。
- PR #35 Bot/群聊数量 UI 限制（10 / 2～5）。PR #36（已合入）去掉助理列表计数展示与创建群聊底部提示卡片。规格 [bot-limits](superpowers/specs/2026-10-14-bot-limits.md)。

## 2026-10-14 · 对话持续执行与本地通知集成

`wip/main-uncommitted`、`codex/chat-continuity`、`codex/local-notifications` 已合入 `integration/2026-10-14`，基于 main `5a91461`，尚未合并。schema v30 为私聊持续回复与阅读记录，v31 为通知事件。离线后端脚本已跑，Swift / 模拟器 / 真机未验证。范围和剩余项见 [集成记录](testing/2026-10-14-integration.md)。

## 2026-10-14 · 主 Bot 已集成本地 Main

产品提交 b68dfc4 已合入，现有 iPhone 17 已安装启动，8096假模型服务运行；原并行修改保持未提交。功能验收待用户完成，最新证据见[交付记录](testing/2026-10-13-primary-bot.md)。下方实施前说明为历史快照。

## 2026-10-13 · 主 Bot 实施前复核与具体计划

- 用户确认主 Bot 推荐首版并要求实施前检查。最新本地 main 为 `b81caed`，群接力 `a01b2d7` 已合入，源码 schema v25；原开发库迁移及群真实交互仍待完成。下方早先“尚未合入”是先前快照。
- 在新基线重新验证定时任务36项、群handoff10项，全部通过；没有重跑Swift/全库测试或调用真实模型。本轮保留已有未提交UI/文档，不安装服务、升级数据库或替换验收App。
- [具体实施计划](superpowers/plans/2026-10-13-primary-bot.md)覆盖P0–P3，明确v26起的迁移、身份设置、任务/步骤/事件、周期桥接、MCP批准续跑及iOS任务页。设计已确认，新增计划待审阅/执行方式确认，主Bot产品代码尚未开始。
- 推荐Native顺序实施、独立工作树保护main；本轮未派发子代理。原定时v1和群协议/权限保持各自边界，APNs/生产部署不在首版。

## 2026-10-13 · 功能盘点、文档对齐与主 Bot 讨论稿

- 本轮主线基线为 `4fc063d` / schema v23；相对本机 `origin/main` 引用领先 13 个提交，未查询远端实时状态。工作区已有其他界面与方案改动，本轮保留，只更新文档。
- 服务端定时任务已实现并合入 main：当前重新运行 36/36 离线回归通过；主线群路由 2/2 通过。没有重跑 Swift、构建、全后端或真实模型验收。独立后台进程部署、iOS 任务管理、APNs、委派/写入/等待用户后续跑仍不在定时任务 v1 范围。
- 群意图与接力已在 `group-intent-handoff` 独立工作树实现并修复，使用 v24/v25，最新交付待用户手动验收；尚未提交或合入 main。主线仍是默认回应者/语义路由与请求内执行，不能把工作树能力当主线已交付。
- README、FEATURES、ROADMAP 与文档索引已同步关键边界，完整依据见 [当前盘点](testing/2026-10-13-project-inventory.md)。文件/真实 OAuth/本地向量效果/设备交互等剩余验收继续保留。
- [主 Bot 接入方案 v0.1](superpowers/specs/2026-10-13-primary-bot-design.md)为待评审讨论稿：推荐身份 + 明确交办/周期任务 + 持久步骤 + 求助/确认续跑；不会替代群内动态成员分配。本轮未实现、提交、合并或推送功能代码。

## 2026-10-13 · 主 Bot P0–P3 实现

已在`codex/primary-bot`实现身份/徽章、任务管理、持久执行/求助/有限咨询、周期桥接和MCP确认续跑，schema v29。代码基于main `b81caed`，保留主工作区现有修改；2026-10-14已提交并合入本地main（b68dfc4），未推送或升级原数据库。新增40项后端与相关回归、Swift260+1、模拟器编译和临时库迁移检查见[交付记录](testing/2026-10-13-primary-bot.md)。实际UI/真实模型、常驻部署和APNs未验收；后台说明与假模型验收脚本已准备。


## 2026-10-13 · 群聊复审整改，已准备用户手动测试

复审16项缺陷及独立复审6项追加组合问题已修复。26项新后端行为回归、相关API/存储/worker回归、Swift Testing 251 + XCTest 1、真实Swift→localhost fake后端流联调通过，最终模拟器构建成功。schema v25修补调用身份保留和游标复用。iPhone17模拟器已安装启动此工作树App，连接8094隔离后端（现有账号/Bot/附件副本、真实provider配置）。未发起真实模型验收；用户要求控制额度并在可手动测试时停下，此刻停止自动工作等待用户结果。未提交、合并、推送或迁移原开发库。见[修复交付与手动验收](testing/2026-10-13-group-intent-handoff-repair.md)。


## 2026-10-13 · 群聊意图路由与任务交接（当前隔离 worktree）

用户确认设计并授权在本对话实施。实现位于独立 worktree `/Users/admin/.codex/worktrees/group-intent-handoff/VeraBot-v0.1`，基于 schema v24 与群协议 v2：移除默认回应者；按意图选成员；含糊时由系统选澄清 Bot 并锁定本次负责人；支持咨询返回和显式交接；任务由单进程后台 worker 持久运行，事件断线可按游标恢复。旧群记录保留，旧写 API 返回 426。

临时 SQLite 后端回归、真实本地 socket/SSE 假模型联调、Swift 群聊/任务用例与 iOS Simulator Debug 构建已通过。未合并、推送、迁移主工作区数据库或发布；未调用真实模型；用户设备与真实模型质量验收未执行。部署仅支持一个 API 进程。详细证据、部署先决条件和待用户验收清单见 [群聊意图分配与交接实现记录](testing/2026-10-12-group-intent-and-handoff.md)。

## 2026-10-12 · 全工作区整合与最新设备版本

全部主工作区和工作树改动已提交并合入本地 main，代码集成提交 `eb67ff9`；其余五个干净工作树的提交原已在 main，保留所有工作树与分支。迁移统一 v23，现有开发后端已备份/演练/升级并重启，数据完整性与数量保持。Swift Testing 241 + XCTest 1、33 个后端离线脚本、36 项定时任务回归通过，独立复审无阻塞；SQL 分层仍有100条既有问题、新增0。iOS 0.1.0 / build 2026101201 已安装到 iPhone 17 模拟器和 iPhone 11 备机；模拟器已启动展示实际页面，备机首次被锁屏拒绝，用户解锁后已启动并确认进程。当前状态与待验收清单见 [Main 集成交付](testing/2026-10-12-main-integration.md)。未推送远端；以下为对应日期的历史快照。

## 2026-10-12 · 群聊 @ 输入与键盘交互验收通过

修复输入框焦点与光标更新冲突、成员列表布局和点击区域、中文组合输入及发送标记生命周期；成员列表保持液态玻璃样式，最多显示五项，超出滚动。25 项编辑器回归、模拟器与真机构建通过；iPhone 17 模拟器、iPhone 12 Pro Max 主机与 iPhone 11 备机已更新。用户于 2026-10-12 确认本轮验收通过，记录见 [群聊 @ 与键盘回归](testing/2026-10-12-group-mention-keyboard.md)。

## 2026-10-12 · 头像形状落地

十一种锁定形状已接入创建、编辑与统一绘制，沿用现有后端外观接口，无新增数据库迁移。12 项 Swift 外观/形状测试及含十一种形状回读的后端契约测试通过，模拟器构建、安装、启动成功；视觉交互待用户手动验收。验收见 [形状落地](design/2026-10-12-avatar-shapes-production.md)。

## 2026-10-12 · 移动端 SQLite 离线持久化（初始实现记录）

- iOS 增加 SQLite 本地库与独立 Repository：Bot/群列表、私聊/群聊完整分页历史、草稿及中断中的消息保存在按服务器与用户隔离的本地数据库。
- 后端 schema v21 增加会话修订号和一致快照分页；本地历史先展示，再按修订号同步，清空/删除会使进行中的快照失效，避免旧数据复活。
- 初始实现时未运行测试、构建或模拟器验收；2026-10-12 整合验证与缺陷修复见上方集成记录。原验收范围和边界见 [移动端持久化记录](testing/2026-10-12-mobile-persistence.md)。

## 2026-10-11 · 群聊转为正式功能

移除 App 群聊预览入口、模拟成员/回复与四个预览页面，以及预览启动参数；助理页群聊和建群统一使用正式 API，沿用 schema v20 的现有持久存储。自动回归及独立开发测试服务保留在产品外，不作为用户功能。正式模型体验、管理与账号隔离的剩余设备验收按原记录继续，不把删除预览等同于全部验收完成。

## 2026-10-11 · 群聊首版运行到模拟器与两台真机

G0/G1/G2 已实现，G3 自动及主要模拟器交互通过；真实模型讨论体验和剩余管理/隔离界面仍待验收。群聊工作树签名构建通过，现有 G3 模拟器、iPhone 12 Pro Max 主机和 iPhone 11 备机均已安装启动；两台真机保留登录，现有后端账号/Bot 请求返回 200。后端使用群聊工作树代码、主工作区现有配置与数据，已备份并迁移 v19→v20，原有用户/Bot/私聊消息数量保持不变。模拟器保留 8093 隔离验收服务，两台真机接 `192.168.0.104:8000` 真实后端。群聊已提交为 `2978090` 并合入本地 main，未推送；主工作区并行语音播放改动保持未提交。合并后的当前工作区 Swift 224 + 1 项与后端 74 项回归通过。完整交付记录见 [设备交付](testing/2026-10-11-bot-group-chat-devices.md)。

## 2026-10-11 · 群聊 G3 自动验证与验收准备

后端 74 项、首轮修复后 Swift 214 + 1 项、Simulator build、真实 HTTP/SSE 模拟提供者联调通过。用户确认创建群、默认回应、全体讨论通过；用户授权代验收后，默认 C 保存/点名/顺序讨论/停止/单成员重试/后台中断/重启偏好已在实际页面通过；「保存 C 仍由 B 回应」本轮未复现、原因仍未确认；管理等其余页面与真实模型验收待完成，未提交/合并/推送，未升级正式库。 [G3 验证与验收交付](testing/2026-10-11-bot-group-chat.md)。

## 2026-10-11 · 对话朗读生命周期修复

- 用户已确认：返回列表停止且不自动恢复，滚动和临时弹层继续；后台 / 锁屏停止，开始语音输入前停止朗读。
- 同步修复本机音频会话释放及旧朗读回调污染新播放状态；保留全屏相机临时覆盖例外，账号退出 / 失效停止。
- Swift Package 完整测试 203/203 通过（本次朗读回归 8/8）；iPhone 17 / iOS 26.0 Debug 构建通过，设备声音、锁屏和页面交互待验收。问题、决策与用例见 [对话朗读生命周期](design/CHAT_SPEECH_PLAYBACK.md)。本次代码与文档尚未提交。

## 2026-10-11 · 代码与文档盘点

- 当前本地 `main` 为 `c66f2d2`；相对本机 `origin/main` 引用超前 9 个提交，未确认远端最新状态。代码已提交；本次进度对齐与验收证据尚未提交。未发布新版本。
- 记忆 M3-01～05、M4-01～05 均已由用户验收通过；M5-02/03 与卡片缺失、回复省略问题已复测通过。M5-04 服务层降级验证通过；真实本地向量模型的语义召回没有单独验收记录。
- MCP M3 已按用户指定模拟器标准通过；MCP M4 OAuth 已实现，真实 Google 授权待验收。Google 账号登录 VeraBot 未实现，与 Gmail 授权连接分开跟踪。
- 主要待验收：文件附件、提醒编辑与时区、真实 OAuth / GitHub / Linear、陪玩与旅行原型、启动 / 网络错误页面及剩余界面项。详见 [完整盘点](testing/2026-10-11-project-inventory.md)。
- 文档中的旧测试数量均为对应提交快照；本次盘点不重跑测试、不新增功能，也不表示当前全量回归已通过。

## 2026-10-11 · 群聊 G2 正式接线（独立工作树）

- 已按用户「继续 G2」完成群上下文/顺序生成、停止、请求断开/重启恢复、原上下文单人重试，以及 iOS 群列表/创建/聊天/管理接线。
- 本群历史与当前成员指令单独组装；不启用工具、附件、私聊或长期记忆。预算、输出上限和超时生效，遗留轮次不自动续跑。
- 后端相关测试 74/74、Swift 包 211 项及模拟器构建通过；SQL 分层检查仍有 100 条基线问题，新增 0。详见 [G2 记录](testing/2026-10-11-bot-group-chat-g2.md)。
- 未部署/升级生产库，未调用真实模型、未提交/合并/推送。G3 实际群联调与用户交互验收待进行；构建通过不代表真实讨论体验通过。

## 2026-10-11 · 群聊 G1 数据与协议基础（独立工作树）

- 用户回复「OK，继续下一阶段」后完成 G1：v20 群表/迁移、群管理 API、用户隔离、轮次幂等与并发限制、历史分页、删除 Bot 后保留身份快照。
- iOS 已补齐 GroupChatAPI、群事件解析与 reducer，复用鉴权/刷新；重复请求查询原轮次快照，换账号后丢弃旧请求。预览 UI 仍使用模拟数据。
- 临时数据库群测试 13/13、既有后端相关回归 45/45、Swift 包 206/206 通过，模拟器构建成功。全库 SQL 分层检查仍失败；基线与当前均 100 条，新增 0。
- 真实模型发言、运行中停止/断开恢复、重试和正式 UI 接入尚未完成。未迁移正式数据库，未提交/合并/推送。详见 [G1 记录](testing/2026-10-11-bot-group-chat-g1.md)。

## 2026-10-11 · 群聊 G0 界面预览（独立工作树）

- 用户确认伙伴讨论模式并授权继续；先交付规划 G0 界面，待用户查看后接群 API 和真实模型。
- 预览提供创建群、独立头像/消息、点名、顺序讨论、停止和失败重试；Debug 专属，模拟数据仅保留在本次运行。
- 主线尚无正式群聊；G0 当时尚未实现群存储与成员权限；后续进度见上方 G1，真实发言和完整验收仍待完成。详见 [G0 记录](testing/2026-10-11-bot-group-chat-preview.md) 和 [实施计划](superpowers/plans/2026-10-11-bot-group-chat.md)。

## 2026-10-11 · MCP M3 确认卡片验收通过

- 用户指定模拟器功能测试通过即标记通过，布局不纳入本次验收。当前 `main` 的 `c66f2d2` 已在 iPhone 17 模拟器重新构建并运行。
- 确认卡片、取消、执行、App 重启恢复待确认卡片、协作记录均通过；确认前及取消后远程调用为 0，执行后为 1，重复确认返回 409 且调用数保持 1。使用隔离后端与本地假 MCP / 模型，未删除真实数据。详见 [验收记录](testing/2026-10-11-mcp-m3-simulator.md)。
- M3-05 委派能力由用户复测通过；MCP M3 确认卡片不再列为待验收项。

## 2026-10-10 · 游乐场游戏助手

- 游乐场标题行右侧的 Bot 头像打开游戏助手对话；首次点击创建账号内普通 Bot，后续复用并保留编辑及历史，遵循数量上限与默认权限。
- 游戏助手提供规则、推荐和分步提示，用户需提供局面信息；更换账号或离开页面时丢弃过期结果。

## 2026-10-10 · 创建页与协作记录显示

- 创建 Bot 页移除底部工具/委派默认状态说明分区；协作记录标题和双方名称使用 Bot 实际名称，不再附加头像形象名称。

## 2026-10-10 · Bot 创建 / 详情头像布局

- 两页头像行减少底部留白，保留分区间距；详情页昵称/标签系统分隔线两端与标准行内边距对齐。
- 创建页头像无背景单独展示，昵称与标签紧随其后；详情页头像无背景单独展示，昵称与标签共用一个分区，人设恢复独立分区。
- 两页共用一张选色卡，合并原头像主色与 Bot 选色卡；详情头像原生菜单提供「从相册选择」和可用时的「使用默认形象」，继续使用 PhotosPicker，保存时才提交头像变更。
- 两页昵称和标签输入居中，昵称使用原来的常规字号，去掉标签标题和昵称必填提示；人设恢复到选色卡下方的独立分区。

## 2026-10-10 · 头像实验室入口调整

- 调试页只保留新版头像实验室入口，并将入口与页面标题统一为「头像实验室」。

## 2026-10-10 · 文件附件已整合，待验收

- iOS 文件菜单已启用系统文件选择器；后端 schema v19 已增加文件存储、文本抽取和按需读取能力。支持 PDF/TXT/MD/CSV/DOCX/XLSX，10 MB，单消息一个附件。设备/真实模型验收尚未完成；解析器 15 秒硬超时已加入。

## 2026-10-10 · 对话页更多按钮

- 对话页导航栏右上角新增三点「更多」按钮，沿用系统原生圆形工具栏按钮样式；按钮暂为空操作。

## 2026-10-10 · 主线整合（验收状态更新至 2026-10-11）

- `main` 已纳入头像系统、俄罗斯方块陪玩、记忆成长 M2–M5；数据库迁移版本为 v19（v15 Bot 外观、v16 M3、v17 M4、v18 M5、v19 文件附件）。
- M3/M4/M5 自动化与模拟器构建沿用隔离分支记录；本次整合后尚未重跑。M3/M4 页面已由用户验收通过；M5 权限共享、反馈提示和两项修复复测通过，降级服务层验证通过；真实向量语义召回未单独记录验收。
- M5 的 BGE-small-zh 向量能力为可选本地依赖；未安装或不可用时回退关键词。Web 冻结。
- 当前工作区为本机 `main`，整合后可在主机上启动验收；代码已提交到本地 `main`，尚未推送本机记录的 9 个领先提交；具体验收结果见当前盘点。

## 2026-10-09 · 俄罗斯方块陪玩首版

- 已实现伙伴选择、在场形象、稀疏主动回应、安静陪伴、暂停聊天与本局回顾。 真实开局与手动局面交流接口已跑通；最终头像点按和聊天面板验收受独立模拟器系统首次启动阻塞，未标为已通过。
- 服务接口专项 4 项通过；Kit 182 项 Swift Testing + 1 项 XCTest 通过。模拟器与真实回应验收见 [验收记录](testing/2026-10-09-tetris-companion.md)；真机待用户验收，相关代码已提交并纳入本次主线汇总；本段验证记录为此前专项结果。

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

## 🔁 当前交接 (Handoff) — 2026-10-10 UTC+8

- **登录恢复**：修复未登录时成功 / 失败结果被丢弃及换账号后旧请求使用新令牌重试的问题；账号数据请求保留原鉴权检查。后端即时事务修复并发失败计数、注册去重与刷新轮换，并校验 bcrypt 密码字节上限。demo 和三个测试账号的主机 API 登录、资料读取均为 200；客户端回归 196 项、后端账号回归 18 项、稳定性回归 6 项通过。构建、安装与交互证据见 [登录恢复排查](testing/2026-10-10-login-recovery.md)。

## 🔁 历史交接记录 — 2026-10-07 UTC+8

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

## 📍 当前进度 (Current progress) — main 工作区 (2026-10-11)

当前本地 HEAD `c66f2d2`，相对本机 `origin/main` 引用领先 9 个提交；本次未访问远端更新引用，未核对开放 PR。代码 schema **v19**，iOS 版本 `0.1.0 (1)`，未发布新版本。最新状态以 [盘点](testing/2026-10-11-project-inventory.md) 和专项验收记录为准；下表旧测试数代表历史提交快照，不等于本次全量回归。

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
| **MCP M3 HITL** (写工具确认卡片；复用 v7 `pending_actions`) | PR #30，合并提交 `61b9b4f` | `mcp_m3_test.py` 23/23；MCP / 插件 / 并发回归通过；Kit `swift test` 156/156；iPhone 12 Pro Max 目标构建通过；2026-10-11 模拟器功能验收通过（用户指定标准） | MCP-10~13、M3-UI |
| **MCP M4 OAuth 2.1 + Google**（不升 schema） | 合并提交 `ed52159` | OAuth 假服务器与 MCP / 插件回归通过；Kit `swift test` 157/157；main 验收地址为 `127.0.0.1:8000` | MCP-20~21、刷新 / 撤销子集；真实 Google OAuth 待手工验收 |
| **MCP M2** (schema v8；按服务同意、会话复用、审计、后台同步、重试与熔断) | 见 CHANGELOG | 后端 `mcp_test.py` 本地假服务器通过（含 v7→v8）；真实公网用例默认跳过。iOS 未在本环境编译。Web 冻结，无对应界面 | MCP-CONSENT、MCP-SESSION、MCP-AUDIT、MCP-SYNC、MCP-RETRY、MCP-BREAKER、MCP-CONTRACT |
| **Bot 详情 / 创建页改版** (顶部卡片弹窗编辑头像 / 昵称 / 标签且「保存」才提交、「默认形象」分组、人设 / 指令独立分组、界面去英文、协作记录本地时间；仅 iOS) | 见 CHANGELOG | `swift test` 53/53；AV/NK 21/21；模拟器已构建 / 安装 / 启动；详情/创建 UI 验收延期 | DETAIL-UI-01~09 |
| **头像实验室** (独立页面；五款角色、八种状态、三种尺寸、按状态机演示；不写入 Bot 资料) | `7ebe99d`、`a29536f` 及之后 | 离屏检查 13/13；模拟器截图 / 录屏通过 (浅色 / 深色、演示、减弱动态效果)；Boss 于 2026-10-07 确认观感通过 | AVLAB-01、AVLAB-02、AVLAB-T01~T14 |
| **默认 Bot 形象** (实验室五款；照片优先；对话导航栏按 10 个执行状态动画，完成后 1.5 s 回空闲；首页 / 详情静态) | 见 CHANGELOG | 后端 AV-18。Kit 用例 EXEC-34~40 已加。iOS 模拟器未在本环境编译 | AV-18、EXEC-34~40、AVFIG-UI |
| **图片附件 P1 + 拍照 P2** (schema v12；PhotosPicker / 系统相机、磁盘存储 + SQLite 元数据、GIF、按需召回、委派带图、带图写操作需确认) | 主线已合入（附件 PR #14；拍照 commit `601ca39`） | Boss 于 2026-10-07 确认图片附件及拍照验收通过；后端附件用例 28/28，ATT-LIVE-01 真实 `deepseek-flash` 带图请求与 caption 持久化均通过 | ATT-01~18、ISO-ATT-01、ATT-CONTRACT、ATT-UI-01~04、ATT-CAM-01~03、ATT-LIVE-01 |
| App 图标、主屏显示名「Vera Bot」 | `b5eccd9`、`d824796` | 已构建 | — |
| 去掉列表数量页脚、账号信息并入设置、移除「恢复默认头像」入口 | `8794552` 等 | 对应 UI 验收延期 | UI-01~03、UI-10 |

### 后续实现 / 延期 / 待验收

| 项 | 状态 |
|---|---|
| MCP M5~M7、Gmail 邮件工具 | OAuth 连接已实现；邮件工具、变更审阅、自定义 URL / stdio 仍按设计稿待做 |
| 以记忆为核心的 Bot 成长体系 M2~M5 (摘要、风格校准、隐式候选、成长界面、向量检索) | M1–M5 已合入本地 main；M3/M4 用户验收、M5 共享 / 反馈复测及降级服务层验证通过；真实向量语义召回待明确验收记录（此行仅记录剩余验收） |
| 首页搜索扩展 (完整聊天历史搜索、搜索历史) | ⏸ 延期到后续迭代；当前只过滤已加载列表 |

### 已知遗留 (Known leftovers)

- **提醒编辑页旧缺陷**（2026-10-05 代码审查发现；修复已纳入当前 main 并随 App 安装，iPhone 目标构建通过；提醒编辑专项交互未验收）：修正了仅改标题仍回传旧排程、使用 snooze 时间、冲突重载不刷新版本、删除缺确认 / 吞错误、时间格式和原时区、日期 / 时间状态混用、关闭日期未清全天字段、重复出现时覆盖编辑态、打开日期后时间过期、备注清空、无日期开启日期默认全天，以及自定义 RRULE 丢失等路径；行内标签改为按钮。逐项验收仍待进行，尤其 DST、跨时区与点击命中区域。
- **相对时间解析**（实现已更新，尚未验证）：创建提醒时，对用户原话中可解析的中文秒 / 分 / 小时 / 天相对时间按服务器时钟重算并向上取整到分钟；范围仅覆盖明确数字或中文数词加「后」的表达。
- **改进建议：点按提醒通知先进只读详情页**：现在点按提醒通知直接进「编辑提醒」。建议改为先看详情 (标题、时间、来源、「查看对话」)，再从详情进编辑。路由规则不变 (仍不直接进对话，见 [REMINDER_PUSH_DESIGN.md](design/REMINDER_PUSH_DESIGN.md) §9.5)。
- **Web 客户端落后于 iOS**：没有迭代 2 的 iOS UI，也没有 2026-10-01 之后的全部 iOS 改动 (见 §2 第一条)。**默认 Bot 形象没有 Web 对应** (Web 冻结)：iOS 无照片时画五款实验室形象，`bots.avatar` 可能是 `veraBean` 等 id；Web 仍把该字段当文字 / 表情显示，不播状态动画。`/api` 未新增字段。**设置 › 用量「已用 N%」没有 Web 对应** (Web 冻结；Web 用量页仍是原有额度进度条，`/api/quota` 未变，不受影响)。**Bot 标签与置顶没有 Web UI** (Web 冻结；后端字段向后兼容)。**Bot 详情改版 (卡片弹窗编辑、默认形象分组、去英文、协作记录本地时间) 没有 Web 对应** (Web 冻结；未改 API)。**记忆 M1 没有 Web UI**：Web 不显示确认卡片 (记忆工具结果显示为普通工具卡片，无法在 Web 确认)，没有记忆页与 `memory_access` 设置；后端接口向后兼容，Web 现有功能不受影响。**MCP M1 / M2 没有 Web UI**（`frontend/web` 冻结，落后于这项功能）：没有服务列表、同意开关、同步状态、熔断状态或工具开关。`/api/mcp/servers` 多了 `consent_at` / `sync_status` / `circuit_state` 等字段，`/api/tools` 的可选字段仍可忽略。对话若模型调用了 MCP 工具，Web 仍只显示普通工具卡片。**插件 P1 没有 Web 对应**（`frontend/web` 冻结）：没有插件页。`/api/plugins/*` 是新接口；`/api/tools` 增加可忽略的 `plugin_id`；`GET /api/mcp/servers` 不再自动补未安装的目录行。
- **设计稿中的 schema 版本号**：v3 = 头像 / 昵称、v4 = 记忆、**v5 = Bot 标签**、**v6 = Bot 置顶**、MCP 表是 **v7**，M2 的同意 / 同步 / 熔断列是 **v8**，账号邮箱 / 手机号是 **v9**，插件安装表是 **v10**。Gmail 设计稿仍写与 MCP 共用 v7 表。

## MCP M1–M4 已实现；Gmail 邮件工具待做

Boss 决定把 MCP (Model Context Protocol) 作为 VeraBot 的一等能力，Gmail 优先通过 MCP 接入。两份设计稿已于 2026-10-01 由 Boss 批准为 **v1.0**。以记忆为核心的 Bot 成长体系方案 v1.0 已批准，记忆 M1–M5 已实现；验收按各阶段单独记录。

| 能力 | 设计文档 | 状态 | 需要 Boss 做的事 |
|---|---|---|---|
| MCP M1（Client、目录、只读工具开关、防注入） | [MCP_CAPABILITY.md](design/MCP_CAPABILITY.md) §18 | ✅ 已实现（schema v7） | 验收设置页与 Bot 详情的 MCP 开关。真实公网用例需 `VERABOT_MCP_LIVE_TESTS=1` |
| MCP M2（同意时间、会话复用、审计、后台同步、重试与熔断） | 同上 §18.3 | ✅ 已实现（schema v8） | 验收设置页的同意 / 同步 / 熔断。`frontend/web` 冻结，没有对应界面 |
| MCP M3（pending_actions、写操作确认卡片、工具调用记录） | 同上 §7 / §15 / §18.5 | ✅ 已实现并由 PR #30 合入 `main`（复用 v7 表，不升版本） | `mcp_m3_test.py` 23/23；Kit 156 项；iPhone 目标构建通过；2026-10-11 模拟器卡片交互验收通过 |
| 插件 P1（安装关系、内置 / 外部入口、卸载） | [PLUGIN_DESIGN.md](design/PLUGIN_DESIGN.md) v1.0；进度见 MCP §18.4 | ✅ 已实现（schema v10） | 新账号不预装。验收设置 › 插件、内置详情的工具权限导航、卸载确认。`frontend/web` 冻结，插件 P1 没有 Web 对应 |
| MCP M4（OAuth 2.1 + Google 连接） | 同上 §15 / §18.6 | ✅ 已合入 `main`，不升 schema | 真实授权需 Google Cloud OAuth 客户端、测试用户与 Workspace Developer Preview；由 Boss 手工完成 |
| MCP M5~M7（Gmail 工具、变更审阅、自定义 URL / stdio） | 同上 §15 | 未实现 | 按设计稿后续推进 |
| Gmail (主路径：Google 官方 Gmail MCP；备用：直连 Gmail API) | [GMAIL_CAPABILITY.md](design/GMAIL_CAPABILITY.md) | ✅ v1.0 已批准，未实现 | 在真实 M4 授权验收后推进邮件工具 |
| 以记忆为核心的 Bot 成长体系 | [MEMORY_GROWTH.md](design/MEMORY_GROWTH.md) | ✅ v1.0 已批准，M1–M5 已实现 | M3/M4 已验收；M5 降级服务层通过，真实向量语义召回待记录 |

**MCP M1–M4 已实现**，其上的 **插件 P1 已实现**（schema v10）。M4 仅提供 OAuth 连接，不提供 Gmail 邮件工具；M5~M7 未实现。原 M0 / G0 技术验证已取消。记忆 M1 占用 schema v4，Bot 标签占用 v5，Bot 置顶占用 v6，MCP 表占用 **v7**，M2 列占用 **v8**，账号占用 **v9**，插件安装表占用 **v10**。`frontend/web` 冻结。

## 1. 已完成功能 (Features done)

| 模块 | 状态 | 说明 |
|---|---|---|
| 账号 Accounts | ✅ | 注册 / 登录 (bcrypt + JWT)，Token 持久化，失效自动退出，设置页底部退出登录 (二次确认)。昵称 `PATCH /api/me`（设置页可编辑；首页与对话读同一 `AppState`） |
| 租户隔离 Isolation | ✅ | 所有查询带 `user_id`，越权 (IDOR) 返回 404 |
| Bot 管理 | ✅ (API) / 🟡 (标签部分 UI 延期) | 创建 (＋)、编辑 (Bot 详情 / 长按「编辑与权限」)、左滑删除；置顶支持左滑 / 长按，置顶项优先排序且 Boss 已验收；标签 UI 与 Bot 详情/删除流程验收延期；软上限 20 (`MAX_BOTS_PER_USER`)；名称右侧显示标签，行右上角显示最后消息时间；搜索只过滤已加载的 Bot 名称与最后消息预览，完整聊天历史搜索、搜索历史等延期 |
| 流式对话 SSE | ✅ | 逐 token 渲染、工具卡片、交接 Trace 卡片、错误气泡 |
| 记忆 Memory | ✅ | 显式长期记忆 M1、每 Bot 记忆分组、最近 20 条对话窗口；M1–M5 已实现；M3/M4 已用户验收，M5 共享 / 反馈与修复通过，真实向量语义召回待记录 |
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
| 输入栏 Composer | ✅ | 浮动玻璃：圆形 ＋（图片 / 拍照 / 文件） + 胶囊输入框 + 🎙；无发送按钮，return 发送；Boss 已验收 |
| 消息富文本 Rich messages | ✅ | Markdown 排版、自动识别网址 / 电话 / 邮箱、网页在 App 内打开、长按复制；解析有单元测试，Boss 已验收 |
| App 图标 / 名称 | ✅ | 主屏「Vera Bot」；AppIcon 1024 单尺寸 |
| 附件 Attachments | 🟡 部分 | ＋ 菜单：「图片」(PhotosPicker，P1) 与「拍照」(系统相机，P2，2026-10-04；无相机设备不显示) 可用；「文件」已启用系统文件选择器；PDF/TXT/MD/CSV/DOCX/XLSX、10 MB、单消息一个，设备验收待做 |

## 2. 已知限制 (Known limits)

- **iOS 与 Web 不对等**：Web SPA 没有迭代 2 的 iOS UI 改动 (权限编辑、协作记录、设置页、TTS)，也没有 2026-10-01 之后的改动 (昵称编辑、照片头像、调试页、通用设置、列表时间 / 搜索、Liquid Glass 视觉、浮动输入栏、富文本 / App 内网页、MCP 服务开关、M2 的同意 / 同步 / 熔断)，只作为 API 验收客户端。`frontend/web` 冻结，落后于 MCP M2。**Web 暂不支持删除单条消息**（iOS 长按「删除」，接口 `DELETE /api/bots/{bot_id}/messages/{message_id}`；Web 只有清空整段对话）。
- **HEIC**：服务端能认出 HEIC 文件头；未安装 `pillow-heif` 时返回 415。iOS 在上传前把相册图片转成 JPEG，不依赖服务端解 HEIC。
- **头像存在 SQLite `avatars.data`**：512 JPEG，单张大约几 KB 到几十 KB。备份数据库即包含头像。
- **提醒通知边界**：已有本地通知和站内通知；尚无 APNs 服务端推送，App 关闭后的远程主动触达未实现。
- **语言**：App 声明了 zh-Hans 与 en 本地化（仅 `InfoPlist.xcstrings`：显示名与权限文案），系统设置中可按 App 切换语言；但界面文案仍是中文硬编码，切到英文后 App 内界面仍为中文。
- **列表时间不会自动跨天刷新**：停留在首页跨过午夜时，「HH:mm」不会自己变成「昨天」；回到首页或下拉刷新后更新。「本周」按系统日历的周（中文地区周一开始）计算。
- **首页搜索暂延期扩展**：搜索入口保留；当前只过滤屏幕上已加载的列表（Bot 名称 + 最后一条消息预览），完整聊天历史搜索、搜索历史等移至后续迭代。
- **记忆**：M1–M5 已实现，M3/M4 已验收；本地向量为可选依赖，不可用时回退关键词；真实向量模型端到端语义效果未单独记录。
- **部署边界**：iOS Token 已存 Keychain，已有刷新、登录限流与账号锁定；Web 仍为 localStorage。IP 限流为进程内存，多实例共享限流未实现；CORS `*`、开发 HTTP / ATS 配置仍需生产收敛。
- **云端 TTS**：只是占位 (stub)，设置里置灰。
- **后端不会开机自启**：Mac 重启后需要重新运行 `backend/start.sh --detach` (或双击 `start.command`)；日志在 `backend/data/server.log`。
- **Docker 未实测**：`Dockerfile` / `docker-compose.yml` 已提供，`docker compose config` 校验通过；但测试机的 Docker daemon 未运行，镜像没有实际构建 / 运行过。
- **Bot 详情 sheet 内没有键盘「完成」按钮** (KB-12 修复所致)：用 下拉表单 / 保存 / 关闭 收起键盘。
- **截图过时**：全部 iOS 截图早于 2026-10-01 的界面改动；`R34_form_keyboard` 仍显示已移除的键盘工具栏「完成」；`R11_settings` 是旧的分组顺序 (语音在前)。

## 3. 未测 / 仅代码审查 (Untested / code review only)

| 项目 | 状态 |
|---|---|
| TC-07 Token 失效处理 | 通过：无效 token 时 `/api/me` 返回 401，App 自动跳转登录页 (iPhone 17 模拟器，2026-10-01) |
| 真机 (Real device) | iPhone 11 已安装并启动当前主线，登录连通；MCP M3 按用户指定标准完成模拟器验收。提醒编辑交互保持原有待验收状态 |
| 昵称 / 照片头像的 iOS 界面 | Boss 手工验收通过 (2026-10-01) |
| 首页正圆头像、圆形 X 取消 / 关闭、行时间、首页搜索 (UI-11~14) | Boss 手工验收通过 |
| iOS 17 / 18 旧系统 | 未测 (`defaultScrollAnchor` 等 iOS 18+ API 已做版本判断) |
| 白底 + Liquid Glass、深色模式 (UI-16~19) | 首页、设置、对话、主要列表已验收；新建 Bot / 提醒 / 登录 / 调试页验收延期 |
| 浮动玻璃输入栏 (UI-20)、return 发送 | Boss 手工验收通过 |
| 消息富文本 / App 内网页 / 长按复制 (MSG-01~04) | 解析 `swift test` 通过；Boss 手工验收通过 |
| 动态字体 (Dynamic Type)、iPad | 未测 |

## 4. 下一步 (Next steps)

1. **提醒编辑交互验收**：验收保存 / 删除 / 时区行为并记录结果；提醒页视觉修复已通过。MCP M3 确认卡片已按用户指定的模拟器标准验收通过。
2. **M4 真实 OAuth 手工验收**：需配置 Google Cloud OAuth 客户端、测试用户和 Workspace Developer Preview；完成授权、取消、重启保持、scope step-up、失效刷新及断开 / 撤销验收后，再推进 Gmail 工具。
3. **完成剩余手工验收**：记忆 M1、用量、Bot 标签、详情 / 创建页、单条消息删除、MCP / 插件页面，以及尚未覆盖的视觉页面；按 [TEST_CASES_v0.1.md](testing/TEST_CASES_v0.1.md) 的待验收项逐项记录。
4. **连接器真实冒烟**：CONN-LIVE-01~06 需要 GitHub / Linear 测试令牌与测试仓库；连接器 UI 验收也仍待完成。
5. **真实向量语义效果**：M3/M4 和 M5 共享 / 反馈已通过；M5-04 服务层降级通过。仅补足真实本地模型语义召回验收记录，避免将已通过项重复列为待测试。
6. **平台覆盖**：APNs 尚未实现；iOS 17 / 18、Dynamic Type、iPad 等覆盖仍未验证。路线图见 [ROADMAP_NEXT.md](ROADMAP_NEXT.md)。
