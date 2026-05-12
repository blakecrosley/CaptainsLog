import SwiftUI
import Kit941

struct JournalWeekStrip: View {
    @Binding var selectedDate: Date
    let metrics: ActivityMetrics
    let onShowMonth: () -> Void

    @State private var weekDragTranslation: CGFloat = 0
    @State private var isSettling = false

    var body: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Button {
                    onShowMonth()
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedDate, format: .dateTime.month(.wide).year())
                            .kit941Font(.title, weight: .semibold)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Text("\(metrics.count(on: selectedDate)) commits")
                    .kit941Font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let pageWidth = max(proxy.size.width, 1)

                HStack(spacing: 0) {
                    weekPage(containing: weekDate(offset: -1), selectedPageDate: weekSelectedDate(offset: -1))
                        .frame(width: pageWidth)
                    weekPage(containing: selectedDate, selectedPageDate: selectedDate)
                        .frame(width: pageWidth)
                    weekPage(containing: weekDate(offset: 1), selectedPageDate: weekSelectedDate(offset: 1))
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
        }
        .padding(Kit941.Spacing.md)
        .background(.background, in: RoundedRectangle(cornerRadius: Kit941.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Kit941.Radius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
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
                        count: metrics.count(on: day),
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

    private func weekSelectedDate(offset: Int) -> Date {
        weekDate(offset: offset)
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
        settleWeek(by: offset, pageWidth: pageWidth)
    }

    private func settleWeek(by offset: Int, pageWidth: CGFloat) {
        isSettling = true
        let targetOffset = CGFloat(-offset) * pageWidth
        withAnimation(Kit941.Motion.snappy) {
            weekDragTranslation = targetOffset
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            selectedDate = weekDate(offset: offset)
            weekDragTranslation = 0
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
        let limit = pageWidth * 0.92
        return min(max(translation, -limit), limit)
    }

    private func weekDragScale(pageWidth: CGFloat) -> CGFloat {
        let progress = min(abs(weekDragTranslation) / max(pageWidth, 1), 1)
        return 1 - (progress * 0.018)
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
    let metrics: ActivityMetrics
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
                                count: metrics.count(on: day),
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
    let metrics: ActivityMetrics

    var body: some View {
        let densityScale = ActivityDensityScale(counts: weeks.flatMap { week in
            week.map { metrics.count(on: $0) }
        })

        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Calendar")
                            .kit941Font(.title, weight: .semibold)
                        Text("Last 53 weeks - commit activity")
                            .kit941Font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: Kit941.Spacing.md)

                    Text("\(yearCommitCount) commits")
                        .kit941Font(.label)
                        .foregroundStyle(.secondary)
                }

                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 4) {
                            ForEach(weeks, id: \.self) { week in
                                VStack(spacing: 4) {
                                    ForEach(week, id: \.self) { day in
                                        let count = metrics.count(on: day)
                                        let densityLevel = densityScale.level(for: count)
                                        Button {
                                            selectedDate = Calendar.current.startOfDay(for: day)
                                        } label: {
                                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                .fill(AppSurface.densityColor(level: densityLevel))
                                                .frame(width: 12, height: 12)
                                                .overlay {
                                                    if Calendar.current.isDate(day, inSameDayAs: selectedDate) {
                                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                            .stroke(Color.primary.opacity(0.65), lineWidth: 1.5)
                                                    }
                                                }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(count) commits")
                                    }
                                }
                                .id(week)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear {
                        scrollToLatestWeek(proxy)
                    }
                    .onChange(of: yearCommitCount) { _, _ in
                        scrollToLatestWeek(proxy)
                    }
                }

                HStack(spacing: 5) {
                    Text("Less")
                        .kit941Font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(0..<5) { level in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(AppSurface.densityColor(level: level))
                            .frame(width: 12, height: 12)
                    }
                    Text("More")
                        .kit941Font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var weeks: [[Date]] {
        CalendarMath.contributionWeeks(ending: Date())
    }

    private var yearCommitCount: Int {
        weeks.flatMap { $0 }.reduce(0) { partial, date in
            partial + metrics.count(on: date)
        }
    }

    private func scrollToLatestWeek(_ proxy: ScrollViewProxy) {
        guard let latestWeek = weeks.last else {
            return
        }
        DispatchQueue.main.async {
            proxy.scrollTo(latestWeek, anchor: .trailing)
        }
    }
}
