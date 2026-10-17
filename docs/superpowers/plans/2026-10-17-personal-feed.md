# Personalized Feed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a bottom Discover tab backed by persistent, personalized Bot-curated public feeds.

**Architecture:** Dedicated Feed API, SQL store and leased read-only collector; existing authenticated networking and native SwiftUI navigation. Feed data and feedback live independently of chat; discuss via user-sent draft.

**Tech Stack:** Python 3.11+, FastAPI, SQLite, httpx, stdlib XML; Swift 6, SwiftUI iOS17+, existing VeraBotKit.

**Spec:** `docs/superpowers/specs/2026-10-17-personal-feed-design.md` (includes authoritative API JSON contracts).

## Global Constraints

- Work only in the attached personal-feed worktree. Preserve main's existing uncommitted attachment changes. No main merge, remote push, production migration or device replacement.
- New bottom「发现」tab tag=5; keep existing tabs and tags.
- No new product dependencies, truthful content evidence, no private memory in external source queries.
- Test-first behavior changes; isolated databases, no tests using production credentials or data.
- Source-specific limitations and reduced first-version scope must be documented explicitly.

## Review Focus

- SSRF: DNS rebinding and redirects cannot reach internal services; bounded XML / network resources.
- Memory/privacy: total switch, per-Bot scope, expiration and sensitive status enforced before using memory.
- Concurrent pause/deletion invalidates in-flight source results and stops later refreshes.
- Account/server changes discard in-flight client results, including feedback mutations and context drafts.
- Stable pagination and dedupe do not lose saved items or turn duplicate fetches into quota consumption.

### Task 1: Backend Feed subsystem

**Files:** Create `backend/verabot/db/migrations/v036_feed.py`, `db/feed_store.py`, `api/feed_schemas.py`, `api/routers/feed.py`, focused `services/feed/` package (catalog, parser, fetcher, service, worker, __main__), `backend/scripts/test/feed_*_test.py`; modify migrations registration and main route registration only.

**Interfaces:** Consumes current auth/db/memory/HTTP conventions. Produces all JSON endpoints and worker entry defined in Spec; feed source/item IDs are Int, catalog IDs String, nullable fields always serialized.

- [x] Write focused isolated DB / API / parser / worker tests for spec and Review Focus. Run using `PYTHONPATH=backend /Users/admin/Desktop/VeraBot-v0.1/backend/.venv/bin/python -m unittest discover -s backend/scripts/test -p 'feed_*_test.py' -v`; record missing-feature RED.
- [x] Implement v36 migration + SQL store, enforce ownership and optimistic plan version. Tests pin same URL/multiple Bot association, state, cursor and quotas.
- [x] Implement bounded public source fetch, XML extraction and normalization, URL/content validation, evidence labels and source catalog. Never turn source descriptions into invented AI summaries.
- [x] Implement memory-aware suggestions and explicit plan enablement; tests remove sensitive, expired and invisible memory and honor global switch.
- [x] Implement leased worker and persistent refresh; tests pause/delete in-flight, restart, 304, retry/backoff and duplicate budget behavior.
- [x] Run Feed suite plus baseline scheduled task and library suites; add backend runbook and API documentation to `backend/verabot/services/feed/README.md`.
- [x] Commit only backend files. Report tests, commit, deviations and exact endpoint JSON to controller. Do not create subagents.

### Task 2: iOS Discover tab and complete Feed interaction

**Files:** Create Core `Feed.swift`, Networking `FeedAPI.swift` / `APIClient+Feed.swift`, Data `FeedViewModel.swift`, Kit tests `FeedTests.swift`; create focused app `Features/Feed/` views. Modify `App/VeraBotApp.swift`, `ChatView.swift` only for defaulted initial draft entry, `project.yml` / generated project.

**Interfaces:** Consumes Spec's Feed API; APIClient implements separate FeedAPI without growing existing VeraBotAPI mocks. FeedViewModel loads persisted server state and uses generation fencing. Existing app.groupAPI / app.api, userID/serverURL identity, existing bots API and ChatView used for integration.

- [x] Read Task 1's current model JSON / runbook. Write meaningful failing Swift tests for Codable, query filters, pagination, stale requests and feedback errors.
- [x] Implement Core/Networking/Data, use default optional initializers for useful fixtures, no hardcoded user IDs or fake feeds.
- [x] Add tag=5 bottom「发现」tab using native navigation and existing UI components. Four content kinds, Bot filter, saved list, card details/evidence, external original link, load more, retry and explicit refresh.
- [x] Implement onboarding + editable plan + memory/source suggestions, custom subscription form, source pause/resume/status. Any mutation failures remain visible and preserve input.
- [x] Implement ask-Bot: server context -> chosen valid Bot -> existing ChatView with initial draft; no automatic send. Draft seeded without overwriting persisted user draft.
- [x] Run complete Swift Kit suite, generate xcodeproj in this worktree only. Controller runs one iOS build after package tests; do not launch concurrent xcodebuild.
- [x] Commit only frontend files. Report tests, commit, deviations and user paths; no subagents.

### Task 3: Integration, delivery records and whole-branch review

**Files:** `docs/tasks/2026-10-17-personal-feed.md`, `docs/testing/2026-10-17-personal-feed.md`, `docs/STATUS.md`, root/backend/frontend README and `docs/product/FEATURES.md` where appropriate.

**Interfaces:** Tasks 1–2 API/UI contracts and worker; isolated temporary backend / live source checks, existing Intel simulator.

- [x] Run actual fetch against selected public feeds, record source failures honestly; no production database access required.
- [ ] Run full Feed/backend relevant regression and complete Swift Kit, then one Intel simulator build; fix actual failures using tests first.
- [ ] Review complete immutable commit diff with a fresh reviewer, address correctness/privacy findings before delivery.
- [ ] Document implementation and missing platform connectors separately, scope current status to this worktree. Distinguish automated tests, build, install, live source check and user acceptance.
- [ ] Commit docs, leave worktree reviewable, no implicit main merge or push.
