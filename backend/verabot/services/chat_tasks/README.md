# Durable ordinary private chat (schema v30)

The API commits inputs and observes persisted work. A **separate process** runs the original chat runtime, including memory, streamed text, attachments, builtin/MCP tools and delegation. A dropped observation connection never cancels this worker.

```sh
# From backend/, after setting the same persistent VERABOT_DB and VERABOT_DATA_DIR as API:
python -m verabot.services.chat_tasks
python -m verabot.services.chat_tasks --once
```

Do not use a different encryption-key directory for API and Worker. v30 backs up an existing older SQLite DB with SQLite backup (`.bak-before-v30-*`), creates old-history read baselines, and is idempotent. No deployment/service supervision is installed by this code. Single host SQLite and the existing single API group-worker constraint remain. Ordinary chat concurrency is bounded by `VERABOT_CHAT_CONCURRENCY` (default 4) and `VERABOT_CHAT_USER_CONCURRENCY` (default 2), with one running reply per private conversation. Waiting replies release that slot. Queue order is task ID order; context contains completed messages before the task's stable input ID, excluding later queued inputs. Acceptance freezes tool names, delegation targets and memory scope. Every dispatch (including pending checkpoint calls and MCP dispatch) intersects those grants with current Bot permissions; later permission additions do not enlarge an already accepted task. The input and assistant placeholder are adjacent IDs from one transaction.

## Exact HTTP contract

All endpoints require the existing bearer authentication and isolate records by user and conversation. All timestamps are UTC ISO8601 strings. Numeric IDs and cursors are JSON integers. Extra unknown fields can be ignored. Error bodies use `{"detail":{"code":"...","message":"..."}}` (existing validation errors retain their established shape).

`POST /api/bots/7/chat/inputs`

```json
{"client_request_id":"input-uuid-1","message":"帮我整理这份资料","attachment_ids":[],"expected_generation":1}
```

First acceptance returns **202**; exact replay returns **200** with the **same original receipt**, not a refreshed task. Reusing the request ID with a different payload returns 409 `request_conflict`. Request IDs are nonempty strings up to 128 characters, scoped by user/Bot and retained across clears. Message is limited to 4000 characters; a nonempty attachment list permits blank text. At most one attachment, with the existing upload/ownership/expiry/file-presence checks. Binding and both messages are atomic. A receipt replay skips attachment/budget revalidation, because the same input may already be attached or executed.

```json
{
  "task":{"id":12,"bot_id":7,"generation":1,"client_request_id":"input-uuid-1","state":"queued","phase":"queued","version":1,"wait_id":null,"error_code":null,"created_at":"2026-10-14T01:00:00+00:00","updated_at":"2026-10-14T01:00:00+00:00","user_message_id":31,"assistant_message_id":32,"content":"","traces":[],"message_status":"queued","publication_revision":0},
  "user_message_id":31,"assistant_message_id":32,"generation":1,"cursor":81
}
```

`GET /api/bots/7/chat/inputs/input-uuid-1` returns that same receipt, or 404 `not_accepted`. A network error is not proof of nonacceptance. Reconcile or resend **the same payload and ID**; never fall back to legacy `/chat`. A receipt survives clear and still describes its original generation; use the execution/activity snapshot to detect that clear.

`GET /api/bots/7/chat/execution` returns a consistent SQLite snapshot. `cursor` is the **account activity cursor**; `event_cursor` is the **private detail cursor**. Do not interchange them. Tasks are current-generation records ordered by task ID, including completed records for recovery. Each task uses precisely the shape above, with fresh state/partial content/traces/publication revision.

```json
{"generation":1,"cursor":85,"event_cursor":19,"tasks":[{"id":12,"bot_id":7,"generation":1,"client_request_id":"input-uuid-1","state":"running","phase":"replying","version":1,"wait_id":null,"error_code":null,"created_at":"2026-10-14T01:00:00+00:00","updated_at":"2026-10-14T01:00:02+00:00","user_message_id":31,"assistant_message_id":32,"content":"这份资料","traces":[],"message_status":"running","publication_revision":0}]}
```

States: `queued`, `running`, `awaiting_user`, `awaiting_approval`, `completed`, `failed`, `stopped`, `interrupted`. Phase also includes `recalling`, `thinking`, `tool`, `delegating`, `replying`, and `retry_wait`. Short bounded retries retain `running` state and use `retry_wait` phase. Phase changes do not advance the task version; stop or continuation does. Partial text has no readable publication revision until a question or terminal result is published.

`POST /api/bots/7/chat/tasks/12/stop`

```json
{"expected_version":1,"control_request_id":"stop-uuid-1"}
```

Returns 200 `{"task":{...fresh task...},"generation":1,"cursor":90}`. Replay returns the saved response, including its original version/cursor. The same control ID with changed payload conflicts. Stopping queued/current/waiting work persists a terminal readable explanation; running calls are canceled by the Worker monitor. An external action already underway cannot be undone, but cannot deliver late text or schedule new calls.

`POST /api/bots/7/chat/tasks/12/inputs`

```json
{"client_request_id":"answer-uuid-1","expected_version":2,"wait_id":"wait:12:2","message":"这周"}
```

Returns the same envelope as stop plus integer `answer_message_id` for the atomically saved user answer; increments version and queues the **same assistant identity**. Only the exact `awaiting_user` task/version/wait ID accepts this input; duplicate exact answers replay their response, wrong/stale references return 409 `wait_changed`/`task_changed`. The answer is saved in history and in this execution checkpoint; it does not create a second ordinary task. Unknown external-action outcomes remain blocked (`operation_unknown`); a new independent message can discuss verification, but this endpoint does not blindly retry that action.

Approvals use the existing `POST /api/pending-actions/{action_id}/confirm` or `/cancel`. `wait_id` is `action:123`. The frozen action insert, live task/version/generation validation, current/frozen tool permission check and task association are committed in one write transaction before the action is visible; the final execution claim checks those again inside its write transaction. Exact action-result content is encrypted and replaces its checkpoint tool result on continuation. Approved external content restores the normal untrusted-content guard, MCP-call count and cross-service source accounting before any pending tool or later model round runs. Runtime and observer trace lists have separate ownership on checkpoint restore, preserving one result frame per tool identity in future history. Approval rejection/expiry also resumes from the saved tool result to report the outcome. Duplicate confirmation remains the established 409 behavior. Unknown or stale claimed outcomes become `awaiting_user` with `wait_id=unknown:123`; no automatic external replay.

## History, attachments, publication and reads

New clients use existing `GET /api/bots/7/messages/sync`. Each message retains its existing fields and now adds `message_status`, `generation`, `publication_revision`; page adds `generation`. IDs themselves are stable conversation order (input, reserved reply, later input/reply), including when an earlier reply completes later. Revision-pinned paging retains existing 409 `sync_revision_changed`; partial writes advance history revision, so reconcile by stable IDs rather than appending duplicate bubbles.

```json
{"generation":1,"revision":10,"messages":[{"id":31,"role":"user","content":"帮我整理这份资料","traces":[],"message_status":"completed","generation":1,"publication_revision":0,"created_at":"2026-10-14T01:00:00+00:00","attachments":[{"id":"att_example","kind":"file","mime":"text/plain","width":0,"height":0,"bytes":120,"status":"attached","expires_at":null,"filename":"notes.txt","ext":"txt","page_count":null,"text_status":"ready","text_chars":120}],"feedback":null},{"id":32,"role":"assistant","content":"整理完成","traces":[{"id":"call1","name":"read_file","args":{"attachment_id":"att_example","offset":0},"result":{"text":"资料内容"}}],"message_status":"completed","generation":1,"publication_revision":1,"created_at":"2026-10-14T01:00:00+00:00","attachments":[],"feedback":null}],"next_before_id":null,"unchanged":false}
```

Group history retains `status` and adds `generation`, `publication_revision`. All readable assistant/Bot results, questions, failures and interruptions publish in their message-writing transaction; tool traces and streaming fragments do not count. A readable waiting question is revision 1; its final answer is a later revision on **the same message ID**, even if the question was already read. Legacy complete history is read by default at migration; inbox notifications keep their independent state.

`GET /api/conversations/activity`

```json
{"cursor":95,"conversations":[{"kind":"private","conversation_id":7,"generation":1,"revision":95,"state":"running","phase":"thinking","unread_count":1,"pending_count":0,"unread_messages":[{"message_id":32,"publication_revision":2}],"work_items":[{"id":13,"state":"running","phase":"thinking","version":1,"wait_id":null,"source":"chat"}],"latest_message":{"id":33,"content":"下一个问题","created_at":"2026-10-14T01:00:10+00:00"}}]}
```

`kind` is `private` or `group`; `conversation_id` is Bot or group ID. Empty rows use state/phase `idle`, `work_items:[]`, `latest_message:null`. `work_items.source` is `chat`, `owned`, or `group`; group work adds `owner_member_id`. Private rows include ordinary work and owned tasks still targeting this generation; group work never mixes into member private rows. Priority is waiting → ordinary running → other running → queued → failure/interruption. `pending_count` counts waits; `unread_count` is exact (client caps display at 99+). Account cursor and all summaries are read in one transaction; no pagination or event retention is currently applied.

`POST /api/conversations/private/7/read` (replace `private/7` with `group/9` for group)

```json
{"generation":1,"messages":[{"message_id":32,"publication_revision":2}]}
```

Returns 200 `{"cursor":96,"conversation":{...current summary...}}`. It advances only the listed message revisions, never clears unread gaps. Stale older reads are harmless; future/unpublished/deleted revisions return 409 `publication_changed`; wrong generation returns 409 `generation_changed`. Reading a fragment with revision 0 is not allowed. Only the client can establish actual foreground visibility; preload/list visibility must never call read. Keep the local entry-session new-message label set after server reads.

## Durable SSE frames

After the consistent snapshots, consume `GET /api/conversations/events?after_id=95` using account cursor, and `GET /api/bots/7/chat/events?after_id=19` using detail cursor. `after_id` is explicit; Last-Event-ID header is not currently used. Streams poll persisted rows every 0.5 seconds and send keepalive comments when idle. Canceling either HTTP stream only ends observation.

Account events: `activity_updated`, `message_published`, `messages_read`, `message_deleted`, `conversation_cleared`, `conversation_deleted`. Every frame has persistent ID and `kind`, `conversation_id`, `generation`, and a fresh `conversation` summary (null for deleted conversations). IDs can have gaps because the global table holds other users' events; no retention/pruning is applied. An ahead-of-current cursor returns HTTP 409 `cursor_invalid`; if ownership disappears during a detail stream it sends `resync_required` then closes. Generation changes are explicit events; discard old-generation detail frames and re-fetch snapshots.

```text
id: 96
event: messages_read
data: {"kind":"private","conversation_id":7,"generation":1,"conversation":{"kind":"private","conversation_id":7,"generation":1,"revision":96,"state":"idle","phase":"idle","unread_count":0,"pending_count":0,"unread_messages":[],"work_items":[],"latest_message":{"id":32,"content":"整理完成","created_at":"2026-10-14T01:00:00+00:00"}}}

id: 20
event: message_updated
data: {"message_id":32,"content":"这份资料","traces":[],"message_status":"running","publication_revision":0,"task_id":12,"generation":1,"version":1}

id: 21
event: task_updated
data: {"task":{"id":12,"bot_id":7,"generation":1,"client_request_id":"input-uuid-1","state":"completed","phase":"completed","version":1,"wait_id":null,"error_code":null,"created_at":"2026-10-14T01:00:00+00:00","updated_at":"2026-10-14T01:00:02+00:00","user_message_id":31,"assistant_message_id":32,"content":"整理完成","traces":[],"message_status":"completed","publication_revision":1},"task_id":12,"generation":1,"version":1}

id: 22
event: done
data: {"message_id":32,"user_message_id":31,"usage":{"total_tokens":5},"memory_ids":[],"task_id":12,"generation":1,"version":1}

: keepalive

```

Private events also retain original `status`, `tool_start`, `tool_result`, `confirmation_required`, `error`, `done` payloads, adding `task_id`, `generation`, `version`. Status payload uses established `phase/depth/bot_name/tool/parent_id`. `accepted` and `task_updated` carry `task`. `message_updated` is a complete partial snapshot, **not a delta to append**. Every readable terminal task update contains final publication revision and traces. Recovery interruptions may carry `reason` rather than task: fetch execution on any `task_updated` if needed.

## Recovery and compatibility boundaries

Partial body is flushed at 256 characters or at a deadline one second from its first unsaved fragment, with important tool/phase changes immediately. The monitor shortens its next sleep to that deadline; timing is independent of heartbeat/phase offset. Lease heartbeat/stop checks run every 0.5 seconds. Safe connection failures before any provider output retry at most twice; streams with output and uncertain writes are not automatically replayed. Provider attempts and known usage are durably recorded. Completed tool identities, frozen args and results are encrypted under the action key; reusing a tool identity with changed params conflicts. Expired running leases preserve partial body and publish `interrupted`; approval checkpoints resume without repeating prior tools and retain taint/call/delegation/round limits.

Clear advances generation, stops ordinary work and removes read/publication records. Deleting either running input or output fences that execution. Deleting an active input keeps its paired reply identity and atomically publishes a stopped explanation (preserving partial content); it emits a `task_updated` detail frame with `reason:message_deleted` and `message_id` so clients can re-fetch execution. Deleting the output keeps it deleted; late Worker results never recreate it. Completed historical pairs retain the existing single-message deletion semantics. Bot deletion cancels its still-pending linked action. Owned task records remain in the task center, but their captured old delivery generation suppresses private redelivery after clear. Notification failure uses a savepoint so it cannot roll back owned-message publication.

Legacy requests atomically reserve their conversation until the stream finishes. New submission returns `chat_busy` while that reservation exists; legacy reservation likewise rejects already accepted durable work. The existing single API process clears abandoned legacy reservations at API startup. Legacy `POST /api/bots/{id}/chat` is retained but returns 409 `chat_busy` while an ordinary durable task is queued/running/waiting. Legacy message listing hides uncompleted placeholders. Legacy requests still have their original request-bound execution behavior; do not claim detached execution for old clients. Backend uptime, persistent storage and supervision are still required; APNs, real-provider/device acceptance and actual localhost disconnect integration evidence are separate delivery steps.
