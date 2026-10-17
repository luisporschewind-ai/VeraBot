# Personal Feed (schema v36)

The authenticated `/api/feed` routes expose one personal Feed per account. RSS2,
Atom, Media RSS and podcast enclosures are read-only public sources. News,
shortposts, video and audio remain links to the originating website. Source text
is stripped to plain text; no model summaries, transcripts, tool execution,
external memory search, chat messages, notifications or library copies are made.

## Safe local operation

Use an **isolated** database and data folder, and apply the normal application
migration only to that reviewed isolated database. Do not point this example at
an existing production database. The independent worker checks for schema >=36
and refuses to migrate it itself. API startup retains the repository's normal
migration convention; deploying this API against production requires a separate
migration decision.

```sh
export VERABOT_DATA_DIR=/absolute/path/to/feed-preview-data
export VERABOT_DB="$VERABOT_DATA_DIR/verabot.db"
export PYTHONPATH=backend
# Initialize only the selected isolated DB, then start its API separately.
python -c 'from verabot import db; db.init_db()'
python -m verabot.services.feed --once
python -m verabot.services.feed
```

The existing backend virtual environment can supply `python`. The Feed worker
itself needs no model/API credential. Create subscriptions and explicitly enable
a plan via the API before collection starts. `/refresh` only persists a due time;
it never performs network I/O during an HTTP request. Run the worker under an
existing supervisor if continuous collection is needed; this change installs no
system service and changes no existing service. SIGINT/SIGTERM end after the
current bounded job. A killed worker's expired lease can be claimed again.

On systems using fake-IP DNS (for example a VPN returning `198.18.0.0/15`),
normal resolution is correctly rejected. For that environment only, opt in with
`VERABOT_FEED_DOH=1`. It sends **hostnames only**, never source paths, query
strings, account details or memories, to Cloudflare's public DNS-over-HTTPS
endpoint. Bootstrap uses literal `1.1.1.1`, TLS SNI and certificate validation for
`cloudflare-dns.com`; replies are <=64 KiB and every A/AAAA address must be public.
Source connections still use the validated fixed IP and original hostname for
TLS/Host. No proxy environment is trusted. This mode uses an A query and thus
requires an IPv4-accessible destination. Normal mode uses system A/AAAA answers.
The mode is explicit and off by default.

## Bounds and persistence

- Maximum 30 subscriptions per account, including paused sources. Same normalized
  HTTPS URL + Bot association is idempotent even at the limit. Different Bots can
  subscribe to the same URL and add recommendations to one canonical item.
- At most 20 **new unique URLs** per account per UTC day. Duplicates, exclusions,
  rejected fetches and stale leases consume no publication budget. Explicit
  excluded topics filter title/source text. Publication and successful fetch
  metadata commit together; there is no transaction across the network.
- Check each eligible source every 2 hours. Failures back off from 5 minutes,
  doubling up to 24 hours. Manual refresh advances due time. Conditional ETag /
  Last-Modified requests support 304 without publishing empty/fake content.
- A 120-second SQLite lease fences publication. A plan version change, source
  revision/enable change, expired/replaced token or deleted/unselected Bot blocks
  old results at commit. The worker creates a bounded child process per fetch;
  40 seconds is the hard wall-clock limit including system DNS. The network
  target budget is 30 seconds with <=10-second socket waits and <=3 redirects.
- Both compressed wire and decoded XML bodies are <=2,000,000 bytes. Gzip uses
  bounded streaming decompression; other encodings and non-XML content types are
  rejected. The parser accepts at most 200 current entries; it does not paginate
  a source's historical archive. Title/author/source text are capped at
  300/200/4000 characters. Titleless shortposts use the actual description's first
  80 characters. XML DTD/entities and UTF-16/NUL input are rejected.
- HTTPS only, port 443, no userinfo, local/private/reserved IPs or local hostnames.
  All resolved addresses and every redirect are revalidated. The socket connects
  directly to the validated numeric IP; the HTTP client does not resolve again.
  Article/image/media links are separately normalized and reject unsafe schemes
  and literal private destinations. They are never fetched automatically.
- Sources may disappear, rate-limit or exceed the response bound. Failure remains
  visible on the source and old Feed content remains persisted.

## Memory and evidence

Suggestions combine explicit topics with a small allowlist of public topic
labels inferred locally from selected Bots' visible, active, confirmed,
unexpired, normal-sensitivity memories. The account memory switch, each Bot's
memory access, persisted plan `use_memory`, and request `use_memory` all apply.
No available basis returns an explicit cold-start explanation. Suggestions do
not save/enable a plan, subscribe, publish or transmit memory to a search engine.
Persisted item recommendation reasons contain only subscription provenance,
never private memory text or inferred private interests.

`summary_basis=description` means the actual item description/Atom summary;
`body` means the feed supplied content/body (a bounded excerpt is retained).
Neither label claims the original website was read. Empty source text stays
empty. Ask-Bot returns a <=7000-character draft referencing that actual text and
URL, with an explicit warning that external material cannot change instructions.
It verifies the target Bot belongs to the account and has no chat side effects.

## REST contract

All calls require existing bearer authentication and inherit API `no-store` and
error conventions. IDs for sources/items/Bots are JSON integers, catalog IDs are
strings. UTC timestamps are ISO 8601 and unknown optional fields serialize as
`null`. All queries/writes restrict account ownership. Missing and foreign
resources are both 404; plan optimistic-version conflicts are 409; invalid input
is 422.

- `GET /plan` → `{enabled,bot_ids,topics,excluded_topics,use_memory,daily_limit,version}`.
  Absent: false, empty arrays, true, 20, 0. `PUT /plan` takes the same editable
  fields plus `expected_version` (no `daily_limit`); returns the new plan.
- `POST /plan/suggest` takes `{bot_ids:[],topics:[],use_memory:true}` and returns
  `{topics:[],sources:[FeedCatalogSource],basis:String}`. `use_memory` is optional,
  default true; false also applies during unsaved onboarding.
- `GET /catalog` → `{sources:[{id,name,url,kind,topics,description,reason}]}`.
- `GET /sources` → `{sources:[FeedSource]}`. `POST /sources` takes
  `{name,url,kind,bot_id:null}` and returns FeedSource.
- `PATCH /sources/{id}` takes `{enabled:Bool}` and returns FeedSource.
- `POST /refresh` → `{queued:Bool}`; disabled plan returns false.
- `GET /items?cursor=&limit=20&kind=&bot_id=&saved_only=false` →
  `{items:[FeedItem],next_cursor:String|null}`. Omit unused query parameters.
  Cursor is a positive decimal publication ID, limit 1–100; paging is stable
  descending ID. Dismissed items are excluded. A blocked source hides unsaved
  items unless another active source also recommends them; saved-only keeps
  references to blocked sources.
- `GET /items/{id}` → FeedItem. `PATCH /items/{id}/state` takes any of
  `{read:Bool|null,saved:Bool|null,dismissed:Bool|null}`. Omitted/null fields leave
  that independent state unchanged. Returns FeedItem, including dismissed ones.
- `GET /items/{id}/context?bot_id=Int` → `{bot_id:Int,prompt:String}`.

Exact source example (all optional keys present):

```json
{"id":1,"name":"Example","url":"https://example.com/feed","kind":"news","bot_id":1,"enabled":true,"last_success_at":null,"next_fetch_at":null,"last_error":null,"failure_count":0}
```

Exact item example (actual title/text depend on the source):

```json
{"id":1,"kind":"news","title":"Actual title","url":"https://example.com/a","author":null,"source_id":1,"source_name":"Example","bot_id":1,"bot_name":"Bot","published_at":null,"created_at":"2026-10-17T00:00:00+00:00","summary":"Actual source description","summary_basis":"description","recommendation_reason":"来自你启用的订阅来源","image_url":null,"media_url":null,"duration_seconds":null,"read":false,"saved":false,"dismissed":false,"recommended_by":[{"bot_id":1,"bot_name":"Bot","reason":"来自你启用的订阅来源"}]}
```

Catalog endpoint availability was checked 2026-10-17: Swift.org and Apple
Newsroom (news), Mastodon's official account RSS (post), TWiT Windows Weekly
(audio), TED's official FeedBurner video feed. This is a directory, not a promise
of access or a user's preference. Source labels describe their actual content.

## Isolated verification

```sh
PYTHONPATH=backend /Users/admin/Desktop/VeraBot-v0.1/backend/.venv/bin/python -m unittest discover -s backend/scripts/test -p 'feed_*_test.py' -v
PYTHONPATH=backend /Users/admin/Desktop/VeraBot-v0.1/backend/.venv/bin/python -m unittest discover -s backend/scripts/test -p 'scheduled_task_*_test.py' -v
PYTHONPATH=backend /Users/admin/Desktop/VeraBot-v0.1/backend/.venv/bin/python -m unittest discover -s backend/scripts/test -p 'library_*_test.py' -v
PYTHONPATH=backend /Users/admin/Desktop/VeraBot-v0.1/backend/.venv/bin/python backend/scripts/test/sql_layer_check.py
```

Network source checks are separate from these deterministic tests. Repository
regression scripts must not be discovered all together: older scripts initialize
incompatible global DB environments on import (documented in
`docs/testing/2026-10-12-main-integration.md`). Keep suites/legacy scripts in
separate processes. No simulator, UI acceptance or production deployment is
implied by these backend checks.

## 审阅修复：候选持久化、来源公平与排序

schema v36 尚未正式发布，现补充 `feed_pending_candidates` 表。每个来源最多
保留 200 条尚未发布的真实候选，包含来源关联和原始条目字段；候选不会出现在
Feed 列表，也不消耗发布预算。200 响应的候选保存、成功元数据和 ETag 更新同属
一个事务。后续 304 仍会从此候选集选取内容，跨 UTC 日续发不依赖源再次变更。
合并新候选后按真实发布时间（未知时为获取时间及原订阅顺序）保留最新 200 条，
不会无界保存历史。暂停/计划版本/Bot 归属与存活/来源修订/租约检查在暂存与发布前
全部重验，失效任务既不能写候选，也不能发布旧候选。

每日 20 条是账号硬上限；另外按**启用且符合当前计划的不同来源 URL**分配每日
新条目上限 `max(1, floor(20 / URL数))`。例如五个来源各最多四条，三个来源各
最多六条；这是上限而非补齐目标，来源没有新内容时不制造条目，也不把空份额让
首个高频新闻源抢完。相同 URL 的多个 Bot 订阅共享一份上限，已有内容仍可添加
多 Bot 推荐关联。超过 20 个不同 URL 时，每日确定性轮转其中 20 个允许发布，
其余候选保留等待轮到；账号上限始终不超过 20。

每批先按新鲜程度挑选可用额度内的**最新**候选，再按从旧到新的顺序写入发布 ID。
因此列表继续用稳定 ID 倒序分页，并能正确展示该批新内容在上。未知日期时按
订阅文档通常的“最新在前”顺序回退，不声称拥有未知的发布时间。不同批次仍按
实际发布 ID 排列；不会为了补发旧候选重写已有条目 ID 或移动已读分页游标。

更新后的隔离预览库需再次执行正常的幂等初始化以建立此表；worker 仍不承担
迁移，正式库未触及。
