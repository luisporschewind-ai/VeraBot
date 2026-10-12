# Bot Notice Copy Pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect the confirmed Bot notice component to chat message and link copy, and deliver the build on the existing iPhone 17 simulator for user acceptance.

**Architecture:** `RootView` owns one `BotNoticeCenter`, injects it through SwiftUI environment, and hosts the banner over the active root surface. `MessageCopyMenu` performs its existing pasteboard write and then emits one deduplicated success notice; modal scopes and other features remain out of this pilot.

**Tech Stack:** SwiftUI, Observation, the existing `BotNoticeCenter` / `botNoticeHost`, `UIPasteboard`, XcodeBuildMCP iOS Simulator.

**Spec:** `docs/superpowers/specs/2026-10-11-bot-notice-rollout-design.md`

## Global Constraints

- Keep the app deployment target at iOS 17 and add no dependency.
- Use the existing `BotAvatarState.success` and confirmed default notice style.
- Keep the existing copy text transformations and pasteboard behavior unchanged.
- Emit a notice only after the pasteboard write; use one stable key, `chat.copy`.
- Keep modal-specific notice hosting, all non-copy business flows, and `AppState.missingNotice` outside this pilot.
- Do not run UI acceptance on the user's behalf; install on the existing iPhone 17 simulator and hand it over.

## Review Focus

- Copying a full message must preserve the exact full message value in the pasteboard.
- Copying a URL, phone number, or email must preserve the existing prefix-stripping behavior.
- Rapid repeated copies must coalesce under `chat.copy`, without building a backlog of identical notices.
- Leaving Chat or changing the active user/tab must clear an old root notice.
- Returning from background must not reveal a notice from before suspension.

---

### Task 1: Give the active root surface one notice owner

**Files:**
- Modify: `frontend/ios/VeraBot/App/VeraBotApp.swift`
- Reuse: `frontend/ios/VeraBot/Core/UI/Notices/BotNotice.swift`
- Reuse: `frontend/ios/VeraBot/Core/UI/Notices/BotNoticeCard.swift`

**Interfaces:**
- Consumes: `BotNoticeCenter.show(_:key:replacing:)`, `BotNoticeCenter.clear()`, and `View.botNoticeHost(_:style:action:)`.
- Produces: A `BotNoticeCenter` owned for the lifetime of `RootView` and available to root-presented screens through `@Environment(BotNoticeCenter.self)`.

- [x] **Step 1: Own and inject the center**

  Add `@State private var noticeCenter = BotNoticeCenter()` to `RootView`, inject it into the root content environment, and attach `.botNoticeHost(noticeCenter)` to the active root surface so it overlays both the existing main tabs and login flow.

- [x] **Step 2: Clear stale root feedback**

  Clear the root center when the scene becomes inactive, the selected tab changes, the user identity changes, or the session token is removed. Preserve the existing speech player lifecycle handlers in `RootView`.

- [x] **Step 3: Inspect the staged change**

  Confirm the root notice host has a single owner, default styling remains unchanged, and no existing alert, confirmation, or notification behavior is altered.

### Task 2: Emit a Bot notice after chat copy succeeds

**Files:**
- Modify: `frontend/ios/VeraBot/Core/UI/MessageContentView.swift`
- Modify: `frontend/ios/VeraBot/Features/Settings/NoticeLab/NoticeScenario.swift`
- Regenerate: `frontend/ios/VeraBot/Features/Settings/NoticeLab/NoticeSourceIndex.json`
- Update: `docs/design/NOTICE_COMPONENT_LAB.md`

**Interfaces:**
- Consumes: `@Environment(BotNoticeCenter.self)` and the current `MessageCopyMenu` actions.
- Produces: The existing copy and copy-link menu actions write their current value, then call `noticeCenter.show(BotNotice(title: "已复制", tone: .success, avatar: .success), key: "chat.copy")`.

- [x] **Step 1: Share one copy helper**

  In `MessageCopyMenu`, add the environment center and a private helper that accepts the exact string to copy, writes it to `UIPasteboard.general.string`, then enqueues the success notice. Route the full-message and link actions through this helper. Keep `copyText(_:)` and URL, telephone, and email formatting unchanged.

- [x] **Step 2: Record the migrated scene**

  Update the “复制消息 / 链接” catalog row to describe its new Bot banner feedback while preserving its proposed placement and state. Regenerate the static source index with `python3 frontend/ios/scripts/notice-source-index.py` and update the design log to record that this is the first production integration.

- [x] **Step 3: Review the change boundary**

  Confirm no other catalog rows or production actions changed, and the copy notice contains no copied message content, URL, phone number, or email address.

### Task 3: Build and hand off for user acceptance

**Files:**
- No further source changes.

- [x] **Step 1: Build and install on the existing iPhone 17 simulator**

  Use the existing `notice-lab-qa` XcodeBuildMCP profile only after setting its simulator to the original iPhone 17 UDID `6FD1E62D-DA65-42B1-81F5-554042006671`. Launch the app using its normal arguments and stop at the running app; do not open or create another simulator.

- [ ] **Step 2: Hand off the manual acceptance points**

  The user verifies full-message copy, link copy, notice appearance after the context menu closes, repeated-copy behavior, clearing after leaving Chat or switching tabs, and clearing on background / foreground. Do not continue to the next feature category until the user reports acceptance or requests a change.

- [ ] **Step 3: Commit the pilot**

  After user acceptance, commit only the root host, copy integration, updated scenario index, and notice design-log changes. Do not include unrelated speech, group-chat, or documentation changes.

## Next scope after this pilot

After the copy pilot is accepted, prepare a separate plan for low-risk completed-operation feedback, starting with the exact success flows selected from the scenario catalog. Then plan modal-scoped feedback and a row-by-row catalog disposition. Keep inline states, field validation, empty states, explicit confirmations, and operating-system notifications in their current semantic roles unless a later reviewed spec changes that decision.
