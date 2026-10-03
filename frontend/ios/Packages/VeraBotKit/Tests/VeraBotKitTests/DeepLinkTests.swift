import Foundation
import Testing
@testable import VeraBotCore

@Test func deepLinksParseAndMissingTargets() {
    #expect(DeepLinkRouter.parse("reminder/12") == .reminder(12))
    #expect(DeepLinkRouter.parse("reminders?bucket=due") == .reminders(bucket: "due"))
    #expect(DeepLinkRouter.parse("bot/3/chat?message=55") == .chat(botID: 3, messageID: 55))
    #expect(DeepLinkRouter.parse("plugin/builtin_reminder") == .plugin("builtin_reminder"))
    #expect(DeepLinkRouter.parse("inbox") == .inbox)
    #expect(DeepLinkRouter.parse("settings/notifications") == .notificationSettings)
    #expect(DeepLinkRouter.parse("nope") == .inbox)

    let reminders: Set<Int> = [12]
    let bots: Set<Int> = [3]
    let plugins: Set<String> = ["builtin_reminder"]
    #expect(DeepLinkRouter.resolve("reminder/12", reminderIDs: reminders, botIDs: bots, pluginIDs: plugins) == .navigate(.reminder(12)))
    #expect(DeepLinkRouter.resolve("reminder/99", reminderIDs: reminders, botIDs: bots, pluginIDs: plugins) == .missing)
    #expect(DeepLinkRouter.resolve("bot/8/chat?message=1", reminderIDs: reminders, botIDs: bots, pluginIDs: plugins) == .missing)
    #expect(DeepLinkRouter.resolve("plugin/gone", reminderIDs: reminders, botIDs: bots, pluginIDs: plugins) == .missing)
    #expect(DeepLinkRouter.resolve("inbox", reminderIDs: reminders, botIDs: bots, pluginIDs: plugins) == .navigate(.inbox))
}

@Test func notificationJSONDecodesMissingFields() throws {
    let json = ##"{"id":4,"category":"reminder","title":"交周报","link":"reminder/4","thread_id":"rem-4","reminder_id":4,"created_at":"2026-10-03T02:00:00+00:00"}"##
    let note = try JSONDecoder().decode(InboxNotification.self, from: Data(json.utf8))
    #expect(note.isUnread)
    #expect(note.reminderId == 4)
    #expect(note.threadId == "rem-4")
    #expect(note.sensitive == false)
    let settings = try JSONDecoder().decode(NotificationSettings.self, from: Data(#"{"preview":"title"}"#.utf8))
    #expect(settings.preview == "title")
    #expect(settings.quietStart == "23:00")
    let odd = try JSONDecoder().decode(InboxNotification.self, from: Data(#"{"id":1,"category":"future","title":"x"}"#.utf8))
    #expect(odd.category == .unknown)
}
