import SwiftUI

struct OBSResponse: Codable {
    let success: Bool
    let data: OBSData
}

struct OBSData: Codable {
    let lessonSchedule: LessonSchedule
}

struct LessonSchedule: Codable {
    let periodList: [Period]
    let periodId: Int?
    let data: ScheduleData
}

struct Period: Codable {
    let id: Int
    let description: String
}

struct ScheduleData: Codable {
    let xInfo: [[String]]
    let yInfo: [[String]]
    let data: [Lesson]

    enum CodingKeys: String, CodingKey { case xInfo, yInfo, data }

    init(xInfo: [[String]], yInfo: [[String]], data: [Lesson]) {
        self.xInfo = xInfo
        self.yInfo = yInfo
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        xInfo = try container.decodeIfPresent([[String]].self, forKey: .xInfo) ?? []
        yInfo = try container.decodeIfPresent([[String]].self, forKey: .yInfo) ?? []
        data = try container.decodeIfPresent([Lesson].self, forKey: .data) ?? []
    }
}

struct Lesson: Codable, Identifiable {
    let x: Int
    let y: Int
    let obsID: String?
    let text: [String]
    let data: LessonInfo

    enum CodingKeys: String, CodingKey { case x, y, obsID = "id", text, data }
    var id: String { obsID ?? "\(x)-\(y)" }
    var subject: String { text.count > 1 ? text[1] : "" }
    var teacher: String { text.first ?? "" }
    var title: String { data.headerTitle ?? "" }
}

struct LessonInfo: Codable {
    let headerTitle: String?
    let headerContent: String?
}

struct ScheduleDay: Identifiable {
    let id: Int
    let title: String
    let weekday: Int?
    let hasLessons: Bool
}

enum ScheduleDaySelection {
    static func initialStartIndex(
        days: [ScheduleDay],
        schedule: LessonSchedule,
        visibleDayCount: Int,
        date: Date,
        calendar: Calendar
    ) -> Int {
        guard days.count > 1 else { return 0 }

        let today = calendar.component(.weekday, from: date)
        let focusIndex: Int
        if let todayIndex = days.firstIndex(where: { $0.weekday == today }) {
            if isWeekend(today), !days[todayIndex].hasLessons {
                focusIndex = nextWeekdayIndex(in: days, after: todayIndex)
            } else if schoolDayHasEnded(day: days[todayIndex], schedule: schedule, date: date, calendar: calendar) {
                focusIndex = (todayIndex + 1) % days.count
            } else {
                focusIndex = todayIndex
            }
        } else if isWeekend(today), let mondayIndex = days.firstIndex(where: { $0.weekday == 2 }) {
            focusIndex = mondayIndex
        } else {
            focusIndex = days.firstIndex { day in
                guard let weekday = day.weekday else { return false }
                return weekday >= today && (!isWeekend(weekday) || day.hasLessons)
            } ?? 0
        }

        let precedingDayCount = visibleDayCount >= 3 ? 1 : 0
        return (focusIndex - precedingDayCount + days.count) % days.count
    }

    static func pairStart(containing index: Int, count: Int) -> Int {
        min(max(index, 0), max(count - 1, 0))
    }

    private static func nextWeekdayIndex(in days: [ScheduleDay], after index: Int) -> Int {
        for offset in 1...days.count {
            let candidate = (index + offset) % days.count
            if let weekday = days[candidate].weekday, !isWeekend(weekday) {
                return candidate
            }
            if days[candidate].hasLessons {
                return candidate
            }
        }
        return 0
    }

    private static func isWeekend(_ weekday: Int) -> Bool {
        weekday == 1 || weekday == 7
    }

    private static func schoolDayHasEnded(
        day: ScheduleDay,
        schedule: LessonSchedule,
        date: Date,
        calendar: Calendar
    ) -> Bool {
        guard let lastPeriod = schedule.data.data
            .filter({ $0.y == day.id })
            .map(\.x)
            .max(),
              schedule.data.xInfo.indices.contains(lastPeriod - 1),
              let endTime = lastClockTime(in: schedule.data.xInfo[lastPeriod - 1]) else {
            return false
        }

        let currentHour = calendar.component(.hour, from: date)
        let currentMinute = calendar.component(.minute, from: date)
        return currentHour * 60 + currentMinute >= endTime.hour * 60 + endTime.minute
    }

    private static func lastClockTime(in values: [String]) -> (hour: Int, minute: Int)? {
        let expression = try? NSRegularExpression(pattern: #"(?:[01]?\d|2[0-3])[.:][0-5]\d"#)
        let text = values.joined(separator: " ")
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression?.matches(in: text, range: range).last,
              let matchRange = Range(match.range, in: text) else { return nil }

        let components = text[matchRange].split(whereSeparator: { $0 == ":" || $0 == "." })
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else { return nil }
        return (hour, minute)
    }
}

struct ScheduleView: View {
    let schedule: LessonSchedule
    let refresh: () -> Void
    @State private var compactStartIndex: Int?
    @State private var userSelectedDays = false

    private var days: [ScheduleDay] {
        ScheduleLayout.days(for: schedule)
    }

    private var compactDays: [ScheduleDay] {
        ScheduleLayout.compactDays(from: days)
    }

    private func preferredCompactStartIndex(visibleDayCount: Int) -> Int {
        compactStartIndex ?? ScheduleDaySelection.initialStartIndex(
            days: compactDays,
            schedule: schedule,
            visibleDayCount: visibleDayCount,
            date: Date(),
            calendar: .current
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let visibleDayCount = ScheduleLayout.visibleDayCount(
                availableWidth: proxy.size.width,
                totalDayCount: days.count
            )
            let showsFullWeek = visibleDayCount >= days.count

            Group {
                if showsFullWeek {
                    FullWeekScheduleView(schedule: schedule, days: days)
                        .onAppear {
                            compactStartIndex = nil
                            userSelectedDays = false
                        }
                } else {
                    CompactScheduleView(
                        schedule: schedule,
                        days: compactDays,
                        startIndex: preferredCompactStartIndex(visibleDayCount: visibleDayCount),
                        visibleDayCount: visibleDayCount,
                        movePair: moveCompactPair
                    )
                    .onAppear {
                        initializeCompactSelectionIfNeeded(visibleDayCount: visibleDayCount)
                    }
                }
            }
            .onChange(of: visibleDayCount) { _, newCount in
                guard !showsFullWeek, !userSelectedDays else { return }
                compactStartIndex = automaticStartIndex(visibleDayCount: newCount)
            }
            .onChange(of: compactDays.map(\.id)) { _, _ in
                compactStartIndex = nil
                userSelectedDays = false
                if !showsFullWeek {
                    initializeCompactSelectionIfNeeded(visibleDayCount: visibleDayCount)
                }
            }
            .task(id: visibleDayCount) {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(30))
                    } catch {
                        return
                    }
                    guard !showsFullWeek, !userSelectedDays else { continue }
                    compactStartIndex = automaticStartIndex(visibleDayCount: visibleDayCount)
                }
            }
        }
        .frame(minWidth: ScheduleLayout.minimumContentWidth)
        .navigationTitle("Ders Programı")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { refresh() } label: { Label("Yenile", systemImage: "arrow.clockwise") }
            }
        }
    }

    private func automaticStartIndex(visibleDayCount: Int) -> Int {
        ScheduleDaySelection.initialStartIndex(
            days: compactDays,
            schedule: schedule,
            visibleDayCount: visibleDayCount,
            date: Date(),
            calendar: .current
        )
    }

    private func initializeCompactSelectionIfNeeded(visibleDayCount: Int) {
        guard compactStartIndex == nil else { return }
        compactStartIndex = automaticStartIndex(visibleDayCount: visibleDayCount)
    }

    private func moveCompactPair(by offset: Int) {
        guard !compactDays.isEmpty else { return }
        let currentIndex = compactStartIndex ?? 0
        compactStartIndex = (currentIndex + offset + compactDays.count) % compactDays.count
        userSelectedDays = true
    }
}

private enum ScheduleLayout {
    static let timeColumnWidth: CGFloat = 80
    static let dayColumnWidth: CGFloat = 140
    static let columnSpacing: CGFloat = 8
    static let contentPadding: CGFloat = 28

    static var minimumContentWidth: CGFloat {
        width(forDayCount: 1)
    }

    static func visibleDayCount(availableWidth: CGFloat, totalDayCount: Int) -> Int {
        guard totalDayCount > 0 else { return 0 }
        let availableDayWidth = availableWidth - contentPadding * 2 - timeColumnWidth
        let count = Int(floor(availableDayWidth / (dayColumnWidth + columnSpacing)))
        return min(max(count, 1), totalDayCount)
    }

    private static func width(forDayCount dayCount: Int) -> CGFloat {
        return timeColumnWidth
            + CGFloat(dayCount) * dayColumnWidth
            + CGFloat(dayCount) * columnSpacing
            + contentPadding * 2
    }

    static func days(for schedule: LessonSchedule) -> [ScheduleDay] {
        let maximumLessonDay = schedule.data.data.map(\.y).max() ?? 0
        let dayCount = max(schedule.data.yInfo.count, maximumLessonDay)
        let fallbackTitles = ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]

        guard dayCount > 0 else { return [] }
        return (1...dayCount).map { dayNumber in
            let apiTitle = schedule.data.yInfo.indices.contains(dayNumber - 1)
                ? schedule.data.yInfo[dayNumber - 1].first(where: { !$0.isEmpty })
                : nil
            let fallbackTitle = fallbackTitles.indices.contains(dayNumber - 1)
                ? fallbackTitles[dayNumber - 1]
                : "Gün \(dayNumber)"
            let title = apiTitle ?? fallbackTitle
            return ScheduleDay(
                id: dayNumber,
                title: title,
                weekday: weekday(for: title) ?? positionalWeekday(for: dayNumber),
                hasLessons: schedule.data.data.contains { $0.y == dayNumber }
            )
        }
    }

    static func compactDays(from days: [ScheduleDay]) -> [ScheduleDay] {
        let schoolDays = days.filter { day in
            guard let weekday = day.weekday else { return true }
            return weekday != 1 && weekday != 7 || day.hasLessons
        }
        return schoolDays.isEmpty ? days : schoolDays
    }

    private static func positionalWeekday(for dayNumber: Int) -> Int? {
        guard (1...7).contains(dayNumber) else { return nil }
        return dayNumber == 7 ? 1 : dayNumber + 1
    }

    private static func weekday(for title: String) -> Int? {
        let normalized = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
        if normalized.contains("pazartesi") || normalized.contains("monday") { return 2 }
        if normalized.contains("sali") || normalized.contains("tuesday") { return 3 }
        if normalized.contains("carsamba") || normalized.contains("wednesday") { return 4 }
        if normalized.contains("persembe") || normalized.contains("thursday") { return 5 }
        if normalized.contains("cumartesi") || normalized.contains("saturday") { return 7 }
        if normalized.contains("cuma") || normalized.contains("friday") { return 6 }
        if normalized.contains("pazar") || normalized.contains("sunday") { return 1 }
        return nil
    }
}

private struct FullWeekScheduleView: View {
    let schedule: LessonSchedule
    let days: [ScheduleDay]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 20) {
                ScheduleHeader(periodDescription: schedule.periodList.first?.description)
                ScheduleGrid(schedule: schedule, days: days, dayColumnWidth: ScheduleLayout.dayColumnWidth)
            }
            .padding(ScheduleLayout.contentPadding)
        }
    }
}

private struct CompactScheduleView: View {
    let schedule: LessonSchedule
    let days: [ScheduleDay]
    let startIndex: Int
    let visibleDayCount: Int
    let movePair: (Int) -> Void

    private var visibleDays: [ScheduleDay] {
        guard !days.isEmpty else { return [] }
        let safeStart = min(max(startIndex, 0), days.count - 1)
        return (0..<min(visibleDayCount, days.count)).map { offset in
            days[(safeStart + offset) % days.count]
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                ScheduleHeader(periodDescription: schedule.periodList.first?.description)
                CompactDayNavigation(
                    days: visibleDays,
                    canMovePrevious: days.count > visibleDayCount,
                    canMoveNext: days.count > visibleDayCount,
                    movePair: movePair
                )
                ScheduleGrid(schedule: schedule, days: visibleDays, dayColumnWidth: nil)
            }
            .padding(ScheduleLayout.contentPadding)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                    movePair(value.translation.width < 0 ? 1 : -1)
                }
        )
    }
}

private struct ScheduleHeader: View {
    let periodDescription: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ders Programı").font(.largeTitle).bold()
            if let periodDescription {
                Text(periodDescription).foregroundStyle(.secondary)
            }
        }
    }
}

private struct CompactDayNavigation: View {
    let days: [ScheduleDay]
    let canMovePrevious: Bool
    let canMoveNext: Bool
    let movePair: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button { movePair(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!canMovePrevious)
            .accessibilityLabel("Önceki günler")

            HStack(spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    if index > 0 {
                        Divider().frame(height: 18)
                    }
                    Text(day.title)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)

            Button { movePair(1) } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!canMoveNext)
            .accessibilityLabel("Sonraki günler")
        }
        .buttonStyle(.borderless)
    }
}

private struct ScheduleGrid: View {
    let schedule: LessonSchedule
    let days: [ScheduleDay]
    let dayColumnWidth: CGFloat?

    private var lessonNumbers: [Int] {
        let maximumLessonPeriod = schedule.data.data.map(\.x).max() ?? 0
        let periodCount = max(schedule.data.xInfo.count, maximumLessonPeriod)
        return periodCount > 0 ? Array(1...periodCount) : []
    }

    var body: some View {
        if days.isEmpty {
            ContentUnavailableView("Ders programı bulunamadı", systemImage: "calendar.badge.exclamationmark")
                .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            Grid(horizontalSpacing: ScheduleLayout.columnSpacing, verticalSpacing: 8) {
                GridRow {
                    Text("Saat")
                        .fontWeight(.semibold)
                        .frame(width: ScheduleLayout.timeColumnWidth)
                    ForEach(days) { day in
                        Text(day.title)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .frame(
                                minWidth: dayColumnWidth,
                                idealWidth: dayColumnWidth,
                                maxWidth: dayColumnWidth ?? .infinity
                            )
                    }
                }
                ForEach(lessonNumbers, id: \.self) { lessonNumber in
                    GridRow {
                        Text(timeText(for: lessonNumber))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(width: ScheduleLayout.timeColumnWidth, height: 80)
                        ForEach(days) { day in
                            LessonCell(
                                lesson: lesson(x: lessonNumber, y: day.id),
                                width: dayColumnWidth
                            )
                        }
                    }
                }
            }
        }
    }

    private func lesson(x: Int, y: Int) -> Lesson? {
        schedule.data.data.first { $0.x == x && $0.y == y }
    }

    private func timeText(for x: Int) -> String {
        let index = x - 1
        guard schedule.data.xInfo.indices.contains(index) else { return "" }
        return schedule.data.xInfo[index].first ?? ""
    }
}

private struct LessonCell: View {
    let lesson: Lesson?
    let width: CGFloat?

    var body: some View {
        Group {
            if let lesson {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.subject).font(.headline).lineLimit(2)
                    Text(lesson.teacher).font(.caption).foregroundStyle(.secondary)
                    if !lesson.title.isEmpty {
                        Text(lesson.title).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Color.clear
            }
        }
        .frame(
            minWidth: width,
            idealWidth: width,
            maxWidth: width ?? .infinity,
            minHeight: 80,
            idealHeight: 80,
            maxHeight: 80
        )
    }
}
