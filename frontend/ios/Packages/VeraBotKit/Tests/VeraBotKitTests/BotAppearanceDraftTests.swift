import Foundation
import Testing
@testable import VeraBotCore

@Test func appearanceDraftPreviewCancelAndFailure() throws {
    var draft = BotAppearanceDraft(saved: .robotDefault)
    var changed = draft.current
    changed.parameters.roundness = 0.9
    try draft.update(changed)
    #expect(draft.isDirty && draft.saved == .robotDefault)
    var invalid = changed
    invalid.parameters.roundness = .nan
    #expect(throws: BotAppearanceError.self) { try draft.update(invalid) }
    #expect(draft.current == changed && draft.isDirty)
    draft.cancel()
    #expect(draft.current == .robotDefault && !draft.isDirty)
    try draft.update(changed)
    draft.markSaved()
    #expect(draft.saved == changed && !draft.isDirty)
}

@Test func appearanceTemplateRejectsTrailingNewline() {
    var value = BotAppearance.robotDefault
    value.templateID = "cx-robot\n"
    #expect(throws: BotAppearanceError.self) { try value.validate() }
}
