import Foundation

enum CalendarMath {
    static func weekDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
        let start = interval?.start ?? calendar.startOfDay(for: date)
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    static func monthStart(for date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    static func monthGridDays(for date: Date, calendar: Calendar = .current) -> [Date?] {
        let start = monthStart(for: date, calendar: calendar)
        let range = calendar.range(of: .day, in: .month, for: start) ?? 1..<1
        let leadingBlankCount = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        var days = Array<Date?>(repeating: nil, count: leadingBlankCount)
        days.append(contentsOf: range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: start)
        })
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }

    static func monthStarts(
        from lowerBound: Date,
        through upperBound: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let first = monthStart(for: lowerBound, calendar: calendar)
        let last = monthStart(for: upperBound, calendar: calendar)
        var current = first
        var result: [Date] = []

        while current <= last {
            result.append(current)
            guard let next = calendar.date(byAdding: .month, value: 1, to: current) else {
                break
            }
            current = next
        }

        return result
    }

    static func contributionWeeks(
        ending endDate: Date,
        weekCount: Int = 53,
        calendar: Calendar = .current
    ) -> [[Date]] {
        let endWeek = calendar.dateInterval(of: .weekOfYear, for: endDate)?.start
            ?? calendar.startOfDay(for: endDate)
        let firstWeek = calendar.date(byAdding: .weekOfYear, value: -(weekCount - 1), to: endWeek)
            ?? endWeek

        return (0..<weekCount).map { weekOffset in
            let weekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: firstWeek) ?? firstWeek
            return (0..<7).compactMap { dayOffset in
                calendar.date(byAdding: .day, value: dayOffset, to: weekStart)
            }
        }
    }
}

struct ActivityDensityScale {
    private let thresholds: [Int]

    init(counts: [Int]) {
        let activeCounts = counts
            .filter { $0 > 0 }
            .sorted()

        guard !activeCounts.isEmpty else {
            thresholds = []
            return
        }

        thresholds = [
            Self.value(at: 0.25, in: activeCounts),
            Self.value(at: 0.50, in: activeCounts),
            Self.value(at: 0.75, in: activeCounts)
        ]
    }

    func level(for count: Int) -> Int {
        guard count > 0 else {
            return 0
        }
        guard !thresholds.isEmpty else {
            return 0
        }

        if count <= thresholds[0] {
            return 1
        }
        if count <= thresholds[1] {
            return 2
        }
        if count <= thresholds[2] {
            return 3
        }
        return 4
    }

    private static func value(at percentile: Double, in sortedCounts: [Int]) -> Int {
        guard sortedCounts.count > 1 else {
            return sortedCounts[0]
        }
        let clamped = min(max(percentile, 0), 1)
        let rawIndex = Double(sortedCounts.count - 1) * clamped
        let index = Int(rawIndex.rounded(.toNearestOrAwayFromZero))
        return sortedCounts[index]
    }
}
