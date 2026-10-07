# VeraBot Memory M3 and M4 design

**Status:** Draft for owner review  
**Source:** `docs/design/MEMORY_GROWTH.md` §§8, 11.2–11.3, 17.1, 20  
**Scope:** Implement Memory M3 and M4 in sequence. Memory M5 is explicitly out of scope until the owner chooses an embedding/retrieval plan.

## Goal and constraints

M3 should let Vera notice durable user preferences and routines without silently activating them, offer a small number of actionable suggestions, and make repeated prompts easier to enter. M4 should make memory and usage understandable, reviewable, searchable, and exportable. All inferred memories remain inactive until the user confirms them.

Keep the current DeepSeek chat provider, SQLite database, single-process memory worker, iOS client, and frozen Web client. Keep each migration additive and idempotent. Use per-user ownership checks on every API and query. Do not send raw conversation history to the M4 review model. Do not add cloud embeddings, vector storage, RAG, automatic permission changes, notifications, or gamification in these milestones.

## Delivery sequence

1. M3 ships as schema v15. It adds extraction, candidate review, suggestions, and quick prompts.
2. M4 ships as schema v16. It adds growth statistics, monthly reviews, export, memory search/filtering, usage counts, and the memory references view.
3. M5 remains parked. The existing M5 proposal for local `bge-small-zh` is not authorization to install or download a model; the owner will choose that approach separately.

Each milestone must work independently, preserve API compatibility, update its implementation notes and acceptance records, and be committed separately. Do not include current root-workspace changes in either milestone.

## M3: implicit candidates, suggestions, quick prompts

### Extraction trigger and inputs

- Queue one `extract` job per Bot after each six new user messages since the previous extraction. Also enqueue when a conversation has been idle for at least ten minutes, checked on the next request. Coalesce duplicate pending work using the existing `memory_jobs` behavior.
- Use the last 12 user messages for that Bot, identified by message IDs. Assistant text may be included only as up to 200 characters of local context per message. Never include tool results, MCP results, attachment contents, or delegated-agent output.
- Include only the Bot's currently visible active memories for deduplication and update proposals. Honor `memory_access`; if it is `none`, do not extract or expose memories.
- Use JSON output at temperature 0 and a 600-token output cap. Count all model usage as `kind=memory`; skip when memory is disabled or daily usage has reached 90% of its budget.

### Candidate validation and persistence

- Accept only `profile`, `preference`, `fact`, `routine`, and `style`; scope is `global` or `bot`, with `memory_access=bot` forcing `bot` scope.
- Require content of 1–200 characters, confidence in [0.6, 1.0], and at least one evidence ID from the input's user-message IDs. At most three creates and updates combined may be emitted per job. Discard malformed JSON, invalid records, prompt-injection indicators, sensitive/credential content, content rejected by the existing memory policy, and candidates whose bigram Jaccard similarity with an active/pending memory is at least 0.8.
- Persist creates and updates as `status=candidate`, `source=implicit_extraction`, with a 14-day expiry. Updates use `action=update` and `target_id`; they do not replace active memory before confirmation. Store evidence IDs and the model's short reason in the existing JSON `meta` field; use the latest valid evidence ID as `source_message_id`.
- Candidate content is never injected into prompts. Confirmation reuses the existing memory confirm flow; rejection reuses the existing reject flow. Expiry clears candidate content and metadata that contains user text.
- Show a “待确认” group in the memory page. Add a once-per-day, non-blocking conversation label when new candidates exist; tapping opens that Bot's memory page. Do not show candidate text in push/local notifications.

### Suggestions

- Store suggestions in a new `suggestions` table (v15), scoped to the owning user and Bot, with kind, bounded JSON payload, status, created/expiry/decision times. Never store secrets or arbitrary prompt text in payloads.
- Create a routine-reminder suggestion only from an active `routine` memory or at least three matching reminders on distinct weeks with sufficiently similar title and local weekday/time. A suggestion is shown in that Bot's next conversation. Accept creates one recurring reminder through the existing reminder service; the operation and suggestion status must be idempotent. Dismiss suppresses the same normalized suggestion for 30 days.
- Create a delegation suggestion only when the same user has asked the same source Bot to delegate to the same existing Bot at least three times in 14 days and that target is not already permitted. Accept navigates to the source Bot's permissions; it never changes `delegate_to` automatically. Dismiss suppresses it for 30 days.
- Add authenticated list/accept/dismiss APIs with tenant checks and replay-safe transitions. Suggestions expire after 30 days. The conversation card is non-blocking and has explicit accept / dismiss actions.

### Quick prompts

- Add `GET /api/bots/{id}/quick-prompts`; require the caller to own the Bot. Return at most six prompts and no message IDs.
- Rank the Bot's own normalized user-message texts from the last 30 days by frequency (at least three occurrences), taking at most four. Fill remaining slots from templates for enabled tools (weather and reminders). Exclude prompts blocked by the existing sensitive-content policy, prompts over 80 characters, and duplicates after normalization.
- Add an iOS setting enabled by default. Show one horizontal row of system glass buttons only when the composer is empty and not focused. Tapping fills the composer without sending. Fetch lazily when the conversation opens and refresh after a new completed user turn; failures hide the row without affecting chat.

## M4: growth, monthly review, export, memory usage

### Growth summary

- Add authenticated `GET /api/bots/{id}/growth`. Return counts by active memory type, assistant-message count, successful delegation-answer count, first conversation date, and up to three recently confirmed memories. Compute counts from user-owned rows and existing conversation/delegation records; do not infer growth from job logs.
- Display plain text rows in the Bot detail memory section. No levels, scores, ranks, badges, progress bars, or streaks.

### Monthly review

- Add a `reviews` table (schema v16), unique by user and month, and reuse `memory_jobs.kind=review` for generation. Generate on the first memory-page visit in a month, with a single cached result per user/month; concurrent requests must not create duplicate reviews.
- The review model receives only aggregate counts, enabled-tool usage aggregates, newly confirmed memories, and a count of pending candidates. It receives no raw messages, message summaries, tool arguments/results, or candidate text. Sensitive memories are excluded from model input and review output.
- Count only completed assistant turns and successful delegations. The response contains assists, common capability categories, new confirmed memories (IDs and safe text for display), pending-candidate count, and at most one short suggestion. Validate every referenced memory ID against the user before returning it.
- The memory page shows a monthly row that opens a plain List. New confirmed memories link to their memory detail and can be deleted there. Do not notify users proactively. If generation fails, return safe aggregate fields with review status `unavailable`; allow a later retry without creating duplicate completed reviews.
- Charge model usage as `kind=memory`; skip generation at 90% of the daily budget and return the aggregate-only view.

### Search, filtering, references, and export

- Add in-memory search and type filtering to the existing memory list; search only records already returned by the user's own memory query. Keep pending candidates grouped separately.
- Include `use_count` and `last_used_at` in memory detail. For an assistant response with recorded `memory_ids`, add a “参考了哪些记忆” action that fetches/resolves only those IDs under the same user and Bot visibility rules. A missing, deleted, or no-longer-visible memory is omitted.
- Add authenticated `GET /api/memories/export` returning the owner's memories and metadata as JSON. Include decrypted sensitive content only when the existing key can decrypt it; otherwise export the existing safe placeholder. Never include tokens, audit records, conversation text, or other users' rows. The iOS export action uses the system share sheet; exporting is user initiated.

## API and storage versioning

- v15 adds only `suggestions`; existing `memories.meta` stores candidate evidence/reason without a new evidence table. Index user/Bot/status/expiry for pending suggestions and deduplication.
- v16 adds `reviews` with `UNIQUE(user_id, month)` plus indexes for lookup and job status as needed.
- Keep migrations idempotent and backup/restore behavior consistent with existing migrations.
- All new API failures use the current safe error format. Logs and audit events contain IDs, kind, status, and short error codes only—never memory text, evidence text, review text, or suggestion payload text.

## Acceptance gates

### M3

- Extraction triggers at six user messages and at idle after ten minutes on the next request; duplicate pending work coalesces.
- Only user-role evidence is accepted; malformed output, invalid evidence, low confidence, sensitive/injection content, duplicates, and empty output yield no candidate.
- Candidate creates and updates remain inactive and uninjectable until confirmation; reject/expiry clear text; valid evidence metadata is retained while pending.
- Each suggestion type obeys its threshold, acceptance/dismissal behavior, 30-day cooldown, tenant isolation, and duplicate-request idempotency.
- Quick prompts use only the owner's current Bot history, return at most six safe prompts, and tapping never sends a message.

### M4

- Growth counts match database rows and exclude other users; deleted or inaccessible memories are not disclosed in response references.
- At most one cached monthly review exists per user/month. Model input contains only allowed aggregates and newly confirmed non-sensitive memories; failures/budget skips degrade to safe aggregate-only output.
- Export contains all and only the requesting user's memory records, with sensitive content decrypted only through the existing crypto service and no chat history.
- Search/filter and referenced-memory flows preserve scope, status, and Bot access rules.

## Explicit deferrals

- M5 embeddings, vector index, hybrid retrieval, historical-chat RAG, and delegation memory sharing/optimization.
- Web UI, push notifications, automatic Bot permission changes, and automatic application of candidate updates.
- New sensitive-data categories or new encryption behavior beyond the existing memory policy.
