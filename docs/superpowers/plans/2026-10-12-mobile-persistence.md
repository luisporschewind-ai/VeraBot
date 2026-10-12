# 移动端 SQLite 持久化实施计划

2026-10-12 状态：实现已保存并整合到本地 main，当前验证与设备边界见 [Main 集成交付](../../testing/2026-10-12-main-integration.md)。下方为原实施步骤，原先不提交/合并限制已由本轮用户明确授权覆盖；未触发的真实服务与设备交互不标记通过。

> **For agentic workers:** Execute this plan task-by-task in the current session. Keep unrelated working-tree changes intact.

**Goal:** 让 Bot/群列表及已同步的完整私聊、群聊历史可在 iOS 断网和重启后读取，并保留草稿与中断中的消息内容。

**Architecture:** 新建无 UI 的 SQLite 持久化模块与数据访问/Repository 模块。Repository 先读本地，再以版本校验的分页协议和现有 API 同步；页面通过 Repository 加载和写入。后端提供私聊、群聊一致快照分页和版本冲突检测。

**Tech Stack:** Swift 6、SPM、SQLite C API、FastAPI、Python sqlite3。

**Spec:** `docs/superpowers/specs/2026-10-11-mobile-persistence-design.md`

## 全局约束

- iOS deployment target 继续为 iOS 17；Swift Package 继续支持 macOS 14 测试目标。
- 保留 URLSession ephemeral / URLCache disabled 的 HTTP 缓存安全边界。
- 本地 scope 使用规范化服务器地址与服务器用户 ID；令牌不写业务数据库。
- 所有异步结果写入前检查认证 generation、Repository scope 与会话 epoch。
- 不清理、不覆盖、不暂存、不提交工作区内与本功能无关的现有改动。
- 后端迁移只在隔离测试数据库验证；不升级实际服务数据库，不部署、不推送。
- 首轮不实现图片/文件原始字节缓存或私聊自动补发；群聊恢复复用现有 request UUID。

## 评审关注

- 历史分页过程中消息变化，不能以混合版本完成对账。
- 未完整同步时进程退出，不能将未下载页误判为删除。
- 删除/清空之后迟到的同步结果不能让内容复活。
- 登录切换或服务器地址变化之后，旧请求不能写入新的账号库。
- done 丢失时的私聊本地消息须保留且不能猜测匹配或自动重发。

---

### Task 1: 后端会话修订版本和一致历史页

**Files:**
- Create: `backend/verabot/db/migrations/v021_conversation_sync.py`
- Modify: `backend/verabot/db/migrations/__init__.py`
- Modify: `backend/verabot/api/routers/chat.py`
- Modify: `backend/verabot/api/routers/groups.py`
- Create: `backend/verabot/db/conversation_sync_store.py`

**Interfaces:**
- `GET /api/bots/{bot_id}/messages/sync?limit=&before_id=&expected_revision=`
- `GET /api/groups/{group_id}/messages/sync?limit=&before_id=&expected_revision=`
- Each endpoint returns `revision`, `messages`, `next_before_id`, `unchanged`.
- Revision storage keyed by `(user_id, kind, conversation_id)` and advanced in the same transaction as any mutation represented by the serialized page.

**Steps:**
- Add schema migration and revision maintenance for private messages, feedback, attachments, group messages/turn state fields that affect page output, and existing rows. Preserve the existing private-history endpoint.
- Implement both snapshot page handlers with permission checks, maximum page size 100, stable ordering, and a single read transaction for revision and page fields. Reject a mismatched expected revision with HTTP 409 `sync_revision_changed`.
- Confirm the endpoint response and transaction boundaries against the shared schema and existing access checks.

### Task 2: SQLite persistence package and migration layer

**Files:**
- Modify: `frontend/ios/Packages/VeraBotKit/Package.swift`
- Create: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotPersistence/LocalDatabase.swift`
- Create: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotPersistence/ConversationStore.swift`

**Interfaces:**
- `LocalDatabase.open(url:)`, `migrate()`, `transaction(_:)`, `close()`.
- `ConversationStore` operates on typed Codable snapshots and exposes list/message page, draft, message upsert/delete, staging, and sync-state operations.
- Schema includes conversations, messages with stable local UUID and optional remote ID, drafts, card states, sync state, sync staging, and list state.

**Steps:**
- Add SQLite system-library linkage usable by iOS/macOS without third-party package dependencies.
- Implement parameter-bound statements, foreign keys, WAL, busy timeout, transactional schema versioning, and database file protection at the App-provided URL boundary.
- Implement atomic writes for messages, drafts, sync staging/cursor, and completed reconciliation markers.
- Inspect migration, transaction, reopen, uniqueness, and paging paths for consistency.

### Task 3: API sync contracts and Repository

**Files:**
- Modify: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/` sync response models
- Modify: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotNetworking/VeraBotAPI.swift`
- Modify: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotNetworking/APIClient.swift`
- Modify: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotNetworking/GroupChatAPI.swift`
- Create: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotData/ConversationRepository.swift`
- Create: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotData/ConversationSyncCoordinator.swift`
- Modify: `frontend/ios/Packages/VeraBotKit/Package.swift`

**Interfaces:**
- Add typed private/group sync page contracts and API methods.
- Repository exposes local page reads, `syncConversation`, cached conversation lists, draft writes, local message lifecycle writes, delete/clear, and scope invalidation.
- Inject API protocols and `ConversationStore`; do not introduce a second network client.

**Steps:**
- Parse new endpoint responses without changing existing API contracts.
- Implement local-first list and history access, revision-pinned pagination, durable staging, resumable page cursor, two automatic conflict restarts, and atomic final reconciliation.
- Order current conversation ahead of remaining list sync; coalesce duplicate sync requests and reject stale generation/epoch results.
- Implement local deletion/clear only after remote success (accept existing 404 semantics), prevent late sync resurrection, and preserve independent list success/failure.
- Inspect pagination beyond 500 messages, crash/resume, conflict restart, deletion reconciliation, and stale-session suppression.

### Task 4: AppState scope and Bot/group list local-first rendering

**Files:**
- Modify: `frontend/ios/VeraBot/App/AppState.swift`
- Modify: `frontend/ios/VeraBot/Features/BotList/BotListView.swift`
- Modify: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotNetworking/GroupChatViewModel.swift` only if needed for injection boundary

**Interfaces:**
- AppState owns the active scope's Repository, created from canonical server URL, authenticated user ID, and current generation.
- BotList receives cached Bot/group snapshots first and reconciles after successful remote list calls.

**Steps:**
- Create scope-hashed Application Support database path, apply iOS file-protection and backup-exclusion attributes, and open only after user identity is established.
- Invalidate and close old scope before sign-out/account/server switch; delete current account data only for explicit sign-out, retaining current auth-expired behavior.
- Render cached Bot/groups immediately. Distinguish never-synced, partial, complete-empty, and offline states; only delete cached records after that list's request succeeds.
- Keep Bot navigation and group selection behavior intact; synchronize selected conversation first.

### Task 5: Private chat local-first history, draft, and interrupted stream recovery

**Files:**
- Modify: `frontend/ios/VeraBot/Features/Chat/ChatViewModel.swift`
- Modify: `frontend/ios/VeraBot/Features/Chat/ChatView.swift`

**Interfaces:**
- Inject active `ConversationRepository` and session scope into `ChatViewModel`.
- Preserve stable local IDs for persisted items; remote integer IDs remain optional.

**Steps:**
- Load latest local page synchronously/asynchronously before remote sync; fetch older pages locally without blocking on network. Show welcome state only after complete empty synchronization.
- Persist draft with 300 ms debounce and immediate lifecycle/send flush. Preserve editor contents on local write failure and failed/offline send.
- Save user/assistant placeholders before starting stream; checkpoint deltas at 500 ms or 2 KiB and on stream/lifecycle transitions. Bind server IDs from `done` to existing local rows.
- On relaunch, mark unfinished private sends unconfirmed/interrupted and preserve text/Trace. Never auto-retry or match by body/time. Provide explicit recovery display and allow edit/discard.
- Route successful delete/clear through Repository and make errors retain local content.

### Task 6: Group chat history, draft, and running turn recovery

**Files:**
- Modify: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotNetworking/GroupChatViewModel.swift`
- Modify: `frontend/ios/VeraBot/Features/GroupChat/GroupChatView.swift`

**Interfaces:**
- Inject the same Repository while preserving existing `GroupChatAPI`, `GroupChatReducer`, and generation-aware session closure.
- Persist group `GroupMessage`, `GroupTurn` identity/status, local draft, and local page cursor.

**Steps:**
- Restore local latest page and draft before remote load; use existing remote group turn query to reconcile active turn with its original request UUID.
- Persist message deltas/checkpoints and reducer snapshots; do not show a stale persistent running animation after relaunch.
- Load older pages from local storage, then remote snapshot synchronization; clear local rows only after server clear/delete succeeds.
- Keep read-only group behavior and existing stop/retry semantics intact.

### Task 7: Integration review, build, and manual acceptance preparation

**Files:**
- Modify: `docs/STATUS.md`
- Create or update: `docs/testing/2026-10-12-mobile-persistence.md`

**Steps:**
- Review the complete diff for scope isolation, data resurrection, transaction boundaries, partial-history behavior, and stream recovery.
- Report the exact validation performed and distinguish source review from user/device acceptance.
- Prepare simulator offline acceptance for cold launch, >500 messages, mid-sync termination, in-flight send restart, cross-account switching, and another-device deletion.
- Do not install on the user's devices, run a production database migration, publish, commit, merge, or push without explicit authorization.
