# Bot 漂流瓶首版 · 2026-10-20

## 状态

**实现完成，隔离环境验证完成，已合入本地 Main，待用户在主分支人工验收。** 未推送、未迁移正式数据库、未替换正式服务、未安装到手机。

- 设计：[已确认设计](../superpowers/specs/2026-10-19-bot-drift-bottle-design.md)
- 计划：[执行计划](../superpowers/plans/2026-10-20-bot-drift-bottle.md)
- 功能清单：[FEATURES](../product/FEATURES.md)
- 管理员操作：[举报处理说明](2026-10-20-bot-drift-bottle-admin.md)

## 用户要求与主轴

“我和 Bot 一起遇见世界”：一起发现 → 交流感受 → 主人决定留下什么 → 带走共同回忆。Bot 是有自己性格、关注点、会好奇追问的同行伙伴；没有陌生人回复也能完成一次有意义的共同体验。首版是真实共享文字瓶，私人交流与公开留言严格分开。

## 实现范围

### 后端（schema v39）

新增迁移 `backend/verabot/db/migrations/v039_drift_bottle.py`，注册到 `migrations/__init__.py`（`SCHEMA_VERSION = 39`）。新增表：

- `drift_bottles`：共享瓶、原始 Bot 快照、累计公开投稿数、状态（active / archived / empty）、版本。
- `drift_bottle_contributions`：原信与沿途留言、作者账号、Bot 公开快照、作者标记、正文、可见状态、1–50 顺序。
- `drift_bottle_encounters`：私有相遇、同行 Bot、租约令牌、24 小时到期、结束原因、当时已读上限。
- `drift_bottle_reads`：账号已读去重标记，删除记录后仍保留。
- `drift_bottle_turns`：私有 opening / chat / draft，事件键去重。
- `drift_bottle_memories`：本功能独立回忆卡、来源轮次、主人编辑标记。
- `drift_bottle_operations`：按账号 + 请求 ID 的幂等操作与生成状态。
- `drift_bottle_generation_locks`：同一相遇生成串行化与超时接管。
- `drift_bottle_blocks`、`drift_bottle_reports`、`drift_bottle_report_hides`、`drift_bottle_moderation_actions`：屏蔽、举报、举报者即时隐藏、管理员审计。
- `drift_bottle_record_hides`：删除足迹但不撤回公开文字。
- 账号删除触发器：撤回其公开投稿；无有效公开文字的 active 瓶退出匹配。

新增 `backend/verabot/db/drift_bottle_store.py`（全部 SQL）与 `backend/verabot/services/drift_bottle/`：

- `contracts.py`：严格请求模型、公开 DTO 白名单、Unicode 码点长度与业务错误。
- `visibility.py`：页面与模型共用的可见性入口；撤回/隐藏/举报/屏蔽显示占位，绝不把隐藏正文送入模型。
- `companion.py`：无工具 JSON 输出；公开上下文最多 12,000 字、原信与最近留言优先；最近 20 轮私聊；opening ≤120 字、chat/draft ≤300 字；回忆分块归纳全部本次对话。
- `service.py`：操作编排、频率限制、租约、幂等、生成锁、迟到写回复核。
- `moderation.py`：受限管理员处理 keep / hide / restore。

新增 `backend/verabot/api/routers/drift_bottle.py`，前缀 `/api/games/drift-bottle`，所有接口需登录：

`GET /state`、`POST /bottles`、`POST /draft-suggestions`、`POST /encounters`、`GET /encounters/{id}`、`POST /encounters/{id}/turns`、`POST /encounters/{id}/release`、`GET /records`、`GET /records/{id}`、`POST /encounters/{id}/memory`、`PATCH /records/{id}/memory`、`DELETE /records/{id}`、`DELETE /records/{id}/memory`、`POST /contributions/{id}/withdraw`、`POST /reports`、`POST /blocks`、`GET /operations/{request_id}`。

新增管理员 CLI `backend/scripts/drift_bottle_admin.py`，仅接受显式数据库路径，管理员身份来自 `VERABOT_DRIFT_BOTTLE_ADMINS`。

### iOS

新增：

- `VeraBotCore/DriftBottle.swift`：共享 Codable 契约与请求/响应。
- `VeraBotCore/DriftBottlePresentation.swift`：码点长度、公开预览、署名、到期、Bot 可用性、事实回忆标题。
- `VeraBotNetworking/DriftBottles.swift`：`DriftBottleAPI` 与 `APIClient` 实现；`VeraBotAPI` 继承该协议。
- `VeraBotData/DriftBottleModel.swift`：账号作用域状态、迟到响应隔离、断线查询、草稿/私聊缓存、操作恢复。
- `VeraBotData/DriftBottleDraftCache.swift`：按账号分区；只缓存自己的草稿、私人轮次与操作 ID，不缓存他人公开正文。
- `VeraBot/Features/Playground/DriftBottle/`：Home、Reading、Composer、Records、Memory 五个页面。

修改：

- `Playground/WorldViews.swift`：漂流瓶卡从占位改为真实入口，增加推荐卡与轮播可访问标识。
- `App/AppState.swift`：登录后按账号配置模型，退出/换账号立即清理旧画面；未扩大普通聊天职责。
- `VeraBot.xcodeproj/project.pbxproj`：加入五个页面文件。

## 关键行为

- 每账号同时持有一个外来瓶；同账号再次请求/多设备恢复同一相遇。
- 持有 24 小时，服务器请求时回收；到期后记录与私聊仍可查看/继续，但不能追加公开留言。
- 每瓶最多 50 条公开投稿（含原信）；第 50 条后归档，不再匹配；撤回不返还名额。
- 公开正文 1–1000 码点；客户端按 `unicodeScalars` 与 Python `len` 对齐。
- 匹配排除自己投过稿、自己已读过、含自己屏蔽作者内容的瓶子；随机选择，不做社交资料匹配。
- 放漂/放回不等待回复；失败保留文字；未知结果先查 `GET /operations/{request_id}`。
- 首次 opening 每次相遇最多成功一次；安静模式在服务器持久化；私聊结束后仍可继续。
- 公开确认页只展示最终文字、Bot 公开名/预设头像与作者标记；生成稿默认 `bot_draft`，不自动标亲笔。
- 回忆卡独立保存，不写普通聊天或通用长期记忆；放漂先落事实卡，聊过天时完成页尝试升级为 Bot 摘要，失败保留事实卡。
- 撤回/隐藏/屏蔽后，新模型调用不再收到隐藏正文；页面用固定占位保持顺序。

## 验证记录（自动 / 构建 / 模拟器 / 真实模型）

### 自动测试

后端漂流瓶专项，全部使用临时数据库：

| 脚本 | 结果 |
|---|---|
| `drift_bottle_store_test.py` | 6/6 |
| `drift_bottle_rules_test.py` | 10/10 |
| `drift_bottle_api_test.py` | 5/5 |
| `drift_bottle_visibility_test.py` | 8/8 |
| `drift_bottle_companion_test.py` | 9/9 |
| `drift_bottle_acceptance_test.py` | 5/5 |
| **合计** | **43/43** |

覆盖：并发捞瓶唯一赢家、同账号恢复、重复放漂只加一条、请求 ID 冲突、24 小时边界、50 条归档、空池、自己/已读/屏蔽排除、越权 404、码点边界、撤回占位、举报者即时隐藏、管理员隐藏/恢复、删记录保留公开文字与已读、账号删除、Bot 删除、满瓶恢复不重开、opening 一次、安静模式持久化、私聊不公开、模型失败可重试、迟到写回拒绝、失败重试复用用户消息、服务器重启后操作/私聊/回忆可查。

既有后端回归：auth 18/18、avatar/profile 22/22、Bot appearance、Tetris store 12/12、Feed 32/32、Reminder 通过。`group_store_test.py` 有 1 个附件清理失败；已在未改动的 main 工作树复现，属于既有问题，不计入本功能回归。

Swift 包：`swift test` **488/488** 通过；新增 DriftBottle 相关测试 16 项。

### 构建与模拟器

- `xcodebuild` iPhone Simulator 构建：`** BUILD SUCCEEDED **`。
- 临时 XCUITest（不提交）在 iPhone 17 Pro / iOS 26 模拟器跑通：
  登录 → 游乐场 → Bot 漂流瓶 → 捞瓶 → 阅读 → Bot opening → 私人聊天 → 留言 → 公开预览 → 放漂 → Bot 整理回忆 → 足迹 → 记录详情，**1/1 通过**。
- 截图证据：[首页](../../assets/screenshots/ios/2026-10-20-drift-bottle/01-home.png)、[阅读](../../assets/screenshots/ios/2026-10-20-drift-bottle/02-reading.png)、[私聊](../../assets/screenshots/ios/2026-10-20-drift-bottle/03-private-chat.png)、[公开预览](../../assets/screenshots/ios/2026-10-20-drift-bottle/04-public-preview.png)、[回忆](../../assets/screenshots/ios/2026-10-20-drift-bottle/05-memory.png)、[足迹](../../assets/screenshots/ios/2026-10-20-drift-bottle/06-records.png)、[记录详情](../../assets/screenshots/ios/2026-10-20-drift-bottle/07-record-detail.png)。
- 手动测试环境：临时 `8765` 测试后端已按用户要求停止；最终包仍安装在 iPhone 17 Pro 模拟器。用户将在本地 Main 上验证；Main 正式库仍为 v38，验证前需按部署决定启动 v39 后端或指向隔离库。

### 真实模型

在隔离临时数据库、隔离后端进程中使用现有 DeepSeek Key 真实调用，同一封信分别由两位不同性格 Bot 阅读：

- 小满（好奇心强、短句、会追问）opening：“信写到一半就下雨了，这个停顿很真实。我好奇的是：他找早餐店，是在找味道，还是找个能坐下的地方？”
- 迟灯（温柔克制、先表达感受）opening：“‘信写到一半，窗外开始下雨’——这个停顿让我停了一下。雨落下来的时候，找早餐店这件事好像忽然变得不那么急了。你读到这里，心里是安静，还是有点空？”
- 两者回复都围绕信里的雨、早餐店与“写到一半”展开，没有编造共同往事，没有机械重复同一句追问。

真实模型调用产生费用；Key 未写入代码、日志或文档。真实模型下的 UI 人工体验仍需用户确认。

### 管理员 CLI

用临时数据库验证：创建举报 → `--action hide` → 投稿 `hidden`、举报 `hidden`、审计行记录 `admin_user_id/action/reason`。未配置管理员身份时拒绝执行。

## 已知限制 / 待验

- **人工验收未完成**：用户尚未在模拟器/真机点击体验、判断 Bot 语气与回忆卡质量。
- **真机未安装**：按用户要求不安装到手机；正式签名/安装待用户指示。
- **正式数据库未迁移**：本机正式库仍为 v38；v39 只在临时测试库和构建中验证。
- **正式服务未替换**：未部署 v39 后端，未配置正式管理员名单。
- **没有账号删除 API**：当前产品没有删除账号入口；已实现触发器与 `cleanup_user`，并通过直接删除用户行验证。以后接入账号删除时必须调用/验证该路径。
- **管理员仅 CLI**：首版不含运营后台；管理员名单通过环境变量配置。
- **UI 自动测试工程未提交**：临时 XCUITest 项目用于本次证据，未进入仓库；可访问标识已保留，便于后续正式 UI 测试。
- **`group_store_test.py` 既有失败**：与漂流瓶无关，main 同样失败。
- **真实模型只验证了两位 Bot 的 opening/chat**：长对话、真实模型回忆摘要、真实网络抖动下的完整体验仍待人工验收。

## 提交与部署边界

- 分支：`codex/bot-drift-bottle`
- 工作树：`.worktrees/bot-drift-bottle`
- 功能提交：`49d8d76 feat: Bot 漂流瓶首版（共享瓶、私聊与共同回忆）`
- 已合入本地 Main（merge commit 见 `git log`）。
- 基线：`16fdabc`。提交后本地 main 已前进到 `e7d0900`（Whack-a-Bot 合入）；`git merge-tree` 预检显示代码文件（含 `project.pbxproj`、`WorldViews.swift`）可自动合并，仅 `docs/CHANGELOG.md` 与 `docs/product/FEATURES.md` 有文档冲突，合并时需保留两节。未执行合并。
- 已合入本地 main；未推送、未迁移正式库、未部署、未安装手机。
- 上线前需要用户明确授权：备份并迁移 v39、重启/替换 API、配置管理员名单、安装新包。
