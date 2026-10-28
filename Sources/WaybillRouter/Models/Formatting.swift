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

    func isSameMonth(as other: Date) -> Bool {
        Calendar.current.isDate(self, equalTo: other, toGranularity: .month)
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
