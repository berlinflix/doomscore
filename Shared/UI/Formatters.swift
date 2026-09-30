import Foundation

enum Fmt {
    /// 950 → "950", 12_400 → "12.4k", 1_200_000 → "1.2m"
    static func compact(_ value: Int) -> String {
        let v = Double(value)
        switch abs(v) {
        case ..<10_000: return value.formatted()
        case ..<1_000_000: return String(format: "%.1fk", v / 1_000).replacingOccurrences(of: ".0k", with: "k")
        default: return String(format: "%.1fm", v / 1_000_000).replacingOccurrences(of: ".0m", with: "m")
        }
    }

    /// 3_700 s → "1h 1m", 420 s → "7m", 20 s → "20s"
    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        let minutes = s / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// 0 → "12am", 13 → "1pm"
    static func hour(_ hour: Int) -> String {
        let h = ((hour % 24) + 24) % 24
        switch h {
        case 0: return "12am"
        case 12: return "12pm"
        case 1..<12: return "\(h)am"
        default: return "\(h - 12)pm"
        }
    }

    static func weekday(_ index: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        guard (0..<symbols.count).contains(index) else { return "" }
        return symbols[index]
    }

    static func percent(_ fraction: Double) -> String {
        let value = Int((fraction * 100).rounded())
        return value > 0 ? "+\(value)%" : "\(value)%"
    }

    static func dayTitle(_ day: DayKey) -> String {
        let date = day.startDate()
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func periodTitle(_ period: StatsPeriod, interval: DateInterval) -> String {
        let calendar = Calendar.current
        let now = Date()
        switch period {
        case .day:
            return dayTitle(DayKey(interval.start))
        case .week:
            if interval.contains(now) { return "This week" }
            let end = interval.end.addingTimeInterval(-1)
            return "\(interval.start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
        case .month:
            if calendar.isDate(interval.start, equalTo: now, toGranularity: .month) { return "This month" }
            return interval.start.formatted(.dateTime.month(.wide).year())
        case .year:
            return interval.start.formatted(.dateTime.year())
        }
    }
}
