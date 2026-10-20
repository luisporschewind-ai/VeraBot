import Foundation
import Testing
@testable import VeraBotCore

private func makeBot(id: Int = 7, name: String = "小满") throws -> Bot {
    let json = """
    {"id":\(id),"name":"\(name)","avatar":"🌊","color":"#0F766E","persona":"安静","instructions":""}
    """
    return try JSONDecoder().decode(Bot.self, from: Data(json.utf8))
}

private func makeEncounter(endedAt: Double? = nil,
                           expiresAt: Double = 2_000) -> DriftBottleEncounter {
    DriftBottleEncounter(
        id: 1, bottleID: 2, botID: 7, botName: "小满", botAvatar: "🌊",
        botColor: "#0F766E", botDeleted: false, startedAt: 1_000, expiresAt: expiresAt,
        endedAt: endedAt, endReason: endedAt == nil ? nil : .returned, version: 2,
        bottleVersion: 3, leaseToken: "lease-token", readLimit: 2, quiet: false,
        remainingSeconds: 500, isExpired: false, canPublish: endedAt == nil,
        contributions: [], nextCursor: nil, turns: [], memory: nil)
}

@Suite struct DriftBottlePresentationTests {
    @Test func unicodeScalarsMatchServerCodePointLimit() {
        #expect(DriftBottlePresentation.characterCount("🌊") == 1)
        #expect(DriftBottlePresentation.characterCount("👨‍👩‍👧‍👦") == 7)
        #expect(DriftBottlePresentation.validatePublic(String(repeating: "🌊", count: 1000)) == nil)
        #expect(DriftBottlePresentation.validatePublic(String(repeating: "🌊", count: 1001)) != nil)
        #expect(DriftBottlePresentation.validatePublic("   ") != nil)
    }

    @Test func publicPreviewKeepsPrivateTalkOutAndLabelsAuthorship() {
        let preview = DriftBottlePresentation.publicPreview(
            text: "我把早餐店写进了信里。", authorship: .coauthored, botName: "小满")
        #expect(preview.text == "我把早餐店写进了信里。")
        #expect(preview.authorshipLabel == "与 Bot 合写")
        #expect(preview.boundaryNotice.contains("私人交流不会公开"))
        #expect(preview.boundaryNotice.contains("后续捞到这个瓶子的人都能读到"))
    }

    @Test func generatedDraftIsNotMarkedAsOwnerWritten() {
        #expect(DriftBottlePresentation.authorshipAfterGeneration(.owner) == .botDraft)
        #expect(DriftBottlePresentation.authorshipAfterGeneration(.coauthored) == .coauthored)
        #expect(DriftBottlePresentation.authorshipAfterGeneration(.botDraft) == .botDraft)
    }

    @Test func factualMemoryDoesNotInventSharedHistory() {
        #expect(DriftBottlePresentation.factualMemoryTitle(hasChat: false, botName: "小满")
                == "我们一起读了一封信")
        let title = DriftBottlePresentation.factualMemoryTitle(hasChat: false, botName: "小满")
        #expect(!title.contains("分享"))
        #expect(!title.contains("经历"))
    }

    @Test func publishStopsAtExpiryAndAfterReturn() {
        let now = Date(timeIntervalSince1970: 1_500)
        #expect(DriftBottlePresentation.canPublish(text: "一句话", endedAt: nil,
                                                   expiresAt: 2_000, now: now))
        #expect(!DriftBottlePresentation.canPublish(text: "一句话", endedAt: nil,
                                                    expiresAt: 1_500, now: now))
        #expect(!DriftBottlePresentation.canPublish(text: "一句话", endedAt: 1_600,
                                                    expiresAt: 2_000, now: now))
        var encounter = makeEncounter()
        #expect(DriftBottlePresentation.canPublish(encounter: encounter, now: now))
        encounter = makeEncounter(endedAt: 1_600)
        #expect(!DriftBottlePresentation.canPublish(encounter: encounter, now: now))
    }

    @Test func botAvailabilityDistinguishesTravelingAndDeleted() throws {
        let bot = try makeBot()
        #expect(DriftBottlePresentation.botAvailability(bot: bot, traveling: false) == .ready)
        #expect(DriftBottlePresentation.botAvailability(bot: bot, traveling: true) == .traveling)
        #expect(DriftBottlePresentation.botAvailability(bot: nil, traveling: false) == .missing)
    }
}
