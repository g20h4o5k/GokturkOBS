import SwiftUI
import Foundation

struct HomeDashboardView: View {
    @ObservedObject var model: AppModel
    @Binding var selection: AppSection?

    var body: some View {
        GeometryReader { proxy in
            let usesCompactCards = shouldUseCompactCards(availableHeight: proxy.size.height)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                HomeDashboardHeader(
                    date: Date(),
                    studentName: model.studentProfile?.name,
                    classID: model.studentProfile?.classId,
                    studentNumber: model.studentProfile?.stuNo
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        FoodSummaryCard(
                            state: model.foodListState,
                            schedule: model.schedule,
                            isCompact: usesCompactCards
                        ) { dayID in
                            model.foodListSelectedDayID = dayID
                            selection = .foodList
                        }
                        HomeworkSummaryCard(
                            homework: model.homework,
                            isLoading: model.isLoadingHomework,
                            errorMessage: model.homeworkError,
                            isCompact: usesCompactCards
                        ) {
                            selection = .homework
                        }
                    }

                    VStack(spacing: 14) {
                        FoodSummaryCard(
                            state: model.foodListState,
                            schedule: model.schedule,
                            isCompact: usesCompactCards
                        ) { dayID in
                            model.foodListSelectedDayID = dayID
                            selection = .foodList
                        }
                        HomeworkSummaryCard(
                            homework: model.homework,
                            isLoading: model.isLoadingHomework,
                            errorMessage: model.homeworkError,
                            isCompact: usesCompactCards
                        ) {
                            selection = .homework
                        }
                    }
                }

                TodayScheduleSection(
                    schedule: model.schedule,
                    isLoading: model.isLoadingSchedule,
                    errorMessage: model.scheduleError,
                    isCompact: usesCompactCards
                ) {
                    selection = .schedule
                }

                LatestExamSection(
                    dashboard: model.examDashboard,
                    isLoading: model.isLoadingExams,
                    errorMessage: model.examsError
                ) {
                    selection = .practiceExams
                }

                QuickAccessSection { selection = $0 }
                }
                .padding(28)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .groupBoxStyle(DashboardGroupBoxStyle())
        .navigationTitle("Ana Sayfa")
        .task {
            await model.refreshHome()
        }
        .refreshable {
            await model.refreshHome(forceReload: true)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.refreshHome(forceReload: true) }
                } label: {
                    Label("Ana Sayfayı Yenile", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private func shouldUseCompactCards(availableHeight: CGFloat) -> Bool {
        let lessonCount = model.schedule
            .flatMap { ScheduleDashboardResolver.upcomingDay(in: $0)?.lessons.count }
            ?? 0
        let estimatedScheduleHeight = 76 + CGFloat(lessonCount) * 54
        let availableScheduleHeight = max(220, availableHeight * 0.44)
        return estimatedScheduleHeight > availableScheduleHeight
    }
}

private struct HomeDashboardHeader: View {
    let date: Date
    let studentName: String?
    let classID: String?
    let studentNumber: String?
    @State private var subtitle = HomeDashboardSubtitle.weightedRandom()

    private var givenNames: String? {
        guard let studentName else { return nil }
        let components = studentName.split(whereSeparator: \.isWhitespace)
        let names = components.count > 1 ? components.dropLast() : components[...]
        guard !names.isEmpty else { return nil }
        return names
            .map { String($0).capitalized(with: Locale(identifier: "tr_TR")) }
            .joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let givenNames, !givenNames.isEmpty {
                Text("Merhaba \(givenNames)")
                    .font(.largeTitle.bold())
            } else {
                Text("Merhaba")
                    .font(.largeTitle.bold())
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(subtitle.text)
                    Spacer(minLength: 12)
                    StudentIdentityLabel(classID: classID, studentNumber: studentNumber)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(subtitle.text)
                    StudentIdentityLabel(classID: classID, studentNumber: studentNumber)
                }
            }
            .font(.title3)
            .foregroundStyle(.secondary)
            Text(date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .environment(\.locale, Locale(identifier: "tr_TR"))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StudentIdentityLabel: View {
    let classID: String?
    let studentNumber: String?

    var body: some View {
        if let classID, !classID.isEmpty,
           let studentNumber, !studentNumber.isEmpty {
            Text("\(classID) / \(studentNumber)")
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Sınıf \(classID), öğrenci numarası \(studentNumber)")
        }
    }
}

private enum HomeDashboardSubtitle {
    case today
    case overview
    case ready
    case rare

    var text: LocalizedStringResource {
        switch self {
        case .today:
            "Bugün okulda neler oluyor?"
        case .overview:
            "okul yani ne bekleyebilirsin"
        case .ready:
            "wuhuuuuuuu"
        case .rare:
            "hessan = heyvan oğlu heyvan"
        }
    }

    static func weightedRandom() -> Self {
        switch Int.random(in: 0..<100) {
        case 0..<60: .today
        case 60..<90: .overview
        case 90..<99: .ready
        default: .rare
        }
    }
}

private struct FoodSummaryCard: View {
    let state: FoodListLoadState
    let schedule: LessonSchedule?
    let isCompact: Bool
    let action: (FoodMenuDay.ID?) -> Void

    private var displayedDayID: FoodMenuDay.ID? {
        displayedMeal?.day.id
    }

    private var displayedMeal: FoodDashboardResolver.Meal? {
        guard case .loaded(_, let days) = state else { return nil }
        let schoolDayEnded = schedule.map {
            ScheduleDashboardResolver.hasSchoolDayEnded(in: $0)
        } ?? false
        return FoodDashboardResolver.currentOrNextMeal(
            in: days,
            beginWithNextDay: schoolDayEnded
        )
    }

    private var mealTitle: String {
        switch displayedMeal?.dayOffset {
        case 1: "Yarının Ana Yemeği"
        case let offset? where offset >= 2: "Sonraki Günün Ana Yemeği"
        default: "Bugünün Ana Yemeği"
        }
    }

    var body: some View {
        Button {
            action(displayedDayID)
        } label: {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label(mealTitle, systemImage: "fork.knife")
                        .font(.headline)

                    HStack(alignment: .center, spacing: 12) {
                        if let displayedMeal {
                            FoodPhotoView(
                                mealName: displayedMeal.mainDish,
                                linksToSource: false
                            )
                            .accessibilityLabel("\(displayedMeal.mainDish) görseli")
                        }

                        FoodSummaryContent(state: state, schedule: schedule)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !isCompact {
                        Spacer(minLength: 0)
                        Label("Yemek Listesine Git", systemImage: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: isCompact ? 88 : 132,
                    alignment: .topLeading
                )
            }
            .groupBoxStyle(DashboardGroupBoxStyle(isCompact: isCompact))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHint("Yemek Listesi bölümünü açar")
    }
}

private struct FoodSummaryContent: View {
    let state: FoodListLoadState
    let schedule: LessonSchedule?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch state {
            case .idle, .loading:
                ProgressView("Yemek listesi yükleniyor…")
                    .controlSize(.small)
            case .error(let message):
                Label("Yemek listesi alınamadı", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            case .empty:
                Text("Bugün için yemek listesi bulunamadı.")
                    .foregroundStyle(.secondary)
            case .loaded(_, let days):
                let schoolDayEnded = schedule.map {
                    ScheduleDashboardResolver.hasSchoolDayEnded(in: $0)
                } ?? false
                if let meal = FoodDashboardResolver.currentOrNextMeal(
                    in: days,
                    beginWithNextDay: schoolDayEnded
                ) {
                    Text(meal.mainDish)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(meal.date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .environment(\.locale, Locale(identifier: "tr_TR"))
                } else {
                    Text("Yaklaşan bir yemek listesi bulunamadı.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private enum FoodDashboardResolver {
    struct Meal {
        let day: FoodMenuDay
        let mainDish: String
        let date: Date
        let dayOffset: Int

        var isToday: Bool { dayOffset == 0 }
    }

    static func currentOrNextMeal(
        in days: [FoodMenuDay],
        date: Date = Date(),
        calendar: Calendar = .current,
        beginWithNextDay: Bool = false
    ) -> Meal? {
        let firstOffset = beginWithNextDay ? 1 : 0
        for dayOffset in firstOffset...(firstOffset + 7) {
            guard let candidateDate = calendar.date(byAdding: .day, value: dayOffset, to: date),
                  let menuDay = today(in: days, date: candidateDate, calendar: calendar),
                  let mainDish = mainDish(in: menuDay) else {
                continue
            }
            return Meal(day: menuDay, mainDish: mainDish, date: candidateDate, dayOffset: dayOffset)
        }
        return nil
    }

    static func today(
        in days: [FoodMenuDay],
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> FoodMenuDay? {
        let weekday = calendar.component(.weekday, from: date)
        guard (2...6).contains(weekday) else { return nil }
        let names = ["", "pazar", "pazartesi", "salı", "çarşamba", "perşembe", "cuma", "cumartesi"]
        let weekdayName = names[weekday]
        let matches = days.filter {
            normalize($0.heading).contains(normalize(weekdayName))
        }
        guard matches.count > 1 else { return matches.first }

        let day = calendar.component(.day, from: date)
        let pattern = #"(?<!\d)"# + String(day) + #"(?!\d)"#
        return matches.first {
            $0.heading.range(of: pattern, options: .regularExpression) != nil
        }
    }

    static func mainDish(in day: FoodMenuDay) -> String? {
        guard day.items.count > 1 else { return nil }
        let first = normalize(day.items[0])
        guard first.contains("corba") || first.contains("soup") else { return nil }
        return day.items[1]
    }

    private static func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "tr_TR")
        )
    }
}

private struct HomeworkSummaryCard: View {
    let homework: [Homework]
    let isLoading: Bool
    let errorMessage: String?
    let isCompact: Bool
    let action: () -> Void

    private var activeCount: Int {
        homework.filter { HomeworkDashboardResolver.isActive($0) }.count
    }

    var body: some View {
        Button(action: action) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Aktif Ödevler", systemImage: "checklist")
                        .font(.headline)

                    if isLoading && homework.isEmpty {
                        ProgressView("Ödevler yükleniyor…")
                            .controlSize(.small)
                    } else if let errorMessage, homework.isEmpty {
                        Label("Ödevler alınamadı", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else if activeCount == 0 {
                        Text("Aktif ödev bulunmuyor.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(activeCount, format: .number)
                            .font(.title.weight(.semibold))
                            .monospacedDigit()
                        Text("aktif ödev")
                            .foregroundStyle(.secondary)
                    }

                    if !isCompact {
                        Spacer(minLength: 0)
                        Label("Ödevlere Git", systemImage: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: isCompact ? 88 : 132,
                    alignment: .topLeading
                )
            }
            .groupBoxStyle(DashboardGroupBoxStyle(isCompact: isCompact))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Aktif Ödevler, \(activeCount)")
        .accessibilityHint("Ödevler bölümünü açar")
    }
}

private enum HomeworkDashboardResolver {
    static func isActive(_ homework: Homework) -> Bool {
        guard homework.isActive else { return false }

        let completedWords = ["tamamlandı", "teslim edildi", "değerlendirildi", "kapalı", "completed"]
        let normalizedStatus = homework.statusName.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "tr_TR")
        )
        guard !completedWords.contains(where: normalizedStatus.contains) else { return false }

        guard let endDate = parseDate(homework.endDate) else { return true }
        return endDate >= Calendar.current.startOfDay(for: Date())
    }

    private static func parseDate(_ value: String) -> Date? {
        let formats = ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "dd.MM.yyyy", "dd/MM/yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}

private struct TodayScheduleSection: View {
    let schedule: LessonSchedule?
    let isLoading: Bool
    let errorMessage: String?
    let isCompact: Bool
    let action: () -> Void

    private var upcomingDay: ScheduleDashboardResolver.UpcomingDay? {
        schedule.flatMap { ScheduleDashboardResolver.upcomingDay(in: $0) }
    }

    private var sectionTitle: String {
        guard let upcomingDay else { return "Sıradaki Ders Programı" }
        return upcomingDay.isToday
            ? "Bugünün Ders Programı"
            : "Sıradaki Ders Programı · \(upcomingDay.dayName)"
    }

    var body: some View {
        Button(action: action) {
            GroupBox(sectionTitle) {
                VStack(alignment: .leading, spacing: 0) {
                    if isLoading && schedule == nil {
                        ProgressView("Ders programı yükleniyor…")
                            .padding(.vertical, 12)
                    } else if let errorMessage, schedule == nil {
                        DashboardErrorView(message: errorMessage)
                    } else if let schedule, let upcomingDay {
                        if upcomingDay.lessons.isEmpty {
                            Text("Yaklaşan bir ders bulunmuyor.")
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 12)
                        } else {
                            ForEach(upcomingDay.lessons) { lesson in
                                ScheduleDashboardRow(
                                    lesson: lesson,
                                    timeText: ScheduleDashboardResolver.timeText(for: lesson, in: schedule),
                                    emphasis: upcomingDay.isToday
                                        ? ScheduleDashboardResolver.emphasis(for: lesson, in: schedule)
                                        : .none,
                                    isCompact: isCompact
                                )
                                if lesson.id != upcomingDay.lessons.last?.id {
                                    Divider()
                                }
                            }
                        }
                    } else {
                        Text("Yaklaşan bir ders bulunmuyor.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    }

                    Label("Ders Programına Git", systemImage: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .groupBoxStyle(DashboardGroupBoxStyle(isCompact: isCompact))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHint("Ders Programı bölümünü açar")
    }
}

private struct ScheduleDashboardRow: View {
    let lesson: Lesson
    let timeText: String?
    let emphasis: ScheduleDashboardResolver.Emphasis
    let isCompact: Bool

    private var displayName: String {
        let subtitle = lesson.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subtitle.isEmpty {
            return subtitle
        }
        let subject = lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return subject.isEmpty ? "Ders" : subject
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: emphasis == .current ? "circle.fill" : "circle")
                .font(.caption2)
                .foregroundStyle(
                    emphasis == .none
                        ? AnyShapeStyle(.tertiary)
                        : AnyShapeStyle(.tint)
                )
                .accessibilityHidden(true)
            Text("\(lesson.x).")
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .fontWeight(emphasis == .none ? .regular : .semibold)
                if !lesson.teacher.isEmpty {
                    Text(lesson.teacher)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let timeText {
                Text(timeText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if emphasis == .current {
                Text("Şimdi")
                    .font(.caption)
                    .foregroundStyle(.tint)
            } else if emphasis == .next {
                Text("Sıradaki")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, isCompact ? 4 : 9)
    }
}

private enum ScheduleDashboardResolver {
    enum Emphasis { case none, current, next }

    struct UpcomingDay {
        let lessons: [Lesson]
        let dayName: String
        let isToday: Bool
    }

    static func upcomingDay(
        in schedule: LessonSchedule,
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> UpcomingDay? {
        let todaysLessons = lessonsToday(in: schedule, date: date, calendar: calendar)
        if !todaysLessons.isEmpty,
           !hasSchoolDayEnded(in: schedule, date: date, calendar: calendar) {
            return UpcomingDay(
                lessons: todaysLessons,
                dayName: dayName(for: date, calendar: calendar),
                isToday: true
            )
        }

        for offset in 1...7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: date) else {
                continue
            }
            let lessons = lessonsToday(in: schedule, date: candidate, calendar: calendar)
            if !lessons.isEmpty {
                return UpcomingDay(
                    lessons: lessons,
                    dayName: dayName(for: candidate, calendar: calendar),
                    isToday: false
                )
            }
        }
        return nil
    }

    static func lessonsToday(
        in schedule: LessonSchedule,
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> [Lesson] {
        let weekday = calendar.component(.weekday, from: date)
        // OBS indexes schedule days from Monday = 1 through Sunday = 7,
        // while Calendar uses Sunday = 1 through Saturday = 7.
        let apiDay = weekday == 1 ? 7 : weekday - 1
        return schedule.data.data
            .filter { $0.y == apiDay }
            .sorted { $0.x < $1.x }
    }

    static func timeText(for lesson: Lesson, in schedule: LessonSchedule) -> String? {
        guard let interval = interval(for: lesson, in: schedule) else { return nil }
        return "\(clock(interval.start))–\(clock(interval.end))"
    }

    static func emphasis(
        for lesson: Lesson,
        in schedule: LessonSchedule,
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> Emphasis {
        let lessons = lessonsToday(in: schedule, date: date, calendar: calendar)
        let timed = lessons.compactMap { item -> (Lesson, (start: Int, end: Int))? in
            interval(for: item, in: schedule).map { (item, $0) }
        }
        guard timed.count == lessons.count else { return .none }

        let now = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if let current = timed.first(where: { now >= $0.1.start && now < $0.1.end })?.0 {
            return current.id == lesson.id ? .current : .none
        }
        if let next = timed.first(where: { $0.1.start > now })?.0 {
            return next.id == lesson.id ? .next : .none
        }
        return .none
    }

    static func hasSchoolDayEnded(
        in schedule: LessonSchedule,
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let lessons = lessonsToday(in: schedule, date: date, calendar: calendar)
        guard !lessons.isEmpty else { return false }
        let intervals = lessons.compactMap { interval(for: $0, in: schedule) }
        guard intervals.count == lessons.count,
              let finalEnd = intervals.map(\.end).max() else {
            return false
        }
        let now = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return now >= finalEnd
    }

    private static func interval(for lesson: Lesson, in schedule: LessonSchedule) -> (start: Int, end: Int)? {
        guard lesson.x > 0, schedule.data.xInfo.indices.contains(lesson.x - 1) else { return nil }
        let text = schedule.data.xInfo[lesson.x - 1].joined(separator: " ")
        let pattern = #"([01]?\d|2[0-3])[:.]([0-5]\d)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = expression.matches(in: text, range: range)
        guard matches.count >= 2 else { return nil }

        func minutes(_ match: NSTextCheckingResult) -> Int? {
            guard let hourRange = Range(match.range(at: 1), in: text),
                  let minuteRange = Range(match.range(at: 2), in: text),
                  let hour = Int(text[hourRange]),
                  let minute = Int(text[minuteRange]) else { return nil }
            return hour * 60 + minute
        }

        guard let start = minutes(matches[0]), let end = minutes(matches[1]), end > start else { return nil }
        return (start, end)
    }

    private static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private static func dayName(for date: Date, calendar: Calendar) -> String {
        let names = ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"]
        let weekday = calendar.component(.weekday, from: date)
        return names.indices.contains(weekday - 1) ? names[weekday - 1] : "Sonraki Gün"
    }
}

private struct LatestExamSection: View {
    let dashboard: ExamDashboard?
    let isLoading: Bool
    let errorMessage: String?
    let action: () -> Void

    private var latest: StudentExam? {
        dashboard?.exams
            .filter { $0.examType.uppercased() != "DBS" }
            .max { lhs, rhs in
                let left = ExamDashboardResolver.date(lhs.examDate)
                let right = ExamDashboardResolver.date(rhs.examDate)
                switch (left, right) {
                case let (left?, right?): return left < right
                case (nil, _?): return true
                case (_?, nil): return false
                case (nil, nil): return false
                }
            }
    }

    var body: some View {
        Button(action: action) {
            GroupBox("Son Deneme Sınavı") {
                VStack(alignment: .leading, spacing: 8) {
                    if isLoading && dashboard == nil {
                        ProgressView("Deneme sınavları yükleniyor…")
                    } else if let errorMessage, dashboard == nil {
                        DashboardErrorView(message: errorMessage)
                    } else if let latest {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(latest.examName)
                                    .font(.headline)
                                if !latest.examDate.isEmpty {
                                    Text(latest.examDate)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if latest.point > 0 {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(latest.point, format: .number.precision(.fractionLength(2)))
                                        .font(.title3.weight(.semibold).monospacedDigit())
                                    Text("Puan")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if latest.questionCount > 0 {
                            HStack(spacing: 14) {
                                Text("Net: \(latest.net.formatted(.number.precision(.fractionLength(2))))")
                                Text("Doğru: \(latest.dogru)")
                                Text("Yanlış: \(latest.yanlis)")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Henüz deneme sınavı bulunmuyor.")
                            .foregroundStyle(.secondary)
                    }

                    Label("Deneme Sınavlarına Git", systemImage: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHint("Deneme Sınavları bölümünü açar")
    }
}

private enum ExamDashboardResolver {
    static func date(_ value: String) -> Date? {
        let formats = ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "dd.MM.yyyy", "dd/MM/yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}

private struct DashboardErrorView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Bilgiler yüklenemedi", systemImage: "exclamationmark.triangle")
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

private struct QuickAccessSection: View {
    let select: (AppSection) -> Void

    private let items: [QuickAccessItem] = [
        QuickAccessItem(title: "Deneme Sınavları", systemImage: "graduationcap", section: .practiceExams),
        QuickAccessItem(title: "Taramalar", systemImage: "doc.text.magnifyingglass", section: .taramalar),
        QuickAccessItem(title: "Ödevler", systemImage: "checklist", section: .homework),
        QuickAccessItem(title: "Ders Programı", systemImage: "calendar", section: .schedule),
        QuickAccessItem(title: "Yemek Listesi", systemImage: "fork.knife", section: .foodList),
        QuickAccessItem(title: "Mesajlar", systemImage: "envelope", section: .messages),
        QuickAccessItem(title: "Devamsızlık", systemImage: "calendar.badge.exclamationmark", section: .attendance),
        QuickAccessItem(title: "Öğretmenlerim", systemImage: "person.2", section: .teachers)
    ]

    var body: some View {
        GroupBox("Hızlı Erişim") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 155), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(items) { item in
                    Button {
                        select(item.section)
                    } label: {
                        Label(item.title, systemImage: item.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)
        }
    }
}

private struct QuickAccessItem: Identifiable {
    let title: String
    let systemImage: String
    let section: AppSection

    var id: AppSection { section }
}

private struct DashboardGroupBoxStyle: GroupBoxStyle {
    var isCompact = false

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 9 : 14) {
            configuration.label
                .font(.headline)
            configuration.content
        }
        .padding(isCompact ? 13 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.45), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
