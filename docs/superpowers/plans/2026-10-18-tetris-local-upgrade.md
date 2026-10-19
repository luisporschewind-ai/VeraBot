# 俄罗斯方块本地操作、规则与陪玩实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Subagent-driven execution only when separately authorized; this document does not dispatch agents.

**Goal:** 先独立交付已确认的掌机v2，再按范围确认推进确定性规则和陪玩改进。

**Architecture:** 将私有游戏规则提取到 VeraBotCore，SwiftUI 消费状态和事件。输入重复与游戏时钟分离，陪玩消费真实事件；L1先保留行为，L3才改变规则。

**Tech Stack:** Swift 6、SwiftUI、Swift Testing、现有 FastAPI 陪玩接口；无新依赖。

**Spec:** [执行基线 §1–5、§8](../specs/2026-10-18-game-upgrade-execution-baseline.md)、[已确认掌机v2](../../product/2026-10-18-tetris-controls-visual-proposal.md)。

**状态（2026-10-19）：**用户已将本计划交DeepSeek Harness，执行已结束；当前main中L2控件/长按已有实现，L1/L3/L4未见完整交付，不能标全计划完成。L2待补已确认图的A/B相对位置、菜单暂停/输入取消/倒数与专项测试；详见[核对证据](../../tasks/2026-10-19-game-plans-progress-audit.md)和[总账](../../tasks/2026-10-18-game-upgrade-progress.md)。以下保留原实施要求，复选框表示整步完成，不把部分代码等同全部验证通过。

## Global Constraints

- iOS最低17，Intel Mac为当前构建环境；保留 Swift Package Mac 测试路径。
- 无新第三方依赖、无全局头像重写、无 Web 改动。
- 原清行100/300/500/800，缓降+1/格、硬降+2/格；保留聊天、换伙伴、安静模式、失败重试。
- 掌机按键映射、最小44pt命中区、输入180/70ms与全部清理条件按执行基线§3执行。
- Xcode工程使用显式引用，新增/移除App文件同步pbxproj；包内文件由SPM发现。
- 只修改本计划文件及直接支持项，保护同一工作区的贪吃蛇、布局、音效方案和无关改动。

## Review Focus

- 旧输入/计时器在暂停、离页、重开后醒来，不能推动新局（L2输入代次测试及V-02）。
- 快速反向、同时左右、多指和滑出时不能双发或继续粘键（L2纯输入测试及双机实测）。
- 清行与落地发生在同一步、动画中暂停，不能重复计分或生成两块（L3状态测试）。
- 换伙伴/账号/重开后迟到文本或表情不能污染当前局（L4代次测试）。
- 小屏、大字体、照片头像和减少动态效果不挤掉棋盘或功能入口（L2/L4人工验收）。

## 文件与职责

- Create Core：`frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/TetrisGame.swift`（状态/动作/事件）、`TetrisInputState.swift`（按键重复）、`TetrisRules.swift`（L3形状/试移/随机）。
- Create App：`frontend/ios/VeraBot/Features/Playground/TetrisGameView.swift`（页面/生命周期）、`TetrisControlsView.swift`（掌机控件）、`TetrisGamePresentation.swift`（颜色/渲染映射）。
- Modify：`MiniGameViews.swift` 移出Tetris相关声明但保留其他游戏；`TetrisCompanionModel.swift`、`TetrisCompanionViews.swift`；`Core/UI/Haptics.swift`只扩展必要按压复用；`VeraBot.xcodeproj/project.pbxproj`。
- L4 Core新建`frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/TetrisCompanionReactionPolicy.swift`（反应策略与代次值类型），修改`TetrisCompanionPolicy.swift`；Networking：`TetrisCompanion.swift`只在确有新增字段时改动；Backend：`backend/verabot/services/tetris_companion.py`、`backend/verabot/api/routers/chat.py`只收敛自动字数及新增事实字段。
- Tests：同包 `Tests/VeraBotKitTests/TetrisGameTests.swift`、`TetrisInputStateTests.swift`、既有`TetrisCompanionTests.swift`；`backend/scripts/test/tetris_companion_test.py`。

## L1：提取现有规则与真实事件，不改变玩法

**Interfaces:** produces 基线§4的 `TetrisGame`/`TetrisState`/`TetrisAction`/`TetrisEvent`；ruleVersion先为`legacy-1`。状态只读，对外不允许任意写board/isPaused。UI通过apply/advance驱动。

- [ ] 新建 `@Suite struct TetrisGameTests`，先断言当前规则：`hardDrop`累计每格2分且仅locked一次；四行800分、下一块只生成一次；暂停后advance/move不改变board/score；出生阻挡over。用固定初始fixture通过`init(restoring:)`构造，不暴露生产调试setter。新API缺失应编译失败；若仅因工程配置失败，修正后重新获得有效红灯。
- [ ] Run `swift test --package-path frontend/ios/Packages/VeraBotKit --filter TetrisGameTests`，记录有效失败原因，再从MiniGameViews迁移旧算法和旧旋转/随机行为。L1暂不启用七袋、ghost、lock delay或ready新机制。
- [ ] `apply/advance`返回事件；每个事件序号递增，失败动作不产生成功结果事件。UI颜色留在App，Core无SwiftUI。页面迁移到新文件，所有原功能使用state访问；整理显式工程引用，避免旧类型同名残留。
- [ ] 重跑规则测试，预期0失败；`swift test --package-path frontend/ios/Packages/VeraBotKit --filter 'SnakeGameTests|TetrisCompanion'`确认相邻功能。检查无重复TetrisGame声明。
- [ ] 独立构建当前App并记录结果；只有本任务有实际产物才更新总账L1。若后续授权提交，仅暂存本任务代码/测试/文档，不使用`git add .`。

## L2：掌机控件、输入取消与恢复倒数

**Consumes:** L1动作/状态。**Produces:** `TetrisControlsView(phase:onPress:onRelease:onAction:onCancel:)`；`TetrisInputState.press(_:atMilliseconds:) -> [TetrisAction]`、`advance(toMilliseconds:) -> [TetrisAction]`、`release(_:)`、`cancel()`。纯输入只接受left/right/softDrop；A/B由原生Button各发一次动作。时间来自同一可注入单调时钟。

- [ ] 新建 `@Suite struct TetrisInputStateTests`：pressLeft(0)产出1次；advance(179)无输出；advance(180)1次；advance(250)1次；cancel后advance(500)为空。再测右键抢占后释放不恢复旧左键、同一时刻重复press不双发、时间倒退不追发。
- [ ] Run `swift test --package-path frontend/ios/Packages/VeraBotKit --filter TetrisInputStateTests`，先红后实现；过大elapsed最多派发当前一次并重设下一重复点，避免主线程恢复后一串补发。页面单一repeat任务带UUID代次，cancel后旧任务无效。
- [ ] 按基线§3制作一体十字键及斜排圆A/B，控制可见键帽与命中区分开、无重叠；所有控件有中文accessibilityLabel。上臂/中心不响应，菜单包含玩法/重开/已有陪玩入口；重开确认后清旧状态。加入3/2/1倒数，倒数时任一暂停/菜单/后台取消，不消耗游戏时间。
- [ ] 绑定按下沿触感，A/B松开/取消不双发；暂停、菜单、聊天、伙伴选择、后台、离页、结束、重开统一cancel输入和倒数。停用方向/A/B时不震动；保留减少动态效果下静态反馈。
- [ ] 测试输入全绿；构建/安装当前可审查包，按人工清单V-01/V-02验收。手工核查320/375/414pt宽、深色、减少动态效果、大字体；不能只凭生成图或构建标通过。同步总账L2及图稿与实现差异，L3未做仍可交付。

## L3：固定vera-tetris-2规则、可恢复状态与落点预览

**前置：**新增机制范围确认；L1完成。**Produces:** 基线§4完整v2状态、确定性advance、ghostCells、跨平台可编码状态；不向旧局静默替换规则。

- [ ] 扩展`TetrisGameTests`的用例及精确断言：每袋7种唯一；同seed同动作同毫秒状态相同；advance(100)等于10次advance(10)；500ms触地锁定；第15次成功微调可刷新、第16次不能；O/阻挡不刷新；hardDrop不等500ms。以测试固定基线的形状、变换和逐项kick优先级。
- [ ] 添加`ghostEqualsHardDropLanding`、顶部负行锁定不部分写盘、清行180ms内玩法输入无效、暂停清行余时不消耗、一次事件仅计分一次、终局不可resume、非法JSON恢复被拒绝。先运行专项测试获得失败，再实现TetrisRules与v2状态转换。
- [ ] 从基线明确的PRNG/洗牌/形状/自定义kick实现算法；timing用整数10ms步与余数。round新建ready、旧legacy局留在原版本到退出，不转换云端。序列化同时保存动画和计时状态，恢复前校验范围/相位一致性。
- [ ] 加入同碰撞算法的ghost轮廓、180ms消行与非布局式状态覆盖。UI在本地动画和规则状态之间不自行加分/生成块；暂停菜单仍保持完整棋盘。更新玩法说明为真实计分与操作，不声称标准SRS。
- [ ] `swift test --package-path frontend/ios/Packages/VeraBotKit --filter 'TetrisGameTests|TetrisInputStateTests'` 全绿；再执行包全量测试与单次App构建。填V-03，生成C1所需稳定恢复fixture并记录ruleVersion。不得因测试通过标记云端已实现。

## L4：陪玩事件反应、额度与回顾

**Consumes:** L1/L3真实事件和快照。**Produces:** `TetrisCompanionPolicy.reserve(event:at:) -> Bool`，`event`为start/highlight/end；保留旧reserve(at:)兼容直到调用迁移完毕。`TetrisCompanionReactionPolicy.consume(event:height:at:) -> Reaction?`是Core纯逻辑，Reaction仅含kind/duration，App映射既有BotAvatarState。

- [ ] 在`TetrisCompanionTests`新增：start@0和highlight@30后highlight@60被拒，end@60可预留第三次；end@59因冷却拒绝且不消耗额度；失败预约已计次、quiet拒绝、换Bot不补额度、新局重置。反应策略测height14→15一次warning，15→16不再warning，降至12后再15可再触发。
- [ ] 先跑 `swift test --package-path frontend/ios/Packages/VeraBotKit --filter TetrisCompanion` 红灯，实施基线§5。UI驱动器所有延迟清泡/复位任务记录round+partner+account代次，迟到回调只允许匹配者应用；为此抽出 `TetrisCompanionEpoch.accepts(round:partner:session:) -> Bool`并测试错一项即false。
- [ ] 每次消行/危险/暂停/终局按真实事件显示本地反应；照片头像保留外层状态表达。气泡5s收起但turns保留；用户手动交流打断自动请求，不吞用户输入。终局主动额度或冷却不满足时给“本局回顾”明确入口，关闭聊天不自动继续。
- [ ] 后端自动回应上限24、聊天180；改`backend/scripts/test/tetris_companion_test.py`原60断言为24，再运行 `cd backend && .venv/bin/python scripts/test/tetris_companion_test.py`，先红后修改自动返回截断与prompt，保持鉴权、预算、history上限与不调用工具约束。不新增后台模型循环。
- [ ] 跑Swift陪玩与后端专项回归，记录V-04，构建并人工核查普通/照片头像、安静模式、错误重试、换伙伴和切账号。完成后更新总账L4；用户验收独立记录。

## 验证与交付命令

包专项/全量：上述`swift test`，最后 `swift test --package-path frontend/ios/Packages/VeraBotKit`，预期退出0。工程检查：`plutil -lint frontend/ios/VeraBot.xcodeproj/project.pbxproj`；`git diff --check`。

App构建优先使用XcodeBuildMCP：先确认defaults，再按用户指定的模拟器或真机目标单次构建。真机工具不可用时使用已验证流程 `xcodebuild -project frontend/ios/VeraBot.xcodeproj -scheme VeraBot -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/verabot-tetris-local -allowProvisioningUpdates build`，预期`BUILD SUCCEEDED`；获得安装授权后同一包依次安装两台iPhone，分别记录启动与人工验收，禁止同时多个build。

## 计划自检与执行交接

已将设计每一项对应到L1–L4；时间、类型与枚举来源统一为执行基线，V-01…V-04覆盖自动测试不足项。该文档是执行计划，不是执行结果。下一入口L1→L2，L3/L4在范围评审后执行；默认由当前会话逐任务实施，只有明确授权才使用子代理。实际开始实现前读取基线、此计划和总账，不重新猜测已确认映射。
