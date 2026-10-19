# 游戏音效实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Subagents require separate authorization.

**Goal:** 为俄罗斯方块和贪吃蛇交付可试听、可追溯、低干扰的8项基础音效，保留朗读与录音行为。

**Architecture:** 先产出候选包与选定清单，再统一共享音频会话租约；纯事件调度策略与AVAudioPlayer适配分离，游戏只发送真实事件。Bot交接音作为C4后的扩展，不阻塞基础包。

**Tech Stack:** Swift 6、AVFoundation、SwiftUI、Python标准库素材校验；无新SDK。

**Spec:** [音效方案](../../product/2026-10-18-game-sound-effects-proposal.md)、[执行基线 §6、§8](../specs/2026-10-18-game-upgrade-execution-baseline.md)。

**状态（2026-10-19）：**用户已交DeepSeek Harness并确认执行结束；音效v1已由`0bbcd05`实现、`ec5b66c`合入main。A1–A3部分完成，A4未见验收；实际采用自产10项44.1kHz短音与布尔占用标记，并非原计划全部参数/租约/策略已经实现。剩余以现有代码增量补齐，见[证据与差异](../../tasks/2026-10-19-game-plans-progress-audit.md)和[总账](../../tasks/2026-10-18-game-upgrade-progress.md)。以下原计划保留作验收参照，不再把音效首版描述成尚未开发。

## Global Constraints

- iOS最低17；Mac包测试可通过，AVAudioSession调用以`#if os(iOS)`隔离。
- 基础8事件、48kHz/16bit/mono WAV、默认gain0.35、最多4路、按键80ms节流、先后优先级按基线§6。
- 游戏音效与触感开关独立；遵守系统静音，锁屏/后台不发声，无麦克风权限和后台音频能力新增。
- 录音优先3、TTS2、游戏1，旧租约不得释放新会话；保持既有TTS生命周期回归。
- 无新第三方依赖、无全局头像重写、无 Web 改动。授权来源记录逐文件保留，首批只选明确CC0。

## Review Focus

- `prepareToPlay`隐式激活会话，预热不得在录音/TTS拥有时发生（A2/A3 fake-driver测试）。
- 被抢占的游戏/TTS迟到释放，不能关掉新录音（A2代次回归）。
- 连点与消行撞上硬降，不能积压音效或叠加削波（A3时钟/voice策略测试与A4听测）。
- 耳机断开/中断恢复不能自动外放，后台不能复活播放器（A3 route/lifecycle状态测试）。
- 重入、重连、账号切换不能重放历史事件（A3 eventID和session generation测试）。

## 文件与接口分工

- 候选素材与试听：`docs/design/audio-candidates/manifest.json`、`index.html`、`candidates/<event>/<id>.wav`、`licenses/<id>.txt`；`docs/testing/2026-10-18-game-audio-audition.md`记录取舍。只保存必要短候选，不把整包大合集混入仓库。
- 最终资源：`frontend/ios/VeraBot/Resources/GameAudio/`，8个蛇形命名wav及`manifest.json`/`LICENSES.txt`，App pbxproj显式登记资源。
- Core：新`GameSoundEvent.swift`、`GameSoundPolicy.swift`，改`SettingsKeys.swift`；Tests：`GameSoundPolicyTests.swift`。
- 共享会话：新`frontend/ios/Packages/VeraBotKit/Sources/VeraBotTTS/AudioSessionCoordinator.swift`，复用既有已被App链接的VeraBotTTS模块，不新增目标；改同模块`TTS.swift`、App `Services/Speech/SpeechInput.swift`，测试`AudioSessionCoordinatorTests.swift`与既有`SpeechPlaybackTests.swift`。
- App播放：新`frontend/ios/VeraBot/Core/Audio/GameSoundPlayer.swift`（AVAudioPlayer适配与播放器池），App `VeraBotApp.swift`注入同一个coordinator与player；改两款游戏页面、`GeneralSettingsSection.swift`、`TetrisControlsView.swift`菜单与工程资源引用。
- 校验脚本：`scripts/check_game_audio.py`，仅标准库wave/json/hashlib；新建`tests/test_game_audio_assets.py`用unittest和临时合成极短波形验证资源校验，不下载网络素材运行CI。

## A1：素材候选、许可归档与试听选择

**Produces:** `manifest.json`格式 `{version:1,candidates:[{id,event,file,sourceURL,creator,license,licenseURL,sha256,durationMs,sampleRate,channels,bitDepth,edits,selected}]}`；id唯一、每个event最终恰好1个selected。资源来源沿用原方案已列官方链接，下载时再次核对当前页面与包内LICENSE。

- [ ] 从Kenney原方案3个官方包按8事件各挑2–3条；保存逐条来源与CC0许可原文/链接。找不到适配音时先记录缺口并另选有明确来源的CC0候选，不能把任意“免费”文件补入最终包。
- [ ] 新建标准audio控件试听页，每行event+候选来源+播放；不自动播放、不发网络请求、无假试听按钮。记录同一轮手机扬声器/有线或蓝牙耳机下的主观音量、刺耳与尾音意见。当前任务只生成候选并交用户选定，不擅自宣称已通过试听。
- [ ] 在`tests/test_game_audio_assets.py`先用临时样本断言错误采样率、双声道、头部空白超5ms、峰值超过0.7满幅、超事件时长/总1MiB、缺许可/哈希不符会退出非0；Run `python3 -m unittest discover -s tests -p test_game_audio_assets.py`，先红后实现`check_game_audio.py`并重跑绿灯。这里只发现这一份隔离脚本测试，不执行后端大范围discover。归一化后留安全余量，批处理不在每次按键运行。
- [ ] 将选定8条导出为`key_press.wav/state_confirm.wav/hard_drop.wav/clear_single.wav/clear_multi.wav/snake_eat.wav/game_end.wav/game_win.wav`；执行 `python3 scripts/check_game_audio.py frontend/ios/VeraBot/Resources/GameAudio/manifest.json`，预期8项齐全、退出0。
- [ ] 在试听记录填写候选、选定理由、设备和用户结论；没有用户选择时A1状态为“候选已交付，最终选择待验收”，A3不得写成最终素材已定。源文件哈希、处理后哈希分别记录，不覆盖来源证据。

## A2：共享音频会话所有权

**Produces:** `@MainActor public final class AudioSessionCoordinator`；`acquire(owner: AudioOwner,onRevoked: @MainActor () -> Void) throws -> AudioLease?`、`release(_ lease: AudioLease) throws`、`owns(_ lease: AudioLease) -> Bool`。owner为recording/tts/game；lease含UUID与递增generation。共享SystemAudioSessionDriver封装category/setActive，可注入fake供测试。

- [ ] 新建 `@Suite struct AudioSessionCoordinatorTests`：game→tts先调用game.stop再改category；tts→recording同理；recording期间game acquire返回nil且driver未prepare/activate；释放旧game/tts lease不调用deactivate。先测失败再实现。
- [ ] 明确转换：同级不同实例不抢占，返回nil；较高优先先撤销旧lease、同步调用onRevoked，再配置新session；旧回调release为no-op。激活失败清空新owner并停止相应功能，不自动恢复旧播放。deactivate失败保留待清理标记，只在没有新owner时重试，绝不能迟到关闭新owner；补fake错误测试。
- [ ] TTS的SystemSpeechAudioSession通过同一coordinator获取tts lease，保持现有 `SpeechAudioSession` 测试注入；录音通过recording lease，录音开始仍停止SpeechPlayer。App只构造一份协调器，默认实例也指向同一shared，避免页面各建一份。
- [ ] Run `swift test --package-path frontend/ios/Packages/VeraBotKit --filter 'AudioSessionCoordinatorTests|SpeechPlayback'`，预期全绿；既有返回列表/临时弹层/退出/取消/后台规则保持原测试。录音启动失败、取消和正常结束均释放自身lease。
- [ ] App单次构建验证集成。此任务无需最终素材即可交付；暂未有播放器时不假设游戏租约已在真实场景得到验收。

## A3：事件策略、播放器与两款游戏绑定

**Consumes:** L1的TetrisEvent、已有SnakeGame每步结果；A2租约，A1最终8项资源。**Produces:** Core `GameSoundEvent`、`GameSoundPolicy.request(event:id:nowMs:) -> [GameSoundCommand]`、`setEnabled(_:)`、`setActive(_:)`、`routeDisconnected()`、`reset(sessionID:)`；command为play(event,gain)/stopVoice(id)/stopAll。App `@MainActor GameSoundPlayer.play(event:id:)`、`activate()`、`deactivate()`执行命令。

- [ ] 新建`GameSoundPolicyTests`：key@0播放、@79拒绝、@80播放；同session同id只播一次；reset新session可接受新事件；voice满4路时低优先不打断高优先，终局淘汰最低优先最老者；clear停尚未结束hardDrop；禁用/后台/routeDisconnected后清音并拒绝后续，必须显式开启才解除耳机断开静默。先红后实现，所有时间用注入clock。
- [ ] AVAudioPlayer池最多4个在播，资源8条预加载；只有`coordinator.owns(gameLease)`时prepare/play。完成回调清voice并按当前lease重新准备，不缓存过时播放请求。被抢占先stop所有players，不能自行抢回会话；前台仍有效且高优先释放后才尝试新lease。
- [ ] 方向/A按下播keyPress（B省按键声，仅落地事件播hardDrop）；START状态实际改变播stateConfirm；重力和每格下降无声；蛇按钮按下或有效滑动入队给一次keyPress、吃食/结束按步结果发唯一id。Tetris只消费L1事件，不能从View.body、分数观察器或快照恢复猜声音。
- [ ] 新增 `SettingsKeys.gameSoundEnabled`；设置通用与游戏菜单绑定同一持久值，切换立即生效，现有haptics key不变。添加资源到Resources构建阶段，检查bundle能定位8个文件。暂停、离页、scene非active、音频中断、route断开统一deactivate，不申请后台音频。
- [ ] Run策略/协调器/语音/蛇/Tetris专项与素材脚本，再包全量和App构建；填人工V-06。没有新的已知缺口才交付A3；生成实际包增量和资源列表，目标1MiB超出时明确记录，不偷换为“已达到”。

## A4：真机声音与中断验收

**Produces:** `docs/testing/2026-10-18-game-audio-audition.md`追加最终资源与主机/备机结论，V-06逐项Pass/Fail/Blocked。

- [ ] 同一包交付两机后，以手机扬声器检查首音、快速连点、硬降接清行、蛇吃食/失败；五分钟连续游戏无音效积压、明显爆音或突兀高频。把听感结论交用户，不用模拟器替代。
- [ ] 记录可测的软件分发时延：输入事件到`play()`调用的单调时间差，100次样本p95目标≤16ms；此值不代表扬声器/蓝牙实际声学时延。声学滞后以用户体验记录；若明显，先查预加载和主线程，再单独评估AVAudioEngine改造，不静默切架构。
- [ ] 验静音开关、App音效开关、触感独立、听其他音乐、TTS→录音→游戏切换、耳机断开、来电/中断、锁屏/返回、账号切换；每项有设备和现象，失败保留记录。
- [ ] 根据用户试听只调素材/增益/包络等声音参数，变更后重跑素材脚本与相关策略测试；影响共享会话则补跑SpeechPlayback和协调器测试，不反复无差别全量构建。
- [ ] 满足V-06后更新总账A4；如果声音仍未验收，状态写“已实现待验收”，不标完成。未来C4完成再以独立任务加入handoff/return，只有服务器确认成功才播、不补播历史事件。

## 验证与交付

`swift test --package-path frontend/ios/Packages/VeraBotKit --filter 'GameSoundPolicyTests|AudioSessionCoordinatorTests|SpeechPlayback'`、`python3 scripts/check_game_audio.py frontend/ios/VeraBot/Resources/GameAudio/manifest.json`、`plutil -lint frontend/ios/VeraBot.xcodeproj/project.pbxproj`、`git diff --check`应退出0。App构建/安装沿用本地计划的一次一个流程；不在本计划中修改正式后端或数据库。

自检：原方案声音、来源、设置、前后台、陪玩静音及TTS冲突分别落在A1–A4；所有参数引用统一基线。实际执行前先读基线和总账；未选素材不是“已完成音效”的理由，也不影响L2掌机交付。提交与推送须按当时用户授权，只暂存本任务范围。
