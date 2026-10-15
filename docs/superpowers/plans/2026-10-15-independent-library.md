# 独立资料库与 Bot 主页 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execute only after the user reviews this plan and selects the execution method.

**Goal:** 实现账号级独立资料库、Bot 专属文件与图片页面、关联授权检索及原件离线查看。

**Architecture:** 复用现有附件文件处理和鉴权存储，将资料本体、来源和 Bot 关联独立于聊天生命周期。后端负责唯一事实、权限与版本化目录；iOS 使用现有账号隔离 SQLite 和统一文件下载服务，页面先读本地。各任务是同一资料生命周期的连续阶段，尚未完成全部阶段时不作为完整功能交付。

**Tech Stack:** Python/FastAPI/SQLite、现有附件解析与工具运行器、Swift/SwiftUI、VeraBotKit、URLSession 后台下载。

**Spec:** `docs/superpowers/specs/2026-10-15-independent-library-design.md`，用户于 2026-10-15 确认。

## Global Constraints

- 清空对话后保留资料；只有在资料库中明确删除才移除文件本体。
- 文件、图片分别放在独立 Tab 中展示。
- Bot 可以主动检索自己关联的资料；跨 Bot 使用须由用户明确共享。
- Wi-Fi 自动下载全部图片和文件原件；蜂窝网络仅手动下载。
- 未关联资料只供用户查看，不对所有 Bot 默认开放。
- 所有资料页面先读本地，再异步更新。
- 群聊来源不自动授予成员 Bot 长期权限；用户和 Bot 读取接口区别授权。
- 复用现有文件类型、配额、图片处理、账号隔离和安全审批，不新增第三方依赖。
- 本次不实现提醒、记忆等页面整体离线，也不自动重发聊天或离线排队修改。
- 不部署到现有用户数据，不把安装、启动或构建成功当作人工验收。

## Review Focus

- 旧清理入口和启动对账误删仍被资料引用的文件：任务 1、2 用真实临时文件验证。
- 一次分页未完成、游标失效及重复上传后错误清空或重复资料：任务 3、5 验证固定版本与提交边界。
- 群成员或委派树继承原 Bot 文件身份导致越权：任务 4 覆盖独立执行身份及撤销竞争。
- Wi-Fi 中途转蜂窝、空间不足及进程退出造成下载状态失真：任务 6 覆盖系统约束、原子提交与恢复。
- 旧设备持有附件 ID、移除关联后旧消息重复同步造成资料复活：任务 2、3、5 覆盖墓碑与旧下载入口。

## 文件职责与准备

后端新增 `db/library_store.py`（事务 SQL）、`services/library.py`（资料规则）、`api/routers/library.py`（用户接口）、`agents/library_tools.py`（Bot 只读工具）、`api/library_schemas.py`（请求响应契约）。迁移在执行时读取最新 `SCHEMA_VERSION` 后新建 `db/migrations/vNNN_independent_library.py`；NNN 是唯一必须动态分配的文件名，不预占版本。

iOS 新增 Core/Library.swift（Codable 契约）、Networking/LibraryAPI.swift 与 APIClient+Library.swift（传输）、Persistence/LibraryStore.swift（本地事务）、Data/LibraryRepository.swift（目录同步）、Data/LibraryViewModel.swift（页面状态）。App 下新增 Services/Library/LibraryDownloadCoordinator.swift、LibraryFileStore.swift；Features/Library/ 下创建 LibraryView.swift、LibraryFileList.swift、LibraryImageGrid.swift、LibraryItemDetailView.swift、LibraryUploadSheet.swift、LibraryBotSharingSheet.swift；Features/BotInfo/ 下新增 BotHomeView.swift。Packages 路径统一以 `frontend/ios/Packages/VeraBotKit/Sources/` 为根，App 路径统一以 `frontend/ios/VeraBot/` 为根。

任务 1 创建 `backend/scripts/test/library_test_support.py`，提供临时数据库与附件目录、两个账号、两个 Bot、一个群、图片及文本文件工厂、目录快照和磁盘读取辅助函数。每个测试脚本使用独立临时资源并在导入后端前设置环境变量，不访问生产数据。后端测试从仓库根使用 `PYTHONPATH=backend backend/.venv/bin/python backend/scripts/test/<name>.py` 单独运行；测试失败必须退出非零。

实施开始时使用 using-git-worktrees 工作流检查附属工作树并选择隔离工作区。当前主工作区存在聊天离线入口、快捷选项及相关文档的未提交修改，禁止 reset、覆盖或混入资料库提交。最终集成时处理交叠文件并保留这些行为。

## Task 1: 独立资料结构、存量迁移与持久引用

**Files:** 新建迁移、`backend/verabot/db/library_store.py`、`backend/verabot/services/library.py`、`backend/scripts/test/library_test_support.py`、`backend/scripts/test/library_migration_test.py`；修改 `backend/verabot/db/migrations/__init__.py`、`backend/verabot/db/attachment_store.py`、`backend/verabot/services/attachments/repo.py`。

**Interfaces:** `library.ingest_attachment(c, *, user_id:int, attachment_id:str, source_kind:str, source_id:int|None, bot_id:int|None, explicit:bool=False) -> str` 返回稳定资料 ID，使用调用方事务。`library_store.live_resource_keys(c) -> set[str]` 供对账保护文件。资源、资料项、来源、Bot 关联、显式移除标记和按账号递增的变更日志各自独立。

- [ ] 写 `migration_preserves_attached_and_ignores_pending`、`migration_is_idempotent`、`migration_preserves_missing_file_state`、`reconcile_keeps_library_resource`：断言两次迁移资料 ID 和数量相同、pending 未入库、丢失文件不可用、迁移后对账不删除存在的文件。
- [ ] 运行 `library_migration_test.py`，确认缺少新结构或迁移导致预期失败。
- [ ] 分配下一迁移版本，重建需要解除消息/Bot 级联的兼容附件结构；回填已发送私聊、群聊附件及来源快照。旧 attachment ID 建立唯一映射，pending 保留现有语义；失去消息和 Bot 不影响独立资料本体。迁移不读取模型或复制不必要的二进制。
- [ ] 将对账有效引用和配额统计接入资料资源，避免双计费和仍被引用的文件成为孤儿；迁移失败不执行资源回收。
- [ ] 再运行 `library_migration_test.py` 和现有 `attachments_test.py`，预期所有断言通过；备份并恢复临时迁移样本验证数据库及文件匹配。
- [ ] 仅提交本任务文件，消息 `feat: persist independent library resources and migrate attachments`。

## Task 2: 聊天归集、保留与删除生命周期

**Files:** 修改 `backend/verabot/db/repository.py`、`backend/verabot/db/group_store.py`、`backend/verabot/db/chat_reply_store.py`、`backend/verabot/services/attachments/repo.py`、`backend/verabot/api/routers/attachments.py`、任务 1 新增文件；新建 `backend/scripts/test/library_lifecycle_test.py`。实施时跟踪实际所有发送/清空/Bot 删除调用方，测试中逐一经过公共入口。

**Interfaces:** `library.unlink_bot(user_id:int, item_id:str, bot_id:int) -> None`；`library.link_bot(user_id:int, item_id:str, bot_id:int) -> None`；`library.delete_item(user_id:int, item_id:str) -> None`。显式 link 清除该关联的抑制标记；自动归集不得清除。删除为幂等并写目录墓碑。

- [ ] 写 `clear_chat_keeps_original`、`delete_bot_preserves_other_links`、`unlink_then_reingest_stays_unlinked`、`delete_then_reingest_stays_deleted`、`shared_resource_survives_one_item_delete`：断言原件字节、关联集合、来源失效标记及旧 ID 下载响应。
- [ ] 运行 `library_lifecycle_test.py` 确认当前行为会失败。
- [ ] 私聊、群聊和回复附件成功提交时调用 ingest；删除来源仅失效来源并保留名称快照，保留单消息和 Bot 删除的其他既有行为。群聊 ingest 的 `bot_id=None` 不产生成员关联。
- [ ] 实现移除、重共享和全局删除事务；兼容附件卡片返回可显示的“资料已删除”，旧下载接口不再提供已删原件。资源回收只在无有效引用时进行。
- [ ] 运行新脚本及现有 `message_delete_test.py`、`group_lifecycle_test.py`、`attachments_test.py`，调整旧测试中已被新产品规则取代的“清空即物理删除”断言，保留其他回归断言。
- [ ] 提交 `feat: retain library items across conversation cleanup`。

## Task 3: 用户资料 API、搜索与版本化目录

**Files:** 新建 `backend/verabot/api/library_schemas.py`、`backend/verabot/api/routers/library.py`、`backend/scripts/test/library_api_test.py`；修改 `backend/verabot/main.py` 及资料服务、存储。

**Interfaces:** 基址 `/api/library`。`GET /items?kind=&bot_id=&q=&downloadable=&cursor=&limit=50` 返回 `items,next_cursor,snapshot_revision`；`GET /changes?after_revision=&cursor=` 返回 `upserts,removed_ids,next_cursor,through_revision`；`GET /items/{id}` 返回详情；`POST /items` 直接上传；`PUT/DELETE /items/{id}/bots/{bot_id}` 建立/移除关联；`DELETE /items/{id}` 全局删除；`GET /items/{id}/content` 与 `/thumb` 鉴权下载。上传使用稳定请求键以处理重试，目录搜索空串等同未筛选，limit 限制 1…100。

**DTO:** Item 必含 `id,kind,name,mime,bytes,sha256,resource_version,created_at,revision,availability,text_status,bot_ids,sources`；Source 必含 `kind,source_id,bot_id,display_name,created_at,message_available`。删除标记保留旧附件映射。分页必须绑定账号、过滤条件及版本边界；失效返回 `409 library_revision_changed`，客户端重新开始，不拼接不同版本。

- [ ] 写 `owner_can_read_unlinked_item`、`other_account_gets_404`、`upload_retry_creates_one_item`、`snapshot_pagination_rejects_revision_change`、`delete_is_visible_in_changes`、`search_returns_filename_and_extracted_text_matches`，断言无越权名称/计数及完整 DTO 校验字段。
- [ ] 运行 `library_api_test.py`，确认路由缺失或契约不满足而失败。
- [ ] 实现参数化 SQL、分页与变更日志，固定快照读取或检测版本变化；完整目录按收录时间及 ID 稳定排序。上传沿用类型/配额/解析规则，文件落盘与事务失败清理复用附件实现。
- [ ] 为旧变更游标过期提供明确重新全量同步响应；用户下载校验所有权，返回稳定资源版本及内容校验信息，缺失原件返回明确 410，不泄漏存储路径。
- [ ] 运行新脚本及 `cache_headers_test.py`、`attachments_test.py`，所有断言通过。
- [ ] 提交 `feat: expose versioned library catalog and sharing APIs`。

## Task 4: Bot 主动检索与逐次访问授权

**Files:** 新建 `backend/verabot/agents/library_tools.py`、`backend/scripts/test/library_tools_test.py`；修改 `backend/verabot/agents/permissions.py`、`runtime.py`、`group_runtime.py`、`tool_router.py`、`delegation.py`，及工具注册导入位置和资料服务。

**Interfaces:** 工具 `search_library(query:str,limit:int=10)`、`read_library_file(item_id:str,start:int=0,limit:int=4000)`、`view_library_image(item_id:str)`；从 ToolContext 的 `user_id` 和 `bot['id']` 取身份。`library.authorize_bot(user_id:int,bot_id:int,item_id:str) -> int` 返回关联授权版本，操作返回前再次校验版本。

- [ ] 写 `bot_search_is_link_scoped`、`delegated_bot_cannot_inherit_parent_files`、`group_membership_does_not_grant_library_access`、`revoke_while_reading_denies_result`、`file_content_cannot_authorize_write`，使用假模型及暂停读取点断言越权 ID、名称、片段和待返回原件均不泄露。
- [ ] 运行 `library_tools_test.py` 确认新工具不可用而失败。
- [ ] 实现独立资料工具的注册和暴露，仅给当前有资料关联的 Bot 暴露只读能力；继续执行现有安全策略及预算，不将此类工具混入普通未命名附件权限列表。解除关联后不因父轮次的 `file_ids` 或 `file_owner_bot_id` 放行新资料工具。
- [ ] 复用现有文本分段和图片读取，读取内容保持不可信标记；图片原件及搜索返回前复核资料/关联版本。原有本轮显式附件路径不得成为被撤销资料的旁路。
- [ ] 运行新脚本和现有 `multi_agent_test.py`、`attachments_test.py`、`group_runtime_test.py`，预期通过。
- [ ] 提交 `feat: authorize Bot library retrieval by explicit links`。

## Task 5: iOS 契约、本地目录与同步

**Files:** 新建前述 Packages 中 Library.swift、LibraryAPI.swift、APIClient+Library.swift、LibraryStore.swift、LibraryRepository.swift；修改 `VeraBotPersistence/LocalDatabase.swift`；新建 `Tests/VeraBotKitTests/LibraryRepositoryTests.swift` 和 `LibraryContractTests.swift`。

**Interfaces:** `LibraryAPI: Sendable` 定义与任务 3 对应的 async throws 方法。`LibraryRepository` 提供 `cachedItems(filter: LibraryFilter) async throws -> [LibraryItem]`、`synchronize() async throws`、`detail(id:String) async throws -> LibraryItem` 及上传/关联/删除方法；`LibraryStore` 以一个事务提交完整目录暂存或完整增量批次。LocalDatabase 迁移保留旧会话、草稿和列表。

- [ ] 编写 `cachedCatalogIsVisibleBeforeNetworkCompletes`、`failedSecondPagePreservesPreviousSnapshot`、`revisionChangeRestartsStaging`、`tombstoneDoesNotResurrectFromOldPage`、`databaseUpgradeKeepsChatDraft`，假 API 控制响应顺序，断言网络等待期间立即可读、失败前后缓存相同、迟到旧页被拒绝。
- [ ] 在 `frontend/ios/Packages/VeraBotKit` 运行 `swift test --filter Library`，确认缺少类型而失败。
- [ ] 定义 Codable DTO 与错误映射，契约样本覆盖未知可选字段和不可用资料。扩展 SQLite 分步迁移，不使用当前版本早退逻辑跳过新版本。
- [ ] 实现串行目录同步、分页暂存、版本变化重启及会话有效性检查。网络失败不落空快照；目录已同步与原件已下载分别存储。离线修改操作返回明确不可用，不伪造服务端成功。
- [ ] 运行筛选测试与完整 `swift test`，预期现有及新增测试通过。
- [ ] 提交 `feat: cache and reconcile library catalog on iOS`。

## Task 6: 原件统一存储与受网络约束的下载

**Files:** 新建 Services/Library/LibraryFileStore.swift、LibraryDownloadCoordinator.swift，以及 Packages 中 `VeraBotData/LibraryDownloadPolicy.swift`、`Tests/VeraBotKitTests/LibraryDownloadPolicyTests.swift`；修改 AppState.swift、VeraBotApp.swift、Services/Attachments/AttachmentImageStore.swift、Features/Chat/AttachmentViews.swift。App 层下载集成测试放 `frontend/ios/VeraBotTests/LibraryDownloadIntegrationTests.swift`；在 `frontend/ios/project.yml` 新建宿主 App XCTest target 及 scheme 测试配置，再重新生成 Xcode 项目，不假设当前已有 App 测试 target。

**Interfaces:** `LibraryFileStore.localURL(itemID:String,resourceVersion:String) -> URL?`、`commit(tempURL:URL,item:LibraryItem) throws -> URL`；`LibraryDownloadCoordinator.enqueue(items:[LibraryItem],mode:LibraryDownloadMode)`、`pauseAutomaticDownloads()`、`invalidateSession()`；mode 为 `automaticWiFi` 或 `manualCellularAllowed`。策略状态模型位于 Package，可注入网络/空间/会话条件测试。

- [ ] 写 `automaticDownloadStopsOnCellular`、`manualDownloadAllowsCellular`、`partialOrCorruptFileIsNeverReady`、`oldSessionCompletionCannotCommit`、`insufficientSpacePreservesDownloadedFiles`、`relaunchReconcilesBackgroundTasks`；断言状态及实际文件校验结果，不只验证枚举分支。
- [ ] 先生成并验证新增 App 测试 target 可以运行，再运行 Package 策略测试与 App 集成测试，确认当前下载路径不能满足这些断言；编译配置错误不能充当行为失败证据。
- [ ] 原件写账号专属 Application Support，使用系统文件保护、禁止备份及临时文件原子提交；仅验证后的资源版本可标记 ready。映射 URLSession task ID 到持久资料/会话身份，恢复未完成任务，处理墓碑后迟到结果。
- [ ] 自动任务使用禁止蜂窝、昂贵及受限网络的独立后台配置；手动任务单独允许蜂窝。切换网络时取消/暂停未完成自动任务，响应系统回调，不仅依赖 NWPathMonitor。实现暂停偏好、失败重试、空间错误和下载进度。
- [ ] 用户退出/换服取消旧任务、立即关闭旧账号可见性。服务端删除同步后清理本地文件；聊天和 Quick Look 从统一文件存储读取，未下载不会显示为已删除。清除本机下载与云端删除分别实现。
- [ ] 运行 Package 完整测试及 App 测试；模拟器使用本地受控下载端点验证断点和重启。蜂窝切换必须在真机执行任务 9 的网络验收，模拟器结果不代替该证据。
- [ ] 提交 `feat: persist shared originals and enforce offline download policy`。

## Task 7: 全局资料库与上传、共享、删除

**Files:** 新建前述 Features/Library/ 全部文件和 Packages 中 `VeraBotData/LibraryViewModel.swift`、`Tests/VeraBotKitTests/LibraryViewModelTests.swift`；修改 Features/BotList/BotListView.swift 增加首页入口；如 Xcode 项目未自动同步目录则更新 project.pbxproj。

**Interfaces:** `LibraryView(scope: LibraryScope)`；scope 为 `.all` 或 `.bot(id:Int)`。`LibraryViewModel` 消费任务 5 repository，发布文件、图片、筛选、错误、离线准备状态；App 通过 coordinator 提供下载进度和预览 URL。所有破坏性操作在服务端成功或同步确认后提交本地结果。

- [ ] 测试 `unlinkedItemAppearsGlobally`、`fileAndImageTabsDoNotMix`、`offlineListShowsCachedDataAndMissingDownloadState`、`deleteFailureKeepsItem`、`unlinkDoesNotDeleteGlobalItem`，从同一 repository fixture 验证状态转换。
- [ ] 运行 `swift test --filter LibraryViewModel`，确认缺少模型或行为失败。
- [ ] 实现文件列表、日期图片网格、搜索筛选、可用状态、详情和原消息失效文案。正文搜索通过任务 3 API；离线仅保证名称及已同步索引可搜索，不把在线结果误作离线全文索引。
- [ ] 接入系统文件导入/照片选择和上传请求键；全局上传可不关联，Bot scope 默认关联当前 Bot。新增关联的确认界面明确目标 Bot 可检索读取，不混同发送聊天。
- [ ] 实现“从当前 Bot 移除”“从资料库删除”和“清除本机下载”三个操作及正确影响范围；蜂窝批量下载先展示预计体积，暂停自动下载和准备进度从全局可见。
- [ ] 运行完整 Swift 测试并构建模拟器，人工检查空状态、失败、长文件名、深浅色和大字体，无额外低价值布局快照测试。
- [ ] 提交 `feat: add global library browsing and management`。

## Task 8: Bot 主页与导航接入

**Files:** 新建 Features/BotInfo/BotHomeView.swift；修改 BotInfoView.swift、BotEditView.swift、Features/Chat/ChatView.swift 及 Task 7 共享页面；仅在涉及群来源定位时修改 Features/GroupChat/GroupChatView.swift。

**Interfaces:** `BotHomeView(bot:Bot,onSaved:@MainActor(Bot)->Void,onStartChat:@MainActor()->Void,onClear:@MainActor(Bool)async->Void)`，通过现有 BotInfo 包装接入。概览入口使用现有记忆、提醒、任务及协作页面，不重写其数据层。

- [ ] 在模拟器记录当前“点对话标题进入详情、长按编辑、保存/关闭、清空确认”的基线操作；新增主页前确认目前直接进入编辑表单。
- [ ] 实现头像/名称/身份/简介、开始对话、概览/文件/图片三个 Tab、随内容滚动收起的大头像及固定分类。编辑放右上角，长按编辑仍直达表单。
- [ ] 复用 `.bot(id:)` LibraryView；保留发送期间禁用清空及既有 onSaved/onClear 回调语义。定位来源通过已有导航模型，在来源失效时禁用。
- [ ] 构建模拟器并逐项操作上述流程、浅深色和大字体；确认切回聊天不会丢草稿、重置历史位置或阻塞本地首屏。记录可复现步骤及截图，不用构建代替交互验收。
- [ ] 提交 `feat: expand Bot details into overview and media home`。

## Task 9: 集成回归、文档与可验收交付

**Files:** 更新 README.md、docs/STATUS.md、docs/CHANGELOG.md、docs/product/FEATURES.md、docs/testing/TEST_CASES_v0.1.md；新建 `docs/testing/2026-10-15-independent-library.md`，必要时使用实际完成日期更新文件名。

**Interfaces:** 依赖任务 1–8 的全部接口，交付同一后端版本、iOS 构建和匹配数据库；不公开推送、不迁移真实用户数据，除非该阶段得到相应授权。

- [ ] 逐一运行新建四个后端库测试脚本（migration、lifecycle、api、tools）；运行附件、消息删除、群生命周期、群运行器、多 Bot 和缓存头回归。各脚本独立进程执行，不使用统一 unittest discover。
- [ ] 运行 VeraBotKit 完整 `swift test`、App 下载集成测试、模拟器构建及 generic iOS 签名构建。测试命令依据当前 scheme/destination，使用单独 DerivedData，记录日志与实际计数，不沿用旧证据。
- [ ] 在独立账号完成：历史归集→直接上传→共享两个 Bot→移除其中一个→清空聊天→重启→保留资料→全局删除→旧设备重连，检查原件、Bot 权限、来源及墓碑。假模型工具验证替代真实模型只作为自动回归，不宣称真实模型使用已验收。
- [ ] 真机验证 Wi-Fi 下载全部、转蜂窝暂停自动任务、蜂窝手动单项/批量、断网重启后文件及图片分享、存储不足、换账号和远程删除后重连。设备不在线时记录未验收，等待实际可用再交付，不重复要求已说明稍后自行打开 App 的用户解锁。
- [ ] 集成工作区现有离线入口/快捷选项修改时检查交叠，针对新冲突补测，不自动提交其他任务文件。更新文档，明确资料库离线完成度与其他页面离线仍待实现的边界。
- [ ] 按 requesting-code-review / verification-before-completion 工作流完成最终审查及证据确认，修复发现的问题再提交相关文件。用户选择原生执行时，仅最终审查使用独立审查者，不主动拆出实现子任务。
- [ ] 交付提交范围、实际测试、设备安装状态和待人工验收项目；用户认可前不宣称整体体验验收完成。

## 计划自审

设计第 1–3 节由任务 3、7、8 覆盖，第 4 节由任务 1、2 覆盖，第 5 节由任务 4 覆盖，第 6 节由任务 1–3 覆盖，第 7 节由任务 5、6 覆盖，第 8 节由任务 1–9 的验证覆盖。全局用户访问与 Bot 关联授权分开；离线目录同步与文件完成状态分开；群聊不自动授权；旧资源入口和重归集不得绕过删除。

本计划尚未执行。审阅后选择原生执行或子代理逐任务执行，再开始产品代码修改。
