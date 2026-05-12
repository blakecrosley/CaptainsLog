import SwiftUI
import Kit941

struct JournalWeekStrip: View {
    @Binding var selectedDate: Date
    let workMetrics: WorkMetrics
    let onShowMonth: () -> Void

    @State private var weekDragTranslation: CGFloat = 0
    @State private var isSettling = false

    var body: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
            HStack(alignment: .top, spacing: Kit941.Spacing.md) {
                Button {
                    onShowMonth()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                                .kit941Font(.title, weight: .semibold)
                            Text(selectedDate, format: .dateTime.month(.wide).year())
                                .kit941Font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(workMetrics.commitCount(on: selectedDate))")
                        .kit941Font(.label, weight: .semibold)
                        .monospacedDigit()
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                    Text("commits")
                        .kit941Font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { proxy in
                let pageWidth = max(proxy.size.width, 1)

                weekPage(containing: selectedDate, selectedPageDate: selectedDate)
                    .frame(width: pageWidth)
                    .offset(x: weekDragTranslation)
                    .contentShape(Rectangle())
                    .gesture(weekGesture(pageWidth: pageWidth))
            }
            .frame(height: 102)
            .clipped()
            .onChange(of: selectedDate) { _, _ in
                guard !isSettling else { return }
                weekDragTranslation = 0
            }
        }
        .padding(.horizontal, Kit941.Spacing.md)
        .padding(.vertical, Kit941.Spacing.md)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: Kit941.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Kit941.Radius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        }
    }

    private func weekPage(containing date: Date, selectedPageDate: Date) -> some View {
        HStack(spacing: 8) {
            ForEach(CalendarMath.weekDays(containing: date), id: \.self) { day in
                Button {
                    select(day)
                } label: {
                    CalendarDayChip(
                        date: day,
                        count: workMetrics.commitCount(on: day),
                        isSelected: Calendar.current.isDate(day, inSameDayAs: selectedPageDate),
                        isToday: Calendar.current.isDateInToday(day)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func weekDate(offset: Int) -> Date {
        Calendar.current.date(byAdding: .weekOfYear, value: offset, to: selectedDate) ?? selectedDate
    }

    private func select(_ day: Date) {
        withAnimation(Kit941.Motion.snappy) {
            selectedDate = Calendar.current.startOfDay(for: day)
        }
        Kit941.Haptics.impact(.soft)
    }

    private func weekGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard !isSettling else { return }
                weekDragTranslation = interactiveWeekOffset(for: value.translation.width, pageWidth: pageWidth)
            }
            .onEnded { value in
                guard !isSettling else { return }
                handleWeekDrag(value, pageWidth: pageWidth)
            }
    }

    private func handleWeekDrag(_ value: DragGesture.Value, pageWidth: CGFloat) {
        let threshold = max(pageWidth * 0.20, 70)
        let predicted = value.predictedEndTranslation.width
        let translation = value.translation.width
        let resolved = abs(predicted) > abs(translation) ? predicted : translation

        guard abs(resolved) >= threshold else {
            snapWeekBack()
            return
        }

        let offset = resolved < 0 ? 1 : -1
        settleWeek(by: offset)
    }

    private func settleWeek(by offset: Int) {
        isSettling = true
        let targetDate = weekDate(offset: offset)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedDate = Calendar.current.startOfDay(for: targetDate)
        }

        withAnimation(Kit941.Motion.snappy) {
            weekDragTranslation = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isSettling = false
        }
    }

    private func snapWeekBack() {
        withAnimation(Kit941.Motion.smooth) {
            weekDragTranslation = 0
            isSettling = false
        }
    }

    private func interactiveWeekOffset(for translation: CGFloat, pageWidth: CGFloat) -> CGFloat {
        let limit = min(pageWidth * 0.16, 54)
        return min(max(translation, -limit), limit)
    }
}

private struct CalendarDayChip: View {
    let date: Date
    let count: Int
    let isSelected: Bool
    let isToday: Bool

    var body: some View {
        VStack(spacing: 7) {
            Text(date, format: .dateTime.weekday(.narrow))
                .kit941Font(.caption)
                .foregroundStyle(.secondary)

            Text(date, format: .dateTime.day())
                .kit941Font(.title, weight: .semibold)
                .foregroundStyle(.primary)
                .transaction { transaction in
                    transaction.animation = nil
                }

            ZStack {
                Circle()
                    .stroke(AppSurface.densityColor(count: count).opacity(count > 0 || isToday ? 1 : 0.55), lineWidth: 2)
                    .frame(width: 18, height: 18)

                if count > 0 {
                    Circle()
                        .fill(AppSurface.densityColor(count: count))
                        .frame(width: markerSize, height: markerSize)
                } else if isToday {
                    Circle()
                        .fill(Color.primary.opacity(0.20))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Kit941.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous)
                .stroke(isToday && !isSelected ? Color.primary.opacity(0.18) : Color.clear, lineWidth: 1)
        }
        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(count) commits")
    }

    private var markerSize: CGFloat {
        min(7 + CGFloat(count * 2), 14)
    }
}

struct MonthCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date
    let workMetrics: WorkMetrics
    let lowerBound: Date
    let upperBound: Date

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
                        ForEach(monthStarts, id: \.self) { month in
                            monthSection(month)
                                .id(month)
                        }
                    }
                    .padding(Kit941.Spacing.lg)
                }
                .scrollIndicators(.hidden)
                .navigationTitle("Calendar")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .onAppear {
                    proxy.scrollTo(CalendarMath.monthStart(for: selectedDate), anchor: .center)
                }
            }
        }
    }

    private var monthStarts: [Date] {
        CalendarMath.monthStarts(from: lowerBound, through: upperBound)
    }

    private func monthSection(_ month: Date) -> some View {
        let days = CalendarMath.monthGridDays(for: month)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

        return VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
            Text(month, format: .dateTime.month(.wide).year())
                .kit941Font(.title, weight: .semibold)

            HStack(spacing: 5) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .kit941Font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 9) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        Button {
                            selectedDate = Calendar.current.startOfDay(for: day)
                            dismiss()
                        } label: {
                            MonthDayCell(
                                date: day,
                                count: workMetrics.commitCount(on: day),
                                isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDate),
                                isToday: Calendar.current.isDateInToday(day)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 58)
                    }
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let firstIndex = max(Calendar.current.firstWeekday - 1, 0)
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }
}

private struct MonthDayCell: View {
    let date: Date
    let count: Int
    let isSelected: Bool
    let isToday: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(date, format: .dateTime.day())
                .kit941Font(.label, weight: .semibold)
                .foregroundStyle(.primary)
                .frame(height: 20)

            Circle()
                .fill(AppSurface.densityColor(count: count))
                .frame(width: count > 0 ? 12 : 7, height: count > 0 ? 12 : 7)
                .opacity(count > 0 || isToday ? 1 : 0.45)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(
            RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous)
                .stroke(isToday && !isSelected ? Color.primary.opacity(0.18) : Color.clear, lineWidth: 1)
        }
        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(count) commits")
    }
}

struct ActivityHeatmapView: View {
    @Binding var selectedDate: Date
    let workMetrics: WorkMetrics
    let metric: WorkDisplayMetric

    @State private var selectedYear: Int?

    var body: some View {
        let data = heatmapData
        let densityScale = ActivityDensityScale(counts: data.activityValuesByDay.map(\.value))

        VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
            HStack(alignment: .center, spacing: Kit941.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rangeTitle)
                        .kit941Font(.label, weight: .semibold)
                    Text(subtitle(for: data))
                        .kit941Font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Kit941.Spacing.md)

                Menu {
                    Button("Last 52 weeks") {
                        selectedYear = nil
                    }

                    Divider()

                    ForEach(availableYears, id: \.self) { year in
                        Button("\(year)") {
                            selectedYear = year
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(rangePickerTitle)
                            .kit941Font(.caption, weight: .semibold)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 4) {
                        ForEach(data.weeks, id: \.self) { week in
                            VStack(spacing: 4) {
                                Text(monthMarker(for: week) ?? "")
                                    .kit941Font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16, height: 14, alignment: .leading)

                                ForEach(week, id: \.self) { day in
                                    let dayKey = GitCommitRecord.dayKey(for: day)
                                    let activityValue = data.activityValuesByDay[dayKey] ?? 0
                                    let densityLevel = densityScale.level(for: activityValue)
                                    Button {
                                        selectedDate = Calendar.current.startOfDay(for: day)
                                    } label: {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(AppSurface.densityColor(level: densityLevel))
                                            .frame(width: 13, height: 13)
                                            .overlay {
                                                if Calendar.current.isDate(day, inSameDayAs: selectedDate) {
                                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                        .stroke(Color.primary.opacity(0.72), lineWidth: 1.5)
                                                }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(accessibilityLabel(for: day, data: data))
                                }
                            }
                            .id(week)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    scrollToLatestWeek(proxy, weeks: data.weeks)
                }
                .onChange(of: data.totalValue) { _, _ in
                    scrollToLatestWeek(proxy, weeks: data.weeks)
                }
                .onChange(of: selectedYear) { _, _ in
                    scrollToLatestWeek(proxy, weeks: data.weeks)
                }
            }
        }
    }

    private var heatmapData: ActivityHeatmapData {
        let weeks = heatmapWeeks
        var activityValuesByDay: [String: Int] = [:]
        var knownLineValuesByDay: [String: Int] = [:]
        var commitCountsByDay: [String: Int] = [:]
        var totalValue = 0
        var commitCount = 0
        var statsBackedCommitCount = 0

        for day in weeks.flatMap({ $0 }) {
            let dayKey = GitCommitRecord.dayKey(for: day)
            if !CalendarMath.isContributionDay(day, in: activeInterval) {
                activityValuesByDay[dayKey] = 0
                knownLineValuesByDay[dayKey] = 0
                commitCountsByDay[dayKey] = 0
                continue
            }

            let snapshot = workMetrics.snapshot(on: day)
            activityValuesByDay[dayKey] = metric.heatmapValue(for: snapshot)
            knownLineValuesByDay[dayKey] = snapshot.totalChanges
            commitCountsByDay[dayKey] = snapshot.commitCount
            let value = metric.value(for: snapshot)
            totalValue += value
            commitCount += snapshot.commitCount
            statsBackedCommitCount += snapshot.statsBackedCommitCount
        }

        return ActivityHeatmapData(
            weeks: weeks,
            activityValuesByDay: activityValuesByDay,
            knownLineValuesByDay: knownLineValuesByDay,
            commitCountsByDay: commitCountsByDay,
            totalValue: totalValue,
            commitCount: commitCount,
            statsBackedCommitCount: statsBackedCommitCount
        )
    }

    private var heatmapWeeks: [[Date]] {
        if let selectedYear {
            return CalendarMath.contributionWeeks(inYear: selectedYear)
        }
        return CalendarMath.contributionWeeks(ending: Date(), weekCount: 52)
    }

    private var activeInterval: DateInterval? {
        guard let selectedYear else {
            return nil
        }
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1))
            ?? Date()
        let end = calendar.date(byAdding: .year, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    private var rangeTitle: String {
        if let selectedYear {
            return "\(selectedYear)"
        }
        return "Last 52 weeks"
    }

    private var rangePickerTitle: String {
        selectedYear.map(String.init) ?? "52W"
    }

    private var availableYears: [Int] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let oldestYear = workMetrics.oldestCommitDate.map { calendar.component(.year, from: $0) } ?? currentYear
        guard oldestYear <= currentYear else {
            return [currentYear]
        }
        return Array((oldestYear...currentYear).reversed())
    }

    private func subtitle(for data: ActivityHeatmapData) -> String {
        switch metric {
        case .changes:
            let coverage = data.coverage.formatted(.percent.precision(.fractionLength(0)))
            return "\(data.totalValue.formatted()) known lines. \(coverage) stats coverage"
        case .commits:
            return "\(data.totalValue.formatted()) commits"
        }
    }

    private func monthMarker(for week: [Date]) -> String? {
        guard let firstMonthDay = CalendarMath.contributionMonthStart(
            in: week,
            activeInterval: activeInterval
        ) else {
            return nil
        }
        return firstMonthDay.formatted(.dateTime.month(.narrow))
    }

    private func accessibilityLabel(for day: Date, data: ActivityHeatmapData) -> String {
        let dayKey = GitCommitRecord.dayKey(for: day)
        let commitCount = data.commitCountsByDay[dayKey] ?? 0
        let knownLines = data.knownLineValuesByDay[dayKey] ?? 0
        let date = day.formatted(date: .complete, time: .omitted)

        switch metric {
        case .changes:
            if knownLines > 0 {
                return "\(date), \(knownLines) changed lines"
            }
            if commitCount > 0 {
                return "\(date), \(commitCount) commits, line stats pending"
            }
            return "\(date), no work"
        case .commits:
            return "\(date), \(commitCount) commits"
        }
    }

    private func scrollToLatestWeek(_ proxy: ScrollViewProxy, weeks: [[Date]]) {
        guard let latestWeek = weeks.last else {
            return
        }
        DispatchQueue.main.async {
            proxy.scrollTo(latestWeek, anchor: .trailing)
        }
    }
}

private struct ActivityHeatmapData {
    let weeks: [[Date]]
    let activityValuesByDay: [String: Int]
    let knownLineValuesByDay: [String: Int]
    let commitCountsByDay: [String: Int]
    let totalValue: Int
    let commitCount: Int
    let statsBackedCommitCount: Int

    var coverage: Double {
        guard commitCount > 0 else {
            return 1
        }
        return Double(statsBackedCommitCount) / Double(commitCount)
    }
}
