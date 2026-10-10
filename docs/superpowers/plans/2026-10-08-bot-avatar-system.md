# Vera Bot 新版形象体系 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在新版实验室内增加六种手动状态、共享参数化模板和可持久化的外观配置。

**Architecture:** 单一状态描述和时钟驱动眼睛、头部、天线，模板只提供几何与锚点。外观配置是带版本的纯数据文档，后端保存独立 appearance 字段，Swift 与实验室分别负责编解码和预览。正式头像与执行状态机保持现状。

**Tech Stack:** Swift 6、SwiftUI Canvas、VeraBotCore、Swift Testing、Python 3.11+、FastAPI / Pydantic 2、SQLite；不增加依赖。

**Spec:** `docs/superpowers/specs/2026-10-08-bot-avatar-system-design.md`

## Global Constraints

- 回退基线：`avatar-lab-robot-v1` → `c35e62523e878de693fe7934b4007bdf6f07a35d`；不移动此 tag。
- 原有 17 状态、双心、天线闪动频率和 80% 可见 / 20% 不可见保持现有版本。
- 新增六状态只由实验室手动选择，不修改 ExecutionState、BotAvatarPose 或聊天状态映射。
- 天线和眼睛 / 头部来自同一个状态采样，禁止另建独立天线状态或计时器。
- 新模板目前只有 `cx-robot`；其他具体形状等待用户提供。
- 原三个快捷配色与截图的 11 色选色卡均保留，P3 和 sRGB 色域分别保存。
- appearance schema_version=1；有限颜色分量 [0,1]；roundness [0,1]；编码 ≤4096 UTF-8 字节。
- 正式列表与聊天头像、照片优先、旧 avatar / color 和 Bot 权限不随实验保存而改变。
- 测试使用临时数据库，不启动正式迁移，不修改 Web 界面，不新增依赖。
- 保留用户本地 project.pbxproj、InfoPlist.xcstrings 与既有 OAuth 计划。
- 当前保存点的提交 / tag 已完成；下一版不自动提交、打 tag 或推送。

## Review Focus

- 拖拽或挤压结束仍覆盖动作：回弹 / 短反馈结束后恢复同一状态的时间线，而非回空闲。
- 旧服务端忽略新字段：只有返回配置与提交内容一致时才提示保存成功。
- PATCH 未提供与明确 null：普通资料更新不清空 appearance，明确清除才写 NULL。
- 未安装模板 / 未来版本：读取保留原始文档，不能让整个 Bot 解码失败或自动覆盖成机器人。
- 更换 Bot 或离开保存页面时仍有请求：完成结果必须匹配发起时的 Bot ID，失败保留对应草稿。

---

## Task 1: 外观文档与 Swift 兼容模型

**Files:**
- Create: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/BotAppearance.swift`
- Modify: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/Models.swift`
- Test: `frontend/ios/Packages/VeraBotKit/Tests/VeraBotKitTests/BotAppearanceTests.swift`

**Interfaces:**
- `BotAppearanceColor`：space / red / green / blue，Codable、Hashable、Sendable；space 支持 srgb / display-p3。
- `BotAppearance`：schemaVersion / templateID / templateVersion / palette(body,eyes) / parameters(roundness)，Codable、Hashable、Sendable。
- `BotAppearance.validate() throws`：按规格校验数值、标识、版本、未知字段和编码长度。
- `Bot.appearance: JSONValue?`：原始文档；`supportedAppearance: BotAppearance?` 只解析支持的有效 v1；`appearanceFieldPresent: Bool` 记录服务端是否真的返回该键，区分旧响应缺省和已明确清除的 null，此标记不编码回服务端。
- `BotPatch.appearance: JSONValue?`：nil 不编码，`.null` 清除，`.object` 替换；BotCreate 同样可省略。
- `BotAppearance.jsonValue() throws -> JSONValue`：产生服务端一致的 snake_case 字段。

- [ ] 写测试 `appearanceP3RoundTrip`、`legacyBotWithoutAppearanceDecodes`、`unknownVersionAndTemplateSurviveBotDecode`、`patchAppearanceOmittedNullAndObject`、`appearanceRejectsInvalidValues`。覆盖规格示例、负值 / 越界 / NaN、布尔分量、额外字段及 4096 字节限制；未知模板原始 JSON 保留。
- [ ] 在包目录运行 `swift test --filter Appearance`，确认新增符号缺失导致失败。
- [ ] 实现模型及 JSONValue 桥接；不把当前动作存入 appearance。保留旧 Bot / BotCreate / BotPatch 调用的默认参数兼容。
- [ ] 重跑 Appearance 测试，再跑 `swift test`，确认现有资料、照片、头像映射及网络编解码测试没有回归。

## Task 2: 后端 appearance 保存契约

**Files:**
- Create: `backend/verabot/core/appearance.py`
- Create: `backend/verabot/db/migrations/v015_bot_appearance.py`
- Modify: `backend/verabot/db/migrations/__init__.py`
- Modify: `backend/verabot/db/schema.py`
- Modify: `backend/verabot/db/repository.py`
- Modify: `backend/verabot/api/schemas.py`
- Modify: `backend/verabot/api/routers/bots.py`
- Modify: `backend/verabot/services/bots.py`
- Test: `backend/scripts/test/bot_appearance_test.py`

**Interfaces:**
- `AppearanceV1`：严格 Pydantic 文档模型，与 Task 1 同字段 / 数值 / 大小约束。
- `validate_appearance(value: dict) -> dict`：返回规范化 v1 数据或抛验证错误；模板 ID 允许合法但未安装的值。
- `migrate(c, ver: int) -> None`：幂等增加 nullable appearance TEXT。
- `_bot` 与 `public_bot`：返回 JSON 对象 / null；历史缺字段或坏 JSON 不影响整个列表读取。
- BotIn / BotPatch 增加字段；PATCH 使用 `model_fields_set` 区分缺省、null、对象。

- [ ] 写临时数据库 TestClient 测试，创建 v14 存量 Bot 后运行两次迁移；验证 POST/GET/list/PATCH/clear 往返、普通 name PATCH 保留外观、用户隔离、所有非法参数返回 422、旧字段与权限 / 照片不变。
- [ ] 在 backend 运行 `uv run python scripts/test/bot_appearance_test.py`，确认缺列 / 字段导致失败。
- [ ] 再次核对实际 SCHEMA_VERSION 为 14，然后登记 v015；若已有其他新版本，顺延编号且更新本文与规格，禁止覆盖迁移。DB 只保存规范 JSON，appearance 的 null 不走现有过滤 None 的普通字段分支。
- [ ] 重跑新脚本及 `uv run python scripts/test/avatar_profile_test.py`，确认幂等迁移与现有头像契约通过。

## Task 3: 统一状态描述与六种工作表现

**Files:**
- Create: `frontend/ios/VeraBot/Features/Settings/BotAvatarState.swift`
- Create: `frontend/ios/VeraBot/Features/Settings/BotAvatarWorkMotion.swift`
- Modify: `frontend/ios/VeraBot/Features/Settings/RobotAvatarView.swift`
- Modify: `frontend/ios/VeraBot/Features/Settings/RobotAvatarMotion.swift`
- Create: `frontend/ios/Tools/RobotAvatarHarness/main.swift`
- Create: `frontend/ios/Tools/RobotAvatarHarness/run.sh`

**Interfaces:**
- `BotAvatarState: String, CaseIterable, Identifiable`：原 17 状态先后顺序不变，后加 thinking / recalling / working / delegating / replying / awaitingConfirmation（rawValue awaiting-confirmation）。保留 `typealias RobotAvatarAction = BotAvatarState`。
- `BotAvatarState.descriptor: BotAvatarStateDescriptor`：title / detail / category / continuous / loopMS / demoMS / antennaPeriodMS；原版频率来自该描述，禁止另一张映射表。
- `BotAvatarWorkMotion.sample(_ action: BotAvatarState, ms: Double, reduced: Bool) -> RobotAvatarMotion.Frame`。
- Frame 增加 `antennaOffsetX / antennaOffsetY`，默认 0；原 17 个动作采样不变。
- duration：六种工作状态无限；demoMS 均 4800；循环分别 2400 / 2800 / 1800 / 2400 / 1200 / 2400ms，天线周期按规格表。

- [ ] 建立纯 Swift harness，直接编译真实 Foundation 动画 / 状态 / 交互源文件，不复制枚举；先断言原 17 顺序、23 唯一状态、六种持续状态周期与天线频率。采样点覆盖开头、边界前后、每个动作结束和 0～60 秒；减弱动态时无闪动。
- [ ] 运行 `frontend/ios/Tools/RobotAvatarHarness/run.sh /tmp/vera-avatar-system-checks`，确认新状态缺失失败。
- [ ] 移出原枚举到 BotAvatarState；保留旧曲线与旧原版 flash 数据。实现规格中的六状态：进入 200ms，之后相位 `(ms-200)%loopMS`，周期边界位置 / 一阶速度连续；统一帧中的天线姿态来自同一相位。
- [ ] 在 harness 验证全状态 demo 时长有限且无遗漏、原 17 峰值和时长与 tag 一致、新状态循环边界连续（位置误差 <0.05 单位、相邻速度差 <0.01 单位/ms）。给六状态生成可用于真机查看的关键时间清单。

## Task 4: 参数化模板与交互恢复

**Files:**
- Create: `frontend/ios/VeraBot/Features/Settings/BotAvatarTemplate.swift`
- Create: `frontend/ios/VeraBot/Features/Settings/BotAvatarTemplateGeometry.swift`
- Modify: `frontend/ios/VeraBot/Features/Settings/RobotAvatarGeometry.swift`
- Modify: `frontend/ios/VeraBot/Features/Settings/RobotAvatarView.swift`
- Modify: `frontend/ios/VeraBot/Features/Settings/RobotAvatarInteraction.swift`
- Test: `frontend/ios/Tools/RobotAvatarHarness/main.swift`

**Interfaces:**
- `BotAvatarTemplateRegistry.resolve(id: String, version: Int) -> BotAvatarTemplate?`：当前仅 cx-robot / 1。
- `BotAvatarTemplate`：leftEyeAnchor / rightEyeAnchor / antennaAnchor / antennaRadius / drawingMargin / capabilities；cx-robot 分别 (86,126)、(154,126)、(120,12)、15、40。
- `BotAvatarTemplateGeometry.head(template:parameters:interaction:) -> Path`：机器人调用现有 baseline 路径，不复制。
- RobotAvatarView 增加 appearance 默认参数；从模板定义读取锚点与外溢空间，原调用仍可使用。
- `RobotAvatarInteraction.finish()`：临时反馈结束清理 overridesAction，而不是在回弹尚未完成时清除。
- View taskKey 排除 ambient；通过 State 镜像接收 ambient 更新，更新眨眼 / 视线而不更改 elapsed 或天线位置。动作 / 重播 / 可见性仍控制动画任务。

- [ ] 在 harness 写 `interactionResumesCurrentStateAfterFeedback`：拖天线 / 头部 / 挤压后等待恢复，断言 overridesAction 清除；原版本此测试应失败。保留四尺寸八方向和天线边界检查。
- [ ] 写模板锚点 / 范围检查；用仅测试的不同锚点定义验证眼睛和天线确实使用模板参数，不向产品登记额外形象。
- [ ] 实现模板注册、路径适配、交互恢复和 ambient 时钟解耦；天线 target 使用模板锚点＋同状态 offset 后随 headTransform 映射。保持原版不可见期间的命中行为。
- [ ] 重跑 harness，构建模拟器；与 tag 关键帧比较机器人轮廓、双心、颜色和天线。实际检查输入状态拖拽后恢复闪动、自然动态开关不重播，以及减弱动态效果。

## Task 5: 实验室入口、演示与外观草稿

**Files:**
- Modify: `frontend/ios/VeraBot/Features/Settings/RobotAvatarLabView.swift`
- Create: `frontend/ios/VeraBot/Features/Settings/BotAvatarAppearanceLabView.swift`
- Create: `frontend/ios/VeraBot/Features/Settings/BotAvatarAppearanceSaveView.swift`
- Create: `frontend/ios/VeraBot/Features/Settings/BotAvatarLabPlayback.swift`
- Create: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/BotAppearanceDraft.swift`
- Create: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotNetworking/BotAppearanceSaveService.swift`
- Create: `frontend/ios/VeraBot/Services/Avatar/BotAppearanceLabStore.swift`
- Create: `frontend/ios/Packages/VeraBotKit/Tests/VeraBotKitTests/BotAppearanceDraftTests.swift`
- Create: `frontend/ios/Packages/VeraBotKit/Tests/VeraBotKitTests/BotAppearanceSaveTests.swift`
- Modify: `frontend/ios/Tools/RobotAvatarHarness/main.swift`

**Interfaces:**
- `BotAppearanceDraft.init(saved: BotAppearance)`、`update(_ value: BotAppearance) throws`、`cancel()`、`markSaved()`：saved / current 文档、isDirty，cancel 回到 saved；成功保存才替换 saved。
- `BotAppearanceLabStore.init(directory: URL)`、`load() throws -> BotAppearance?`、`save(_ appearance: BotAppearance) throws`：默认 Application Support 的独立实验 JSON，测试注入临时目录；原子写入，损坏时显示可恢复提示，不静默覆盖。
- `BotAvatarLabPlayback`：mode=none / all / currentLoop / transitions，sequence 与 holdMS 来自 Task 3 状态描述；以 serial 防止已取消任务更新。
- `BotAppearanceSaveService.init(api: any VeraBotAPI)`、`save(botID: Int, appearance: BotAppearance?) async throws -> Bot`：appearance 非 nil 替换，nil 明确清除；使用现有 updateBot，PATCH 仅 appearance。返回 Bot ID、appearanceFieldPresent 和配置必须与请求匹配，否则抛出明确的保存错误。
- SaveView 调用上述服务，读 / 写目标是明确选择的 Bot ID；UI 用请求 serial 和目标 ID 拒绝过期完成结果。

- [ ] 写草稿测试：预览不保存、取消还原、失败保留草稿；写播放 harness 断言：23 项顺序、进度、原动作 duration+800、新状态 4800ms、停止 / 换动作使旧 serial 无效、固定状态切换序列符合规格。
- [ ] 运行对应测试确认缺模型 / 播放控制导致失败，再实现上述模型。
- [ ] 新版实验室保留原预览和入口位置；增加“状态演示”“形象与配色”“外观配置”入口。状态按钮分原版和工作组；演示全 23 项、循环当前、状态切换测试均用同一控制器。
- [ ] 外观页共用主预览配置，保留三个快捷色 / 11 色 / 四尺寸 / 圆角；保存页支持本机保存 / 加载、指定 Bot 读取 / 保存 / 明确清除，提示正式头像暂未切换。
- [ ] 对保存操作写 Fake VeraBotAPI 测试：旧响应无 appearance 不报成功、返回不一致不报成功、网络失败保留草稿、切换 Bot 不把旧响应当新目标保存成功、明确清除发送 null。测试临时目录中的本机原子保存及损坏文档读取。
- [ ] 实际验证重进页面恢复外观且状态回正常；手动六状态、23项整轮、当前循环及切换测试、停止、离屏 / 后台、配置保存失败和重试。

## Task 6: 集成验收与交付记录

**Files:**
- Modify: `docs/design/ROBOT_AVATAR_LAB.md`
- Modify: 本实施计划中的完成标记与验证记录。

- [ ] 在包目录运行 `swift test`；在 backend 运行新外观脚本、现有头像资料脚本；运行 RobotAvatarHarness，全部成功才继续。
- [ ] 使用 XcodeBuildMCP 核对 session defaults，iPhone 17 / iOS 26 构建、安装、启动；录制 23 状态完整演示和六状态单独循环，查看关键帧确认天线与表情共同表达。
- [ ] 使用隔离测试后端验证指定 Bot 外观读写与跨账号访问；禁止利用正式 Bot 或正式数据库做试写。检查保存前后的旧 avatar / color / has_avatar / 权限字段相同。
- [ ] 验证 32/44/96/160、浅深色、系统减弱动态、拖拽打断后恢复、快速切换、自然动态开关不重置计时。
- [ ] `git diff --check`、检查最终 diff 的文件白名单和现有用户改动；确认旧实验室、正式头像和 ExecutionState 文件无新修改，tag 仍指向保存点。
- [ ] 更新说明：23 状态、模板边界、appearance 格式和兼容行为、入口 / 保存步骤、实际验收结果及尚未进行的真机测试。交付代码供用户测试，不自动提交 / 推送。

## 计划自检

已覆盖六点用户要求、规格中的状态 / 天线 / 模板 / 保存 / 实验入口 / 兼容与取消语义。
Task 1 与 2 独立验证保存契约，Task 3 与 4 验证共享绘制和交互，Task 5 消费两组接口；
Task 6 完成跨层验收。正式状态机接入和用户尚未提供的形状均不在本次实施范围。

建议执行方式：由当前助手在本对话逐项实现；先完成 Foundation 数据与运动测试，
再处理绘制与页面，避免多个实现者同时修改 RobotAvatarView / 实验室和共享契约。
本计划目前未执行，需审核计划并确定执行方式后开始。
