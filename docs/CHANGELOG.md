# 更新日志 (CHANGELOG)

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/)，版本号遵循 [SemVer](https://semver.org/lang/zh-CN/) (见 [CONTRIBUTING.md](../CONTRIBUTING.md))。时间为北京时间 (UTC+8)。

## [Unreleased]

### 修复 (Fixed)

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
