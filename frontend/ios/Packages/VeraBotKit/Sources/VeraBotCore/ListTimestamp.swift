import Foundation

/// 会话列表右上角的时间文案（与系统「信息」类似）：
/// 今天 → HH:mm；昨天 → 昨天；本周内 → 星期几；更早 → M/d；非今年 → yyyy/M/d。
public enum ListTimestamp {
    /// 解析后端的 ISO 8601 时间（如 `2026-10-01T02:28:50+00:00`，可带小数秒）。
    public static func parse(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: iso) { return d }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: iso)
    }

    /// 行的时间：最后一条消息时间，缺失时回退 Bot 创建时间。
    public static func rowDate(for bot: Bot) -> Date? {
        parse(bot.lastMessage?.createdAt) ?? parse(bot.createdAt)
    }

    /// 完整的本地时间：「2026/10/1 17:32」（协作记录等明细用）。
    public static func fullLabel(for date: Date, calendar: Calendar = .current,
                                 locale: Locale = Locale(identifier: "zh_Hans_CN")) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.dateFormat = "yyyy/M/d HH:mm"
        return f.string(from: date)
    }

    public static func label(for date: Date, now: Date = Date(), calendar: Calendar = .current,
                             locale: Locale = Locale(identifier: "zh_Hans_CN")) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        if calendar.isDate(date, inSameDayAs: now) {
            f.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(date, relativeTo: now) {
            return "昨天"
        } else if date < now, calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            f.dateFormat = "EEEE"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            f.dateFormat = "M/d"
        } else {
            f.dateFormat = "yyyy/M/d"
        }
        return f.string(from: date)
    }
}

extension Calendar {
    func isDateInYesterday(_ date: Date, relativeTo now: Date) -> Bool {
        guard let y = self.date(byAdding: .day, value: -1, to: now) else { return false }
        return isDate(date, inSameDayAs: y)
    }
}
