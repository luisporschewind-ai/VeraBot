import Foundation
import Testing
@testable import VeraBotCore

@Test func avatarFigureIdsFitAvatarField() {
    #expect(BotAvatarFigure.maxStoredLength == 8)
    #expect(BotAvatarFigure.allCases.count == 5)
    #expect(BotAvatarFigure.allCases.allSatisfy { $0.rawValue.unicodeScalars.count <= BotAvatarFigure.maxStoredLength })
    #expect(BotAvatarFigure.veraBean.rawValue.unicodeScalars.count == 8)
    let titles = Set(BotAvatarFigure.allCases.map(\.title))
    #expect(titles == ["V豆", "芽芽", "星点", "云朵", "方糖"])
}

@Test func avatarFigureStoredIdWinsOverLegacyEmoji() {
    #expect(BotAvatarFigure(stored: "veraBean") == .veraBean)
    #expect(BotAvatarFigure(stored: "sprout") == .sprout)
    #expect(BotAvatarFigure(stored: "star") == .star)
    #expect(BotAvatarFigure(stored: "cloud") == .cloud)
    #expect(BotAvatarFigure(stored: "sugar") == .sugar)
    #expect(BotAvatarFigure.default == .veraBean)
}

@Test func legacyEmojiMapsOntoFiveFigures() {
    #expect(BotLook.emojis.count == 16)
    for (index, emoji) in BotLook.emojis.enumerated() {
        let figure = BotAvatarFigure.allCases[index % BotAvatarFigure.allCases.count]
        #expect(BotAvatarFigure(stored: emoji) == figure)
    }
    #expect(BotAvatarFigure(stored: "🤖") == .veraBean)
    #expect(BotAvatarFigure(stored: "🐼") == .star)
}

@Test func unknownAvatarMapsStably() {
    let first = BotAvatarFigure(stored: "xyz")
    #expect(BotAvatarFigure(stored: "xyz") == first)
    #expect(BotAvatarFigure(stored: "") == .veraBean)
}

@Test func photoBeatsDefaultFigure() {
    #expect(BotAvatarDisplay(hasPhoto: true, storedAvatar: "sugar") == .photo)
    #expect(BotAvatarDisplay(hasPhoto: true, storedAvatar: "🐼") == .photo)
    #expect(BotAvatarDisplay(hasPhoto: false, storedAvatar: "sugar") == .figure(.sugar))
    #expect(BotAvatarDisplay(hasPhoto: false, storedAvatar: "🐼") == .figure(.star))
}

@Test func figureTextLabelKeepsLegacyEmoji() {
    #expect(BotAvatarFigure.textLabel(stored: "sugar") == "方糖")
    #expect(BotAvatarFigure.textLabel(stored: "veraBean") == "V豆")
    #expect(BotAvatarFigure.textLabel(stored: "🐼") == "🐼")
    #expect(BotAvatarFigure.textLabel(stored: nil) == "V豆")
    #expect(BotAvatarFigure.textLabel(stored: "") == "V豆")
}

@Test func avatarPoseMapsAllTenExecutionStates() {
    let cases: [(ExecutionState, BotAvatarPose)] = [
        (.idle, .idle),
        (.recalling, .thinking),
        (.thinking, .thinking),
        (.callingTool(name: "get_weather"), .working),
        (.delegating(botName: "小研", progress: nil), .delegating),
        (.delegating(botName: "小研", progress: DelegationProgress(botName: "阿厨", depth: 2, tool: "x")), .delegating),
        (.replying, .replying),
        (.blocked(code: "loop", message: "m"), .blocked),
        (.failed(message: "e"), .blocked),
        (.awaitingConfirmation, .waiting),
        (.completed, .done),
    ]
    #expect(cases.allSatisfy { BotAvatarPose($0.0) == $0.1 })
    #expect(Set(cases.map(\.1)) == Set(BotAvatarPose.allCases))
    #expect(BotAvatarPose.allCases.count == 8)
}
