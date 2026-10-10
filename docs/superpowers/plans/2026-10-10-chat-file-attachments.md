# Chat File Attachments Implementation Plan

> **For agentic workers:** Implement this plan task by task in the current session. The user authorized direct native implementation; do not delegate.

**Goal:** Add secure iOS chat file attachments that VeraBot can read on demand while preserving existing image and camera behavior.

**Architecture:** Extend the existing attachment table, private storage, upload API, and message attachment IDs with a `file` kind. Extract bounded text server-side and expose a read-only `read_file` tool for later pages or ranges. Generalize iOS attachment models and presentation while keeping the existing image preparation path intact.

**Tech Stack:** SwiftUI `.fileImporter`, Quick Look, Swift 6 / VeraBotKit, FastAPI, SQLite migrations, local private attachment storage, `pypdf`, `python-docx`, `openpyxl`, `defusedxml`.

**Spec:** `docs/design/FILE_ATTACHMENT_PLAN.md`

## Global Constraints

- Preserve the existing attachment menu and its image/camera actions; enable only the File action.
- Supported file types: PDF, TXT, MD, CSV, DOCX, XLSX; maximum file size: 10 MB.
- Each message accepts at most one attachment, either image or file.
- Extractable document text must be available by bounded on-demand page/range reads; never claim unread content was read.
- Scanned PDFs remain uploadable and previewable but have no OCR in this release.
- Migrate schema v18 to v19 while preserving existing image rows and files.
- Preserve the user's existing uncommitted changes. Do not stage or commit this implementation.
- Do not add or run tests in this implementation turn; the user did not request testing. Keep manual acceptance unclaimed.

## Review Focus

- A path or crafted filename must never escape the per-user attachment storage root.
- A file ID must be revalidated for user, Bot, message binding, and active status on every read.
- ZIP expansion, document page/sheet counts, parser duration, and per-read size must stay within the spec's limits.
- File text must be treated as untrusted data; write tools remain behind user confirmation.
- Existing image upload, GIF rendering, PhotosPicker, and camera flows must continue to work.

---

### Task 1: Schema v19 and generic attachment repository

**Files:**
- Create: `backend/verabot/db/migrations/v019_file_attachments.py`
- Modify: `backend/verabot/db/migrations/__init__.py`
- Modify: `backend/verabot/db/attachment_store.py`
- Modify: `backend/verabot/services/attachments/repo.py`

**Interfaces:**
- Keep current public repository functions callable by image code; extend them with file-aware behavior rather than renaming all image APIs.
- Add a file creation path that accepts original bytes, validated filename/type, extracted-text metadata, and returns the same public attachment shape with `kind="file"`.
- Extend file lookup to return the original blob and extracted-text key without exposing storage paths publicly.

- [ ] Preserve existing image rows in the v18-to-v19 table rebuild; add fields for filename, extension, text key/status/length, and optional page count.
- [ ] Keep legacy `width` and `height` public values as integers (`0` for files) for old-client decoding.
- [ ] Extend per-user quota, daily count, pending expiry, deletion, and reconciliation to include original files and extracted text.
- [ ] Use the existing random-ID storage layout; never derive a storage path from the client filename.

### Task 2: Safe document extraction and upload/download API

**Files:**
- Create: `backend/verabot/services/attachments/files.py`
- Modify: `backend/verabot/services/attachments/__init__.py`
- Modify: `backend/verabot/api/routers/attachments.py`
- Modify: `backend/pyproject.toml`
- Modify: `backend/uv.lock`
- Modify: `backend/requirements.txt`
- Modify: `backend/Dockerfile`

**Interfaces:**
- `process_file(data: bytes, filename: str) -> ProcessedFile` returns validated `kind`, `mime`, sanitized display filename, extension, page count, extracted-text segments, and byte/hash metadata; raises a typed attachment error for unsupported or over-limit inputs.
- The file content endpoint continues to require normal Bearer authentication and returns `private, no-store` plus `nosniff` headers.

- [ ] Validate the six approved formats using extension and structural checks; reject macros, encrypted files, corrupt files, and limit violations with stable client errors.
- [ ] Extract PDF pages, text/Markdown, CSV rows, DOCX paragraphs/tables, and XLSX cell values without executing embedded content.
- [ ] Apply the spec limits: 10 MB, 15-second parser timeout, 100 MB Office expansion, 2,000 ZIP entries, 200 PDF pages, 10 XLSX sheets, and 5,000 rows per sheet.
- [ ] Keep valid but textless documents attachable for preview and report `empty`/unreadable status explicitly.
- [ ] Accept and store the multipart original filename; sanitize it before metadata and `Content-Disposition` output.
- [ ] Regenerate and synchronize dependency lock/export/container records.

### Task 3: Chat context, file reads, delegation, and confirmation guard

**Files:**
- Modify: `backend/verabot/tools/registry.py`
- Modify: `backend/verabot/agents/runtime.py`
- Modify: `backend/verabot/agents/delegation.py`
- Modify: `backend/verabot/agents/tool_router.py`
- Modify: `backend/verabot/services/attachments/vision.py`
- Modify: `backend/verabot/services/attachments/files.py`
- Modify: `backend/verabot/agents/prompts.py`

**Interfaces:**
- Register `read_file(attachment_id: str, page: int | None, offset: int | None, length: int | None) -> dict` as an attachment-only read tool, available only when the current conversation has an authorized file.
- Return text with source page/range, truncation/continuation metadata, and no local filesystem paths.
- Retain `view_image` and its current semantics; generalize attachment taint/ownership checks without weakening image checks.

- [ ] Pass new file IDs and extracted text into the initial user turn without putting the whole file into every future history request.
- [ ] Enforce same-user, same-Bot/conversation attachment authorization on every `read_file` call; bound text to 30,000 characters per call and two reads per model response.
- [ ] Permit subsequent reads for the same file over additional tool rounds; accurately report unread portions.
- [ ] Pass only explicitly authorized attachment IDs through `ask_bot` delegation and preserve audit IDs without logging file text.
- [ ] Mark file-derived content untrusted and require user confirmation before file-tainted reminder, memory, or external write operations.

### Task 4: Shared Swift models and networking

**Files:**
- Modify: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/Attachment.swift`
- Modify: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotNetworking/APIClient+Attachments.swift`
- Modify: `frontend/ios/Packages/VeraBotKit/Sources/VeraBotNetworking/VeraBotAPI.swift`

**Interfaces:**
- Model `Attachment.kind`, optional file metadata (`filename`, `ext`, `pageCount`, `textStatus`, `textChars`), and retain integer dimensions with `0` interpreted as not applicable for files.
- Extend `uploadAttachment` to accept an explicit filename while preserving image callers.
- Add authenticated content retrieval that can serve both image and file attachments.

- [ ] Keep decoding old servers that omit `attachments` and keep image metadata behavior unchanged.
- [ ] Build multipart filenames safely and preserve the original file extension for document parsing and Quick Look.
- [ ] Map file-specific errors into actionable API error messages.

### Task 5: iOS file importer, composer state, and file preview

**Files:**
- Modify: `frontend/ios/VeraBot/Features/Chat/ChatView.swift`
- Modify: `frontend/ios/VeraBot/Features/Chat/ComposerAttachmentModel.swift`
- Modify: `frontend/ios/VeraBot/Features/Chat/AttachmentViews.swift`
- Modify: `frontend/ios/VeraBot/Features/Chat/ChatViewModel.swift`
- Modify: `frontend/ios/VeraBot/Features/Chat/MessageRow.swift`
- Modify: `frontend/ios/VeraBot/Services/Attachments/AttachmentImageStore.swift`
- Create: `frontend/ios/VeraBot/Services/Attachments/AttachmentFileStore.swift`

**Interfaces:**
- Add file selection and preparation to the existing composer attachment flow, keeping its image path intact.
- Add a generic bubble that routes images to the current image renderer and files to a named Quick Look preview URL.
- Add a safe local file-copy helper that scopes security access to import and deletes temporary copies after upload/cancel.

- [ ] Enable the existing File menu item and present `.fileImporter` for only the six supported types, single selection.
- [ ] Keep the existing image and camera actions, menu structure, and toolbar behavior intact.
- [ ] Enforce the 10 MB client-side limit, show upload/error/retry/remove states, and block sending until the selected attachment is ready.
- [ ] Display file cards in pending and historical messages and support Quick Look preview/share.
- [ ] Clear local file preview cache on logout/account switch alongside existing image cache cleanup.

### Task 6: Calibrate product/status/changelog/acceptance documents

**Files:**
- Modify: `docs/design/FILE_ATTACHMENT_PLAN.md`
- Modify: `docs/design/ATTACHMENTS_DESIGN.md`
- Modify: `docs/STATUS.md`
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/product/FEATURES.md`
- Modify: `docs/testing/TEST_CASES_v0.1.md`

- [ ] Replace legacy v12/v13 file-plan claims with the implemented v19 design and distinguish shipped from pending UI acceptance.
- [ ] Update API field mapping and image-only copy without deleting the user's unrelated current documentation changes.
- [ ] Record the release scope as PDF, TXT, MD, CSV, DOCX, XLSX; 10 MB; one attachment; OCR and other deferred work remain out of scope.
- [ ] Keep Web frozen and state clearly that Web cannot upload or read file attachments.

## Execution Notes

- Work directly in the current checkout because the user explicitly authorized native implementation. Preserve all existing unrelated modified/untracked files.
- Use scoped edits around the user's existing `ChatView.swift` toolbar change and existing status/features text changes.
- Do not commit or stage implementation files; the user has not requested a commit.
- No tests are added or executed in this turn. Any simulator interaction or real-provider acceptance remains unclaimed.
