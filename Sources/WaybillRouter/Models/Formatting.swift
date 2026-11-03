import Foundation

enum Fmt {
    static let pl = Locale(identifier: "pl_PL")

    static func km(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(pl))
    }

    static func money(_ v: Double) -> String {
        v.formatted(.currency(code: "PLN").locale(pl))
    }

    static func dayMonth(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = pl
        f.dateFormat = "dd.MM"
        return f.string(from: d)
    }

    /// Dzień miesiąca, np. „05”.
    static func day(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = pl
        f.dateFormat = "dd"
        return f.string(from: d)
    }

    /// Skrót dnia tygodnia, np. „pon.”.
    static func weekdayShort(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = pl
        f.dateFormat = "EEE"
        return f.string(from: d)
    }

    static func full(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = pl
        f.dateFormat = "dd.MM.yyyy"
        return f.string(from: d)
    }

    static func month(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = pl
        f.dateFormat = "LLLL yyyy"
        return f.string(from: d).capitalized(with: pl)
    }

    /// Nagłówek dnia: „Dziś”, „Wczoraj”, „Jutro” albo np. „Środa, 5 listopada”.
    static func dayTitle(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Dziś" }
        if cal.isDateInYesterday(d) { return "Wczoraj" }
        if cal.isDateInTomorrow(d) { return "Jutro" }
        return weekdayDate(d)
    }

    /// Np. „Środa, 5 listopada”.
    static func weekdayDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = pl
        f.dateFormat = "EEEE, d MMMM"
        let s = f.string(from: d)
        return s.prefix(1).uppercased(with: pl) + s.dropFirst()
    }

    static func duration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }
}

extension Date {
    var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self)) ?? self
    }

    func addingMonths(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: n, to: self) ?? self
    }

    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    func addingDays(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: self) ?? self
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    func isSameMonth(as other: Date) -> Bool {
        Calendar.current.isDate(self, equalTo: other, toGranularity: .month)
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
