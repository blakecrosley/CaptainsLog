import SwiftUI
import Kit941

struct JournalWeekStrip: View {
    @Binding var selectedDate: Date
    let workMetrics: WorkMetrics
    let onShowMonth: () -> Void

    @State private var weekDragTranslation: CGFloat = 0
    @State private var isSettling = false

    private var weekSpring: Animation {
        .interactiveSpring(response: 0.34, dampingFraction: 0.78, blendDuration: 0.08)
    }

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
                                .foregroundStyle(AppSurface.secondaryText)
                        }

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppSurface.secondaryText)
                    }
                    .foregroundStyle(AppSurface.primaryText)
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
                        .foregroundStyle(AppSurface.secondaryText)
                }
            }

            GeometryReader { proxy in
                let pageWidth = max(proxy.size.width, 1)

                HStack(spacing: 0) {
                    weekPage(containing: weekDate(offset: -1), selectedPageDate: weekDate(offset: -1))
                        .frame(width: pageWidth)
                    weekPage(containing: selectedDate, selectedPageDate: selectedDate)
                        .frame(width: pageWidth)
                    weekPage(containing: weekDate(offset: 1), selectedPageDate: weekDate(offset: 1))
                        .frame(width: pageWidth)
                }
                    .frame(width: pageWidth * 3, alignment: .leading)
                    .offset(x: -pageWidth + weekDragTranslation)
                    .scaleEffect(weekDragScale(pageWidth: pageWidth))
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
        .appPanel(highlighted: true)
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
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedDate = Calendar.current.startOfDay(for: day)
        }
        Kit941.Haptics.impact(.soft)
    }

    private func weekGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard !isSettling else { return }
                guard hasWeekSwipeIntent(value.translation) else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    weekDragTranslation = interactiveWeekOffset(for: value.translation.width, pageWidth: pageWidth)
                }
            }
            .onEnded { value in
                guard !isSettling else { return }
                handleWeekDrag(value, pageWidth: pageWidth)
            }
    }

    private func handleWeekDrag(_ value: DragGesture.Value, pageWidth: CGFloat) {
        let predicted = value.predictedEndTranslation
        guard hasWeekSwipeIntent(value.translation) || hasWeekSwipeIntent(predicted) else {
            snapWeekBack()
            return
        }

        let offset = predicted.width < 0 ? 1 : -1
        let distancePush = abs(value.translation.width) > pageWidth * 0.24
        let projectedPush = abs(predicted.width) > pageWidth * 0.26
        let velocityPush = abs(predicted.width - value.translation.width) > pageWidth * 0.18
        guard distancePush || projectedPush || velocityPush else {
            snapWeekBack()
            return
        }

        settleWeek(by: offset, pageWidth: pageWidth)
    }

    private func settleWeek(by offset: Int, pageWidth: CGFloat) {
        isSettling = true
        Kit941.Haptics.impact(.soft)

        withAnimation(weekSpring) {
            weekDragTranslation = offset > 0 ? -pageWidth : pageWidth
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            let targetDate = weekDate(offset: offset)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedDate = Calendar.current.startOfDay(for: targetDate)
                weekDragTranslation = 0
                isSettling = false
            }
        }
    }

    private func snapWeekBack() {
        withAnimation(weekSpring) {
            weekDragTranslation = 0
            isSettling = false
        }
    }

    private func weekDragScale(pageWidth: CGFloat) -> CGFloat {
        1 - min(abs(weekDragTranslation) / max(pageWidth * 18, 1), 0.012)
    }

    private func hasWeekSwipeIntent(_ translation: CGSize) -> Bool {
        let horizontal = abs(translation.width)
        let vertical = abs(translation.height)
        return horizontal >= 14 && horizontal > vertical * 1.15
    }

    private func interactiveWeekOffset(for translation: CGFloat, pageWidth: CGFloat) -> CGFloat {
        guard translation != 0 else { return 0 }
        let sign: CGFloat = translation < 0 ? -1 : 1
        let magnitude = abs(translation)
        let pageTravel = min(magnitude, pageWidth)
        let overflow = max(magnitude - pageWidth, 0)
        return sign * (pageTravel + elasticOffset(overflow, limit: 34))
    }

    private func elasticOffset(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        let magnitude = abs(value)
        let sign: CGFloat = value < 0 ? -1 : 1
        return sign * ((limit * magnitude) / (limit + magnitude))
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
                .foregroundStyle(AppSurface.secondaryText)

            Text(date, format: .dateTime.day())
                .kit941Font(.title, weight: .semibold)
                .foregroundStyle(AppSurface.primaryText)
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
                        .fill(AppSurface.accent.opacity(0.22))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Kit941.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous)
                .fill(isSelected ? AppSurface.accent.opacity(0.08) : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous)
                .stroke(isToday && !isSelected ? AppSurface.accent.opacity(0.18) : Color.clear, lineWidth: 1)
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
    let initialVisibleDate: Date

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
                .navigationTitle("Choose Date")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .onAppear {
                    proxy.scrollTo(CalendarMath.monthStart(for: initialVisibleDate), anchor: .center)
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
                        .foregroundStyle(AppSurface.secondaryText)
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
                .foregroundStyle(AppSurface.primaryText)
                .frame(height: 20)

            Circle()
                .fill(AppSurface.densityColor(count: count))
                .frame(width: count > 0 ? 12 : 7, height: count > 0 ? 12 : 7)
                .opacity(count > 0 || isToday ? 1 : 0.45)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(
            RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous)
                .fill(isSelected ? AppSurface.accent.opacity(0.08) : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous)
                .stroke(isToday && !isSelected ? AppSurface.accent.opacity(0.18) : Color.clear, lineWidth: 1)
        }
        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(count) commits")
    }
}

struct ActivityHeatmapView: View {
    @Binding var selectedDate: Date
    let workMetrics: WorkMetrics
    let repositoryCoverage: [ActivityRepositoryCoverage]
    let metric: WorkDisplayMetric
    var showsHeaderTitle = true
    var onShowDetail: (@MainActor @Sendable () -> Void)? = nil
    private let selectedYearBinding: Binding<Int?>?

    @State private var localSelectedYear: Int?

    init(
        selectedDate: Binding<Date>,
        workMetrics: WorkMetrics,
        repositoryCoverage: [ActivityRepositoryCoverage] = [],
        metric: WorkDisplayMetric,
        selectedYear: Binding<Int?>? = nil,
        showsHeaderTitle: Bool = true,
        onShowDetail: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self._selectedDate = selectedDate
        self.workMetrics = workMetrics
        self.repositoryCoverage = repositoryCoverage
        self.metric = metric
        self.showsHeaderTitle = showsHeaderTitle
        self.selectedYearBinding = selectedYear
        self.onShowDetail = onShowDetail
    }

    var body: some View {
        let data = heatmapData
        let densityScale = ActivityDensityScale(counts: data.activityValuesByDay.map(\.value))

        VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
            HStack(alignment: .center, spacing: Kit941.Spacing.md) {
                if showsHeaderTitle {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rangeTitle)
                            .kit941Font(.label, weight: .semibold)
                        Text(subtitle(for: data))
                            .kit941Font(.caption)
                            .foregroundStyle(AppSurface.secondaryText)
                    }
                }

                Spacer(minLength: Kit941.Spacing.md)

                Menu {
                    Button("Last 52 weeks") {
                        setSelectedYear(nil)
                    }

                    Divider()

                    ForEach(availableYears, id: \.self) { year in
                        Button("\(year)") {
                            setSelectedYear(year)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(rangePickerTitle)
                            .kit941Font(.caption, weight: .semibold)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(AppSurface.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(AppSurface.mutedFill(opacity: 1), in: Capsule())
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
                                    .foregroundStyle(AppSurface.secondaryText)
                                    .frame(width: 16, height: 14, alignment: .leading)

                                ForEach(week, id: \.self) { day in
                                    let dayKey = GitCommitRecord.dayKey(for: day)
                                    let activityValue = data.activityValuesByDay[dayKey] ?? 0
                                    let densityLevel = densityScale.level(for: activityValue)
                                    let trustState = data.trustStatesByDay[dayKey] ?? .verified
                                    Button {
                                        selectedDate = Calendar.current.startOfDay(for: day)
                                    } label: {
                                        ActivityHeatmapCell(
                                            densityLevel: densityLevel,
                                            trustState: trustState,
                                            isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDate)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(trustState == .future || trustState == .outsideRange)
                                    .accessibilityLabel(accessibilityLabel(for: day, data: data))
                                }
                            }
                            .id(week)
                        }
                    }
                    .padding(.horizontal, Kit941.Spacing.md)
                    .padding(.vertical, 2)
                }
                .frame(height: Self.heatmapScrollHeight, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous))
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

            if data.unknownDayCount > 0 {
                HStack(spacing: 7) {
                    ActivityHeatmapCell(densityLevel: 0, trustState: .unknown, isSelected: false)
                        .frame(width: 13, height: 13)
                    Text("Diagonal days are still indexing")
                        .kit941Font(.caption)
                        .foregroundStyle(AppSurface.secondaryText)
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
        .padding(Kit941.Spacing.md)
        .appPanel(highlighted: true)
        .contentShape(Rectangle())
        .onTapGesture {
            onShowDetail?()
        }
        .accessibilityAddTraits(onShowDetail == nil ? [] : .isButton)
    }

    private var heatmapData: ActivityHeatmapData {
        let weeks = heatmapWeeks
        var activityValuesByDay: [String: Int] = [:]
        var knownLineValuesByDay: [String: Int] = [:]
        var commitCountsByDay: [String: Int] = [:]
        var trustStatesByDay: [String: ActivityDayTrustState] = [:]
        var totalValue = 0
        var commitCount = 0
        var statsBackedCommitCount = 0
        var unknownDayCount = 0
        let selectedCoverage = repositoryCoverage.filter { $0.isSelected && $0.isGitHubBacked }
        let now = Date()
        let calendar = Calendar.current

        for day in weeks.flatMap({ $0 }) {
            let dayKey = GitCommitRecord.dayKey(for: day)
            if !CalendarMath.isContributionDay(day, in: activeInterval) {
                activityValuesByDay[dayKey] = 0
                knownLineValuesByDay[dayKey] = 0
                commitCountsByDay[dayKey] = 0
                trustStatesByDay[dayKey] = .outsideRange
                continue
            }

            let snapshot = workMetrics.snapshot(on: day)
            let trustState = ActivityDataTrust.state(
                for: day,
                selectedRepositoryCoverage: selectedCoverage,
                now: now,
                calendar: calendar
            )
            activityValuesByDay[dayKey] = metric.heatmapValue(for: snapshot)
            knownLineValuesByDay[dayKey] = snapshot.totalChanges
            commitCountsByDay[dayKey] = snapshot.commitCount
            trustStatesByDay[dayKey] = trustState
            if trustState == .unknown {
                unknownDayCount += 1
            }
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
            trustStatesByDay: trustStatesByDay,
            totalValue: totalValue,
            commitCount: commitCount,
            statsBackedCommitCount: statsBackedCommitCount,
            unknownDayCount: unknownDayCount
        )
    }

    private static var heatmapScrollHeight: CGFloat {
        14 + (7 * 13) + (6 * 4) + 4
    }

    private var heatmapWeeks: [[Date]] {
        if let selectedYear {
            return CalendarMath.contributionWeeks(inYear: selectedYear)
        }
        return CalendarMath.contributionWeeks(ending: Date(), weekCount: 52)
    }

    private var selectedYear: Int? {
        selectedYearBinding?.wrappedValue ?? localSelectedYear
    }

    private func setSelectedYear(_ year: Int?) {
        if let selectedYearBinding {
            selectedYearBinding.wrappedValue = year
        } else {
            localSelectedYear = year
        }
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
        "Work Map"
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
        let indexingSuffix = data.unknownDayCount > 0
            ? ". \(data.unknownDayCount.formatted()) days not indexed"
            : ""
        switch metric {
        case .changes:
            let coverage = data.coverage.formatted(.percent.precision(.fractionLength(0)))
            return "\(rangeLabel). \(data.totalValue.formatted()) known lines. \(coverage) stats coverage\(indexingSuffix)"
        case .commits:
            return "\(rangeLabel). \(data.totalValue.formatted()) commits\(indexingSuffix)"
        }
    }

    private var rangeLabel: String {
        selectedYear.map(String.init) ?? "Last 52 weeks"
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
        let trustState = data.trustStatesByDay[dayKey] ?? .verified
        let date = day.formatted(date: .complete, time: .omitted)
        if trustState == .outsideRange {
            return "\(date), outside this map range"
        }
        if trustState == .future {
            return "\(date), future"
        }
        let trustSuffix = trustState == .unknown ? ", history still indexing" : ""

        switch metric {
        case .changes:
            if knownLines > 0 {
                return "\(date), \(knownLines) changed lines\(trustSuffix)"
            }
            if commitCount > 0 {
                return "\(date), \(commitCount) commits, line stats pending\(trustSuffix)"
            }
            return trustState == .unknown ? "\(date), not fully indexed" : "\(date), no work"
        case .commits:
            return "\(date), \(commitCount) commits\(trustSuffix)"
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

private struct ActivityHeatmapCell: View {
    let densityLevel: Int
    let trustState: ActivityDayTrustState
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fillColor)
            .frame(width: 13, height: 13)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(AppSurface.selectedStroke, lineWidth: 1.5)
                }
            }
            .opacity(trustState == .outsideRange ? 0.28 : 1)
    }

    private var fillColor: Color {
        switch trustState {
        case .verified:
            return AppSurface.densityColor(level: densityLevel)
        case .unknown:
            return densityLevel > 0
                ? AppSurface.densityColor(level: densityLevel).opacity(0.78)
                : AppSurface.track.opacity(0.72)
        case .future, .outsideRange:
            return AppSurface.track.opacity(0.45)
        }
    }
}

private struct ActivityHeatmapData {
    let weeks: [[Date]]
    let activityValuesByDay: [String: Int]
    let knownLineValuesByDay: [String: Int]
    let commitCountsByDay: [String: Int]
    let trustStatesByDay: [String: ActivityDayTrustState]
    let totalValue: Int
    let commitCount: Int
    let statsBackedCommitCount: Int
    let unknownDayCount: Int

    var coverage: Double {
        guard commitCount > 0 else {
            return 1
        }
        return Double(statsBackedCommitCount) / Double(commitCount)
    }
}
