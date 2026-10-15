import Foundation
import Testing
@testable import VeraBotCore

private func cal(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10) -> (Date, Calendar) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    var comps = DateComponents()
    comps.year = year; comps.month = month; comps.day = day; comps.hour = hour
    let date = calendar.date(from: comps)!
    return (date, calendar)
}

@Test func openingPeriodBuckets() {
    let (_, calendar) = cal(2026, 10, 15)
    #expect(OpeningCalendar.period(at: cal(2026, 10, 15, hour: 3).0, calendar: calendar) == .lateNight)
    #expect(OpeningCalendar.period(at: cal(2026, 10, 15, hour: 8).0, calendar: calendar) == .morning)
    #expect(OpeningCalendar.period(at: cal(2026, 10, 15, hour: 12).0, calendar: calendar) == .noon)
    #expect(OpeningCalendar.period(at: cal(2026, 10, 15, hour: 15).0, calendar: calendar) == .afternoon)
    #expect(OpeningCalendar.period(at: cal(2026, 10, 15, hour: 20).0, calendar: calendar) == .evening)
    #expect(OpeningCalendar.period(at: cal(2026, 10, 15, hour: 23).0, calendar: calendar) == .lateNight)
}

@Test func openingDayMondayFridayWeekend() {
    // 2026-10-16 周五；10-17 周六；10-19 周一
    let fri = cal(2026, 10, 16)
    let sat = cal(2026, 10, 17)
    let mon = cal(2026, 10, 19)
    #expect(OpeningCalendar.dayNote(on: fri.0, calendar: fri.1) == .friday)
    #expect(OpeningCalendar.dayNote(on: sat.0, calendar: sat.1) == .weekend)
    #expect(OpeningCalendar.dayNote(on: mon.0, calendar: mon.1) == .monday)
}

@Test func openingHolidayAndSolarTerm() {
    let national = cal(2026, 10, 1)
    #expect(OpeningCalendar.dayNote(on: national.0, calendar: national.1) == .holiday("国庆节"))
    let frost = cal(2026, 10, 23)
    let note = OpeningCalendar.dayNote(on: frost.0, calendar: frost.1)
    guard case .solarTerm(let name, let tip) = note else {
        Issue.record("expected frost descent solar term")
        return
    }
    #expect(name == "霜降")
    #expect(tip.contains("添件衣服"))
}

@Test func openingRelationshipStage() {
    #expect(OpeningCalendar.relationshipStage(conversationGeneration: 1) == .firstMeeting)
    #expect(OpeningCalendar.relationshipStage(conversationGeneration: 2) == .returning)
}

@Test func openingComposeFirstMeetingNoCityChecklist() {
    let (date, calendar) = cal(2026, 10, 16, hour: 19) // 周五晚
    let text = OpeningMessageComposer.compose(
        botName: "大管家",
        persona: "贴心管家",
        templates: nil,
        address: "Boss",
        at: date,
        conversationGeneration: 1,
        calendar: calendar,
        pick: { _ in 0 }
    )
    #expect(text.contains("大管家"))
    #expect(text.contains("周五晚上好") || text.contains("晚上好"))
    #expect(!text.contains("石家庄"))
    #expect(!text.contains("试试："))
}

@Test func openingComposeReturningFridayEveningExample() {
    let templates = OpeningTemplates(
        firstMeeting: ["{greeting}，我是{bot_name}。{invite}"],
        returning: ["{greeting}，{address}。{day_note}{invite}"],
        invite: "有事交给我。"
    )
    let (date, calendar) = cal(2026, 10, 16, hour: 19)
    let text = OpeningMessageComposer.compose(
        botName: "大管家",
        templates: templates,
        address: "Boss",
        at: date,
        conversationGeneration: 2,
        calendar: calendar,
        pick: { _ in 0 }
    )
    #expect(text == "周五晚上好，Boss。这周辛苦了。有事交给我。")
}

@Test func openingLateNightAddsCare() {
    let templates = OpeningTemplates(
        firstMeeting: ["{greeting}。{late_care}"],
        returning: ["{greeting}。{late_care}"],
        invite: "有事交给我。"
    )
    let (date, calendar) = cal(2026, 10, 15, hour: 1)
    let text = OpeningMessageComposer.compose(
        botName: "健康助手",
        templates: templates,
        address: nil,
        at: date,
        conversationGeneration: 2,
        calendar: calendar
    )
    #expect(text.contains("早点休息"))
}

@Test func openingInviteFollowsPersona() {
    #expect(OpeningMessageComposer.inviteHint(name: "健康助手").contains("身体") || OpeningMessageComposer.inviteHint(name: "健康助手").contains("作息"))
    #expect(OpeningMessageComposer.inviteHint(name: "调查员").contains("查"))
    #expect(OpeningMessageComposer.inviteHint(name: "大管家").contains("交给我"))
}

@Test func openingTidyEmptyAddress() {
    #expect(OpeningMessageComposer.tidy("晚上好，。有事交给我。") == "晚上好。有事交给我。")
}

@Test func openingTemplatesDecode() throws {
    let json = Data(#"{"version":1,"first_meeting":["hi {bot_name}"],"returning":["hey {address}"],"invite":"来吧"}"#.utf8)
    let decoded = try JSONDecoder().decode(OpeningTemplates.self, from: json)
    #expect(decoded.firstMeeting == ["hi {bot_name}"])
    #expect(decoded.invite == "来吧")
}

@Test func botDecodesOpeningFields() throws {
    let json = Data(#"""
    {"id":1,"name":"大管家","avatar":"🤖","color":"#000",
     "opening_templates":{"version":1,"first_meeting":["a"],"returning":["b"],"invite":"c"},
     "opening_address":"Boss"}
    """#.utf8)
    let bot = try JSONDecoder().decode(Bot.self, from: json)
    #expect(bot.openingTemplates?.invite == "c")
    #expect(bot.openingAddress == "Boss")
}
