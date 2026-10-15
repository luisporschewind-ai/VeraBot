import Foundation

/// Bot 服务端一次生成的开场词模板（Phase 1）。
public struct OpeningTemplates: Codable, Sendable, Hashable {
    public var version: Int
    public var firstMeeting: [String]
    public var returning: [String]
    public var invite: String

    enum CodingKeys: String, CodingKey {
        case version, invite
        case firstMeeting = "first_meeting"
        case returning
    }

    public init(version: Int = 1, firstMeeting: [String], returning: [String], invite: String) {
        self.version = version
        self.firstMeeting = firstMeeting
        self.returning = returning
        self.invite = invite
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        firstMeeting = try c.decodeIfPresent([String].self, forKey: .firstMeeting) ?? []
        returning = try c.decodeIfPresent([String].self, forKey: .returning) ?? []
        invite = try c.decodeIfPresent(String.self, forKey: .invite) ?? ""
    }
}

public enum OpeningRelationshipStage: String, Sendable {
    case firstMeeting
    case returning
}

public enum OpeningPeriod: String, Sendable, CaseIterable {
    case lateNight = "深夜"
    case morning = "早上"
    case noon = "中午"
    case afternoon = "下午"
    case evening = "晚上"

    public var greetingWord: String {
        switch self {
        case .lateNight: return "深夜好"
        case .morning: return "早上好"
        case .noon: return "中午好"
        case .afternoon: return "下午好"
        case .evening: return "晚上好"
        }
    }
}

/// 日子提示：节假日 > 节气 > 周一/周五/周末。
public enum OpeningDayNote: Equatable, Sendable {
    case holiday(String)
    case solarTerm(String, tip: String)
    case monday
    case friday
    case weekend
    case none

    public var text: String {
        switch self {
        case .holiday(let name): return "\(name)快乐。"
        case .solarTerm(let name, let tip): return tip.isEmpty ? "\(name)了。" : "\(name)了，\(tip)"
        case .monday: return "新的一周，慢慢来。"
        case .friday: return "这周辛苦了。"
        case .weekend: return "周末好时光。"
        case .none: return ""
        }
    }

    /// 拼进 greeting 前缀的日子标签（如「周五」）；节假日/节气用完整 day_note，greeting 只保留时段。
    public var greetingPrefix: String? {
        switch self {
        case .friday: return "周五"
        case .monday: return "周一"
        case .weekend: return "周末"
        default: return nil
        }
    }
}

public enum OpeningCalendar {
    /// 时段：深夜 23–5、早上 5–11、中午 11–13、下午 13–18、晚上 18–23。
    public static func period(at date: Date, calendar: Calendar = .current) -> OpeningPeriod {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 23, 0, 1, 2, 3, 4: return .lateNight
        case 5..<11: return .morning
        case 11..<13: return .noon
        case 13..<18: return .afternoon
        default: return .evening
        }
    }

    public static func dayNote(on date: Date, calendar: Calendar = .current) -> OpeningDayNote {
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        if let holiday = chineseHoliday(year: y, month: m, day: d) {
            return .holiday(holiday)
        }
        if let term = solarTerm(year: y, month: m, day: d) {
            return .solarTerm(term.name, tip: term.tip)
        }
        let weekday = calendar.component(.weekday, from: date) // 1=Sun … 7=Sat
        if weekday == 2 { return .monday }
        if weekday == 6 { return .friday }
        if weekday == 1 || weekday == 7 { return .weekend }
        return .none
    }

    public static func relationshipStage(conversationGeneration: Int) -> OpeningRelationshipStage {
        conversationGeneration > 1 ? .returning : .firstMeeting
    }

    // MARK: - Holidays (公历固定 + 近年农历节日表)

    public static func chineseHoliday(year: Int, month: Int, day: Int) -> String? {
        switch (month, day) {
        case (1, 1): return "元旦"
        case (5, 1): return "劳动节"
        case (10, 1), (10, 2), (10, 3): return "国庆节"
        default: break
        }
        if let name = lunarHolidayTable[year]?[month * 100 + day] {
            return name
        }
        // 清明：近似为 4 月 4/5/6（按年取表）
        if let qingming = qingmingDay[year], month == 4, day == qingming {
            return "清明节"
        }
        return nil
    }

    /// year → (MMdd → 名称)：春节、端午、中秋等
    private static let lunarHolidayTable: [Int: [Int: String]] = [
        2024: [210: "春节", 211: "春节", 212: "春节", 610: "端午节", 917: "中秋节"],
        2025: [129: "春节", 130: "春节", 131: "春节", 531: "端午节", 1006: "中秋节"],
        2026: [217: "春节", 218: "春节", 219: "春节", 619: "端午节", 925: "中秋节"],
        2027: [206: "春节", 207: "春节", 208: "春节", 609: "端午节", 915: "中秋节"],
        2028: [126: "春节", 127: "春节", 128: "春节", 525: "端午节", 1003: "中秋节"],
        2029: [213: "春节", 214: "春节", 215: "春节", 616: "端午节", 922: "中秋节"],
        2030: [203: "春节", 204: "春节", 205: "春节", 605: "端午节", 912: "中秋节"],
    ]

    private static let qingmingDay: [Int: Int] = [
        2024: 4, 2025: 4, 2026: 5, 2027: 5, 2028: 4, 2029: 4, 2030: 5,
    ]

    // MARK: - Solar terms（按年固定公历日表，覆盖常用关心文案）

    public struct SolarTermInfo: Sendable {
        public let name: String
        public let tip: String
    }

    public static func solarTerm(year: Int, month: Int, day: Int) -> SolarTermInfo? {
        guard let map = solarTermTable[year], let entry = map[month * 100 + day] else { return nil }
        return SolarTermInfo(name: entry.0, tip: entry.1)
    }

    /// year → MMdd → (名称, 关心句)
    private static let solarTermTable: [Int: [Int: (String, String)]] = {
        var out: [Int: [Int: (String, String)]] = [:]
        let tips: [String: String] = [
            "立春": "春天要来了。",
            "雨水": "雨水多，出门带把伞。",
            "惊蛰": "天气转暖，别着凉。",
            "春分": "昼夜平分，作息也均衡些。",
            "清明": "踏青正好，记得多喝水。",
            "谷雨": "雨生百谷，别忘添衣。",
            "立夏": "夏天到了，注意防暑。",
            "小满": "小满未满，慢慢来。",
            "芒种": "有事早安排，别太赶。",
            "夏至": "白天最长，记得防晒。",
            "小暑": "天气渐热，多补水。",
            "大暑": "大暑炎热，别在大太阳下久待。",
            "立秋": "立秋了，早晚温差会变大。",
            "处暑": "暑气渐消，别乱减衣。",
            "白露": "白露到，早晚添件衣服。",
            "秋分": "秋高气爽，适合走走。",
            "寒露": "寒露至，注意保暖。",
            "霜降": "霜降了，早晚添件衣服。",
            "立冬": "立冬了，把厚衣服找出来吧。",
            "小雪": "小雪时节，出门小心路滑。",
            "大雪": "大雪将至，注意保暖。",
            "冬至": "冬至到了，吃点热乎的。",
            "小寒": "小寒最冷，别冻着。",
            "大寒": "大寒末伏，再坚持一阵就回暖。",
        ]
        // 近似日期（与常见历书一致，按年微调）
        let byYear: [Int: [(Int, String)]] = [
            2024: [
                (106, "小寒"), (120, "大寒"), (204, "立春"), (219, "雨水"), (305, "惊蛰"), (320, "春分"),
                (404, "清明"), (419, "谷雨"), (505, "立夏"), (520, "小满"), (605, "芒种"), (621, "夏至"),
                (706, "小暑"), (722, "大暑"), (807, "立秋"), (822, "处暑"), (907, "白露"), (922, "秋分"),
                (1008, "寒露"), (1023, "霜降"), (1107, "立冬"), (1122, "小雪"), (1206, "大雪"), (1221, "冬至"),
            ],
            2025: [
                (105, "小寒"), (120, "大寒"), (203, "立春"), (218, "雨水"), (305, "惊蛰"), (320, "春分"),
                (404, "清明"), (420, "谷雨"), (505, "立夏"), (521, "小满"), (605, "芒种"), (621, "夏至"),
                (707, "小暑"), (722, "大暑"), (807, "立秋"), (823, "处暑"), (907, "白露"), (923, "秋分"),
                (1008, "寒露"), (1023, "霜降"), (1107, "立冬"), (1122, "小雪"), (1207, "大雪"), (1221, "冬至"),
            ],
            2026: [
                (105, "小寒"), (120, "大寒"), (204, "立春"), (218, "雨水"), (305, "惊蛰"), (320, "春分"),
                (405, "清明"), (420, "谷雨"), (505, "立夏"), (521, "小满"), (605, "芒种"), (621, "夏至"),
                (707, "小暑"), (723, "大暑"), (807, "立秋"), (823, "处暑"), (907, "白露"), (923, "秋分"),
                (1008, "寒露"), (1023, "霜降"), (1107, "立冬"), (1122, "小雪"), (1207, "大雪"), (1222, "冬至"),
            ],
            2027: [
                (105, "小寒"), (120, "大寒"), (204, "立春"), (219, "雨水"), (306, "惊蛰"), (321, "春分"),
                (405, "清明"), (420, "谷雨"), (506, "立夏"), (521, "小满"), (606, "芒种"), (621, "夏至"),
                (707, "小暑"), (723, "大暑"), (808, "立秋"), (823, "处暑"), (908, "白露"), (923, "秋分"),
                (1009, "寒露"), (1024, "霜降"), (1108, "立冬"), (1122, "小雪"), (1207, "大雪"), (1222, "冬至"),
            ],
        ]
        for (year, entries) in byYear {
            var map: [Int: (String, String)] = [:]
            for (key, name) in entries {
                map[key] = (name, tips[name] ?? "")
            }
            out[year] = map
        }
        return out
    }()
}

public enum OpeningMessageComposer {
    public static let lateNightCare = "早点休息。"

    /// 内置通用模板（生成失败或未就绪时）。
    public static func builtinTemplates(botName: String, persona: String = "") -> OpeningTemplates {
        let invite = inviteHint(name: botName, persona: persona)
        return OpeningTemplates(
            firstMeeting: [
                "{greeting}，我是 **{bot_name}**。{invite}",
                "{greeting}，我是 **{bot_name}**。{day_note}{invite}",
            ],
            returning: [
                "{greeting}，{address}。{day_note}{invite}",
                "{greeting}。{day_note}{invite}{late_care}",
            ],
            invite: invite
        )
    }

    public static func inviteHint(name: String, persona: String = "") -> String {
        let blob = name + persona
        if blob.contains("健康") { return "身体或作息上有什么想留意的，跟我说。" }
        if blob.contains("调查") { return "想查点什么，交给我。" }
        if blob.contains("管家") { return "有事交给我。" }
        return "有什么想聊的，跟我说。"
    }

    public static func compose(
        botName: String,
        persona: String = "",
        templates: OpeningTemplates?,
        address: String?,
        at date: Date = Date(),
        conversationGeneration: Int = 1,
        calendar: Calendar = .current,
        pick: ((Int) -> Int)? = nil
    ) -> String {
        let period = OpeningCalendar.period(at: date, calendar: calendar)
        let day = OpeningCalendar.dayNote(on: date, calendar: calendar)
        let stage = OpeningCalendar.relationshipStage(conversationGeneration: conversationGeneration)
        let pack = (templates.flatMap { $0.firstMeeting.isEmpty || $0.returning.isEmpty ? nil : $0 })
            ?? builtinTemplates(botName: botName, persona: persona)
        let pool = stage == .firstMeeting ? pack.firstMeeting : pack.returning
        let index = (pick?(pool.count) ?? 0)
        let raw = pool.isEmpty ? builtinTemplates(botName: botName, persona: persona).firstMeeting[0]
            : pool[((index % pool.count) + pool.count) % pool.count]

        let greeting = makeGreeting(period: period, day: day)
        let dayNote = day.text
        let lateCare = period == .lateNight ? lateNightCare : ""
        let invite = pack.invite.isEmpty ? inviteHint(name: botName, persona: persona) : pack.invite
        let addr = cleanedAddress(address)

        var text = raw
        text = text.replacingOccurrences(of: "{greeting}", with: greeting)
        text = text.replacingOccurrences(of: "{bot_name}", with: botName)
        text = text.replacingOccurrences(of: "{invite}", with: invite)
        text = text.replacingOccurrences(of: "{day_note}", with: dayNote.isEmpty ? "" : dayNote)
        text = text.replacingOccurrences(of: "{late_care}", with: lateCare)
        text = text.replacingOccurrences(of: "{address}", with: addr)
        return tidy(text)
    }

    public static func makeGreeting(period: OpeningPeriod, day: OpeningDayNote) -> String {
        // 节假日 / 节气细节放在 day_note；问候前缀只拼周一/周五/周末。
        if let prefix = day.greetingPrefix {
            return prefix + period.greetingWord
        }
        return period.greetingWord
    }

    public static func cleanedAddress(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed.count <= 16 else { return "" }
        return trimmed
    }

    /// 去掉因空称呼产生的「，。」「，。」等赘余标点。
    public static func tidy(_ input: String) -> String {
        var s = input
        let replacements = [
            "，。": "。", "，，": "，", "。。": "。",
            "， ": "，", "  ": " ",
        ]
        for _ in 0..<3 {
            for (a, b) in replacements {
                s = s.replacingOccurrences(of: a, with: b)
            }
            // 「晚上好，。」→「晚上好。」
            s = s.replacingOccurrences(of: "，。", with: "。")
            while s.contains("，。") { s = s.replacingOccurrences(of: "，。", with: "。") }
            // 空称呼：`晚上好，。` 或 `晚上好， 。`
            if let regex = try? NSRegularExpression(pattern: "，\\s*。") {
                s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "。")
            }
            if let regex = try? NSRegularExpression(pattern: "，\\s*，") {
                s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "，")
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
