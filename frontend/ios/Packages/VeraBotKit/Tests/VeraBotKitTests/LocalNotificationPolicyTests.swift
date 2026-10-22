import Testing
@testable import VeraBotCore

@Test func foregroundReminderUsesInAppNotice() {
    #expect(LocalNotificationPolicy.presentation(isForeground: true, isReminder: true, soundEnabled: true) == .inApp)
    #expect(LocalNotificationPolicy.presentation(isForeground: true, isReminder: true, soundEnabled: false) == .inApp)
}

@Test func backgroundReminderKeepsSystemNotification() {
    #expect(LocalNotificationPolicy.presentation(isForeground: false, isReminder: true, soundEnabled: true) == .system(sound: true))
    #expect(LocalNotificationPolicy.presentation(isForeground: false, isReminder: true, soundEnabled: false) == .system(sound: false))
}

@Test func foregroundNonReminderKeepsSystemBanner() {
    #expect(LocalNotificationPolicy.presentation(isForeground: true, isReminder: false, soundEnabled: true) == .system(sound: true))
    #expect(LocalNotificationPolicy.presentation(isForeground: true, isReminder: false, soundEnabled: false) == .system(sound: false))
}
