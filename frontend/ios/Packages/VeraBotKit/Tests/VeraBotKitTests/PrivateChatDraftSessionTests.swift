import Testing
import VeraBotCore

@Test func privateChatDraftTwoEntriesHydrateSameBotWithoutStaleDisappearWrite() throws {
    var shared = "unfinished question"
    var assistants = PrivateChatDraftSession()
    let first = assistants.begin()
    #expect(assistants.hydrate(saved: shared, entry: first) == "unfinished question")
    assistants.edit("edited question")
    let flushed = assistants.leave()
    shared = try #require(flushed)

    var discover = PrivateChatDraftSession(incoming: "source context")
    let second = discover.begin()
    #expect(discover.hydrate(saved: shared, entry: second) == "edited question\n\nsource context")
    let save = try #require(discover.pendingWrite)
    shared = save.text
    discover.acknowledge(save)
    #expect(discover.leave() == nil)
    // A retained inactive view cannot write its old text during another disappear callback.
    #expect(assistants.leave() == nil)
    let returned = assistants.begin()
    #expect(assistants.hydrate(saved: shared, entry: returned) == "edited question\n\nsource context")
    #expect(assistants.pendingWrite == nil)
}

@Test func privateChatDraftIncomingContextIsConsumedOnceAcrossRepeatedAppearances() throws {
    var draft = PrivateChatDraftSession(incoming: "source context")
    let first = draft.begin()
    let hydrated = draft.hydrate(saved: "existing", entry: first)
    let initial = try #require(hydrated)
    let save = try #require(draft.pendingWrite)
    draft.acknowledge(save)
    #expect(draft.leave() == nil)
    let again = draft.begin()
    #expect(draft.hydrate(saved: initial, entry: again) == "existing\n\nsource context")
    #expect(draft.pendingWrite == nil)
}

@Test func privateChatDraftPreservesTypingDuringHydration() throws {
    var draft = PrivateChatDraftSession(incoming: "source context")
    let entry = draft.begin()
    draft.edit("typed while loading")
    #expect(draft.pendingWrite == nil)
    #expect(draft.hydrate(saved: "shared draft", entry: entry) == "shared draft\n\ntyped while loading\n\nsource context")
    let save = try #require(draft.pendingWrite)
    #expect(save.text == "shared draft\n\ntyped while loading\n\nsource context")
    draft.edit("a newer edit")
    draft.acknowledge(save)
    #expect(draft.pendingWrite?.text == "a newer edit")
}

@Test func privateChatDraftLeaveBeforeHydrationRejectsStaleTextAndLateCompletion() {
    var draft = PrivateChatDraftSession(incoming: "source context")
    let first = draft.begin()
    _ = draft.hydrate(saved: "old retained text", entry: first)
    _ = draft.leave()
    let second = draft.begin()
    #expect(draft.text.isEmpty && draft.isHydrating)
    #expect(draft.leave() == nil)
    #expect(draft.hydrate(saved: "new shared draft", entry: second) == nil)
    #expect(draft.pendingWrite == nil)
}

@Test func privateChatDraftFencesDebouncedSavesAndIgnoresProgrammaticHydration() throws {
    var draft = PrivateChatDraftSession()
    let entry = draft.begin()
    let hydrated = draft.hydrate(saved: "saved\n", entry: entry)
    let restored = try #require(hydrated)
    let changed = draft.edit(restored)
    #expect(!changed)
    #expect(draft.pendingWrite == nil)
    draft.edit("my edit")
    let pending = try #require(draft.pendingWrite)
    #expect(draft.canSave(pending))
    #expect(draft.leave() == "my edit")
    #expect(!draft.canSave(pending))
    let hiddenEdit = draft.edit("hidden stale edit")
    #expect(!hiddenEdit)
}

/// Account/server switch discards the active entry without flushing a write to the new identity.
@Test func privateChatDraftAccountSwitchDiscardsActiveEntryWithoutFlush() {
    var draft = PrivateChatDraftSession(incoming: "source context")
    let entry = draft.begin()
    #expect(draft.hydrate(saved: "", entry: entry) == "source context")
    draft.edit("typed after hydrate")
    #expect(draft.pendingWrite?.text == "typed after hydrate")
    // ChatView sessionGeneration handler cancels saves then leave()s without persisting.
    _ = draft.leave()
    #expect(draft.leave() == nil)
    #expect(draft.pendingWrite == nil)
    #expect(!draft.isActive)
}
