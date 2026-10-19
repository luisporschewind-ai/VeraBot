# 2026-10-18 · 游戏音效 v1（俄罗斯方块 + 贪吃蛇）

日期：2026-10-18（实现于 2026-10-19 凌晨）。按 [游戏音效方案](../product/2026-10-18-game-sound-effects-proposal.md) §2 / §4 / §5 落地首版：约 10 个短音，共用播放器，素材自行合成、无第三方授权。只改 iOS + 音频资源，不改后端。

2026-10-19核对：已合入main，实读10个WAV共66,328 bytes；后续集成文档称模拟器构建安装通过，首次“未构建”记录保留其环境范围。本轮未重跑或听测；原完整音效计划A1–A3部分完成，A4未见双机验收。会话标记不等于租约所有权，按事件池不等于全局4路优先级，详见[核对记录](2026-10-19-game-plans-progress-audit.md)。

## 素材与授权

- 用 `frontend/ios/Tools/gen_game_sounds.py`（仅标准库 `wave` / `math` / `struct`，无 numpy 依赖）**确定性合成** 10 个 WAV：`key_press` / `start` / `pause` / `resume` / `hard_drop` / `clear_single` / `clear_multi` / `eat` / `game_over` / `win`。
- 单声道、统一 44100 Hz、16-bit PCM，全部淡入淡出，总 **64.8 KB**（<1MB）；无第三方采样、无 CC0 下载，故**无需署名/许可归档**。重复运行脚本得到字节级一致文件。
- 输出目录 `frontend/ios/VeraBot/Resources/Sounds/`，以文件夹引用登记进 `project.pbxproj` 的 Resources 阶段；各文件 SHA256 见脚本运行输出（可复现，不随构建漂移）。

## 播放器（GameSoundPlayer）

- 有限 `AVAudioPlayer` 池（按键 3 路、其余 2 路）+ `prepareToPlay()`；按事件映射文件名与音量（结果音略重于按键，整体偏低）。
- `AVAudioSession` 用 `.ambient`（遵守系统静音开关、可与其它 App 音乐混音）；不启用后台音频。
- 与 TTS（`.playback` / `.duckOthers`）和语音输入（`.record`）做小范围协调：新增 `VeraBotCore.AudioSessionOwner`（NSLock 保护）记录「录音 / 朗读」占用，游戏播放前查询，为真则静默；TTS 与语音输入在占用/释放时写标记。录音 / 朗读优先。
- 中断 / 耳机断开（`.oldDeviceUnavailable`）立即 `stopAll()` 并让出会话；不补播历史事件。
- 按键音 60ms 最小间隔防积压；自动重力 / 软降每格 / 蛇每格移动保持安静。

## 事件绑定（规则层结果，视图层输入）

- 新增 `VeraBotCore.GameSoundEvent`（10 个 case），供规则层与 App 共用。
- 贪吃蛇规则 `VeraBotCore/SnakeGame.swift`：真实结果事件写入 `soundEvents`（`eat` / `gameOver` / `win`），`soundEventsVersion` 递增，视图 `drainSoundEvents()` 一次取走；不在重绘/分数变化时猜测。
- 俄罗斯方块规则（App 内私有 `TetrisGame`）：`lockPiece(fromHardDrop:)` 写 `hardDrop`（仅硬降）/ `clearSingle` / `clearMulti` / `gameOver`，`soundTick` 递增，视图 `drainSounds()` 取走。
- 输入层：方向/旋转键播 `keyPress`；硬降只播落地声；开始/暂停/继续播对应确认音。

## 设置

- 新增 `SettingsKeys.gameSoundEnabled`（默认开启），设置 › 通用新增「游戏音效」开关（与「触感反馈」分开）。
- 两款游戏顶部工具栏新增扬声器快捷开关，关闭时立即 `stopAll()`。

## 文件

- `frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/GameSoundEvent.swift`（新增）
- `frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/AudioSessionOwner.swift`（新增）
- `frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/SnakeGame.swift`（规则事件）
- `frontend/ios/Packages/VeraBotKit/Sources/VeraBotTTS/TTS.swift`（朗读占用标记）
- `frontend/ios/VeraBot/Services/Speech/SpeechInput.swift`（录音占用标记）
- `frontend/ios/VeraBot/Core/UI/GameSoundPlayer.swift`（新增）
- `frontend/ios/VeraBot/Features/Playground/MiniGameViews.swift`、`SnakeGameView.swift`（事件接线 + 扬声器开关）
- `frontend/ios/VeraBot/Features/Settings/GeneralSettingsSection.swift`、`SettingsKeys.swift`（开关）
- `frontend/ios/Tools/gen_game_sounds.py`、`frontend/ios/VeraBot/Resources/Sounds/*.wav`（素材）

## 验证

- 原执行记录报告 `swift test --disable-sandbox`（VeraBotKit）388项通过。2026-10-19源码核对未发现新增GameSoundEvent/AudioSessionOwner/声音队列专项测试，不能将全包通过说成这些新行为已获专项覆盖；本轮未重新运行测试。
- `plutil -lint project.pbxproj` 通过。
- `xcodebuild`（iPhone 17 / iOS 26 模拟器）**未构建**：沙箱拒绝写入 `~/Library/Caches/org.swift.swiftpm`（`Operation not permitted`），按要求未申请权限。
- 未跑真机、未试听；首音/连点延迟、音量、叠加削波、静音开关、耳机断开等仍需 iPhone 11 / 12 Pro Max 真机确认。

## 未完成 / 风险

- App 目标未编译验证（见上）；新增 Swift 文件仅人工审查 + 包层测试通过。
- Bot 接管 / 交回音未做（依赖未实现的云端接管，不伪造成功）。
- 会话协调是「标记 + 静默」的轻量方案：游戏不抢占、TTS / 录音优先；未做更细的所有权回滚（若需在游戏中即时恢复播放，再单独评审）。
