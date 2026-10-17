import SwiftUI
import Charts
import Foundation

struct StudentProfile: Codable {
    let stuNo: String
    let classId: String
    let name: String
    let photoURL: URL?
    var stuType: String? = nil
    var parentName: String? = nil
}

struct ExamDashboard: Codable {
    let success: Bool
    let exams: [StudentExam]
    let kpi: ExamKPI?
    let lessonSuccess: [ExamLessonSuccess]
    let trend: JSONValue?
    let lessons: [JSONValue]

    init(exams: [StudentExam]) {
        success = true
        self.exams = exams
        kpi = nil
        lessonSuccess = []
        trend = nil
        lessons = []
    }

    init(exams: [StudentExam], preserving metadata: ExamDashboard) {
        success = metadata.success
        self.exams = exams
        kpi = metadata.kpi
        lessonSuccess = metadata.lessonSuccess
        trend = metadata.trend
        lessons = metadata.lessons
    }

    enum CodingKeys: String, CodingKey {
        case success, exams, kpi, lessonSuccess, trend, lessons
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        exams = try container.decodeIfPresent([StudentExam].self, forKey: .exams) ?? []
        kpi = try container.decodeIfPresent(ExamKPI.self, forKey: .kpi)
        lessonSuccess = (try? container.decode([ExamLessonSuccess].self, forKey: .lessonSuccess)) ?? []
        trend = try container.decodeIfPresent(JSONValue.self, forKey: .trend)
        lessons = (try? container.decode([JSONValue].self, forKey: .lessons)) ?? []
    }

    func lessonName(at index: Int) -> String {
        guard lessons.indices.contains(index) else { return "Ders \(index + 1)" }
        let item = lessons[index]
        if let name = item.stringValue { return name }
        for key in ["lesson", "name", "lessonName", "title"] {
            if let name = item[key]?.stringValue { return name }
        }
        return "Ders \(index + 1)"
    }

    var normalizedTrendPoints: [Double] {
        guard let points = trend?["point"], case .array(let values) = points else { return [] }
        return values.compactMap(\.numberValue)
    }
}

struct StudentExam: Codable, Identifiable {
    let examId: String
    let examName: String
    let examDate: String
    let point: Double
    let net: Double
    let dogru: Int
    let yanlis: Int
    let bos: Int
    let questionCount: Int
    let successRate: Double
    let TD: Double?
    let GD: Double?
    let SD: Double?
    let examType: String

    var id: String { examId }

    enum CodingKeys: String, CodingKey {
        case examId, examName, examDate, point, net, dogru, yanlis, bos
        case questionCount, successRate, TD, GD, SD, examType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        examId = (try? container.decode(String.self, forKey: .examId))
            ?? String((try? container.decode(Int.self, forKey: .examId)) ?? 0)
        examName = try container.decodeIfPresent(String.self, forKey: .examName) ?? "Sınav"
        examDate = try container.decodeIfPresent(String.self, forKey: .examDate) ?? ""
        point = container.decodeNumber(forKey: .point) ?? 0
        net = container.decodeNumber(forKey: .net) ?? 0
        dogru = container.decodeInteger(forKey: .dogru) ?? 0
        yanlis = container.decodeInteger(forKey: .yanlis) ?? 0
        bos = container.decodeInteger(forKey: .bos) ?? 0
        questionCount = container.decodeInteger(forKey: .questionCount) ?? dogru + yanlis + bos
        successRate = container.decodeNumber(forKey: .successRate) ?? 0
        TD = container.decodeNumber(forKey: .TD)
        GD = container.decodeNumber(forKey: .GD)
        SD = container.decodeNumber(forKey: .SD)
        examType = try container.decodeIfPresent(String.self, forKey: .examType) ?? "SBS"
    }

    init(indexRecord: WebExamRecord) {
        examId = indexRecord.sinavKod
        examName = indexRecord.sinavAd
        examDate = indexRecord.sinavTarih ?? ""
        point = indexRecord.point ?? 0
        net = indexRecord.net ?? 0
        dogru = indexRecord.correct ?? 0
        yanlis = indexRecord.incorrect ?? 0
        bos = indexRecord.blank ?? 0
        questionCount = indexRecord.questionCount ?? dogru + yanlis + bos
        successRate = indexRecord.successRate ?? 0
        TD = nil; GD = nil; SD = nil
        examType = indexRecord.examType
    }

    init(taramaExam: TaramaExam) {
        examId = taramaExam.examCode
        examName = taramaExam.name
        examDate = taramaExam.date ?? ""
        point = taramaExam.point ?? 0
        net = 0
        dogru = 0
        yanlis = 0
        bos = 0
        questionCount = 0
        successRate = 0
        TD = nil; GD = nil; SD = nil
        examType = taramaExam.examType
    }
}

struct WebExamRecord: Decodable, Identifiable, Hashable {
    let sinavKod: String
    let sinavAd: String
    let sinavTarih: String?
    let examType: String
    let point: Double?
    let net: Double?
    let correct: Int?
    let incorrect: Int?
    let blank: Int?
    let questionCount: Int?
    let successRate: Double?
    var id: String { "\(examType)|\(sinavKod)" }

    private enum CodingKeys: String, CodingKey {
        case sinavKod, sinavAd, sinavTarih, examType, point, net
        case correct = "dogru", incorrect = "yanlis", blank = "bos", questionCount, successRate
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sinavKod = (try? values.decode(String.self, forKey: .sinavKod))
            ?? String((try? values.decode(Int.self, forKey: .sinavKod)) ?? 0)
        sinavAd = try values.decodeIfPresent(String.self, forKey: .sinavAd) ?? "Sınav"
        sinavTarih = try values.decodeIfPresent(String.self, forKey: .sinavTarih)
        examType = (try values.decodeIfPresent(String.self, forKey: .examType) ?? "").uppercased()
        point = values.decodeNumber(forKey: .point)
        net = values.decodeNumber(forKey: .net)
        correct = values.decodeInteger(forKey: .correct)
        incorrect = values.decodeInteger(forKey: .incorrect)
        blank = values.decodeInteger(forKey: .blank)
        questionCount = values.decodeInteger(forKey: .questionCount)
        successRate = values.decodeNumber(forKey: .successRate)
    }
}

struct ExamKPI: Codable {
    let examCount: Int?
    let avgPoint: Double?
    let lastPoint: Double?
    let lastPointDelta: Double?
    let maxPoint: Double?
    let maxPointExamName: String?
    let avgSuccess: Double?
    let bestLesson: ExamLessonSuccess?
    let worstLesson: ExamLessonSuccess?

    enum CodingKeys: String, CodingKey {
        case examCount, avgPoint, lastPoint, lastPointDelta, maxPoint
        case maxPointExamName, avgSuccess, bestLesson, worstLesson
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        examCount = container.decodeInteger(forKey: .examCount)
        avgPoint = container.decodeNumber(forKey: .avgPoint)
        lastPoint = container.decodeNumber(forKey: .lastPoint)
        lastPointDelta = container.decodeNumber(forKey: .lastPointDelta)
        maxPoint = container.decodeNumber(forKey: .maxPoint)
        maxPointExamName = try container.decodeIfPresent(String.self, forKey: .maxPointExamName)
        avgSuccess = container.decodeNumber(forKey: .avgSuccess)
        bestLesson = try container.decodeIfPresent(ExamLessonSuccess.self, forKey: .bestLesson)
        worstLesson = try container.decodeIfPresent(ExamLessonSuccess.self, forKey: .worstLesson)
    }
}

struct ExamLessonSuccess: Codable, Identifiable {
    let lesson: String
    let successRate: Double
    var id: String { lesson }

    enum CodingKeys: String, CodingKey { case lesson, successRate }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lesson = try container.decodeIfPresent(String.self, forKey: .lesson) ?? "Ders"
        successRate = container.decodeNumber(forKey: .successRate) ?? 0
    }
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var numberValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value.replacingOccurrences(of: ",", with: "."))
        default: return nil
        }
    }

    subscript(key: String) -> JSONValue? {
        guard case .object(let values) = self else { return nil }
        return values[key]
    }
}

fileprivate struct ExamTopicAnalysis: Identifiable {
    let lesson: String
    let topic: String
    let questionCount: Int?
    let correct: Int?
    let wrong: Int?
    let successRate: Double?

    var id: String { "\(lesson)|\(topic)" }
}

fileprivate struct ExamLessonAnalysis: Identifiable {
    let lesson: String
    let topics: [ExamTopicAnalysis]

    var id: String { lesson }
    var questionCount: Int? { total(for: \.questionCount) }
    var correct: Int? { total(for: \.correct) }
    var wrong: Int? { total(for: \.wrong) }
    var successRate: Double? {
        if let questionCount, questionCount > 0, let correct {
            return Double(correct) / Double(questionCount) * 100
        }
        let rates = topics.compactMap(\.successRate)
        return rates.isEmpty ? nil : rates.reduce(0, +) / Double(rates.count)
    }

    private func total(for keyPath: KeyPath<ExamTopicAnalysis, Int?>) -> Int? {
        let values = topics.compactMap { $0[keyPath: keyPath] }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}

struct ExamSchoolReport: Codable {
    private static let examLessons = [
        "TÜRKÇE",
        "MATEMATİK",
        "SOSYAL BİL.",
        "FEN VE TEKN.",
        "DİN. KÜL.",
        "Y.DİL"
    ]

    let success: Bool
    let data: [String: JSONValue]
    let subanal: JSONValue?
    let graphs: JSONValue?
    private let lessonAnalyses: [ExamLessonAnalysis]

    enum CodingKeys: String, CodingKey { case success, data, subanal, graphs }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        data = (try? container.decode([String: JSONValue].self, forKey: .data)) ?? [:]
        subanal = try container.decodeIfPresent(JSONValue.self, forKey: .subanal)
        graphs = try container.decodeIfPresent(JSONValue.self, forKey: .graphs)
        lessonAnalyses = Self.parseLessonAnalyses(from: subanal)
    }

    fileprivate func achievementAnalyses() -> [ExamLessonAnalysis] {
        lessonAnalyses
    }

    private static func parseLessonAnalyses(from value: JSONValue?) -> [ExamLessonAnalysis] {
        guard let value else { return [] }
        var rows: [ExamTopicAnalysis] = []
        collectTopicRows(from: value, inheritedLesson: nil, into: &rows)

        var lessonOrder: [String] = []
        var grouped: [String: [ExamTopicAnalysis]] = [:]
        for row in rows {
            if grouped[row.lesson] == nil {
                lessonOrder.append(row.lesson)
            }
            if let index = grouped[row.lesson]?.firstIndex(where: { $0.topic == row.topic }) {
                let existing = grouped[row.lesson]?[index]
                grouped[row.lesson]?[index] = ExamTopicAnalysis(
                    lesson: row.lesson,
                    topic: row.topic,
                    questionCount: combined(existing?.questionCount, row.questionCount),
                    correct: combined(existing?.correct, row.correct),
                    wrong: combined(existing?.wrong, row.wrong),
                    successRate: combinedRate(existing, row)
                )
            } else {
                grouped[row.lesson, default: []].append(row)
            }
        }

        return lessonOrder.compactMap { lesson in
            guard let topics = grouped[lesson], !topics.isEmpty else { return nil }
            return ExamLessonAnalysis(lesson: lesson, topics: topics)
        }
    }

    private static func collectTopicRows(
        from value: JSONValue,
        inheritedLesson: String?,
        into rows: inout [ExamTopicAnalysis]
    ) {
        switch value {
        case .array(let values):
            for child in values {
                collectTopicRows(from: child, inheritedLesson: inheritedLesson, into: &rows)
            }
        case .object(let fields):
            let lesson = string(in: fields, keys: ["lesson", "ders", "dersAd", "lessonName"])
                ?? inheritedLesson
                ?? "Diğer"
            let topic = string(in: fields, keys: ["konuAd", "konu", "kazanim", "kazanım", "topic"])
            let questionCount = integer(in: fields, keys: ["SSay", "soruSayisi", "questionCount"])
            let correct = integer(in: fields, keys: ["Dog", "dogru", "correct"])
            let wrong = integer(in: fields, keys: ["Yan", "yanlis", "yanlış", "wrong"])
            let successRate = number(in: fields, keys: ["Bas", "basari", "başarı", "successRate"])

            if let topic, questionCount != nil || correct != nil || wrong != nil || successRate != nil {
                rows.append(
                    ExamTopicAnalysis(
                        lesson: lesson,
                        topic: topic,
                        questionCount: questionCount,
                        correct: correct,
                        wrong: wrong,
                        successRate: successRate
                    )
                )
                return
            }

            for child in fields.values {
                collectTopicRows(from: child, inheritedLesson: lesson == "Diğer" ? inheritedLesson : lesson, into: &rows)
            }
        case .string, .number, .bool, .null:
            break
        }
    }

    private static func string(in fields: [String: JSONValue], keys: [String]) -> String? {
        guard let text = value(in: fields, keys: keys)?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func integer(in fields: [String: JSONValue], keys: [String]) -> Int? {
        guard let number = value(in: fields, keys: keys)?.numberValue else { return nil }
        return Int(number.rounded())
    }

    private static func number(in fields: [String: JSONValue], keys: [String]) -> Double? {
        value(in: fields, keys: keys)?.numberValue
    }

    private static func value(in fields: [String: JSONValue], keys: [String]) -> JSONValue? {
        for key in keys {
            if let exact = fields[key] { return exact }
            if let match = fields.first(where: { $0.key.localizedCaseInsensitiveCompare(key) == .orderedSame }) {
                return match.value
            }
        }
        return nil
    }

    private static func combined(_ first: Int?, _ second: Int?) -> Int? {
        guard first != nil || second != nil else { return nil }
        return (first ?? 0) + (second ?? 0)
    }

    private static func combinedRate(_ first: ExamTopicAnalysis?, _ second: ExamTopicAnalysis) -> Double? {
        guard let first else { return second.successRate }
        if let firstCount = first.questionCount,
           let secondCount = second.questionCount,
           firstCount + secondCount > 0,
           let firstRate = first.successRate,
           let secondRate = second.successRate {
            return (firstRate * Double(firstCount) + secondRate * Double(secondCount))
                / Double(firstCount + secondCount)
        }
        return second.successRate ?? first.successRate
    }

    func subjectResults() -> [ExamSubjectResult] {
        (1...6).compactMap { index in
            let reportedQuestions = data.intValue("SR\(index)") ?? 0
            let correct = data.intValue("D\(index)") ?? 0
            let wrong = data.intValue("Y\(index)") ?? 0
            let reportedBlank = data.intValue("B\(index)")
            let blank = reportedBlank ?? max(reportedQuestions - correct - wrong, 0)
            let questions = reportedQuestions > 0 ? reportedQuestions : correct + wrong + blank
            let net = data.numberValue("N\(index)") ?? Double(correct) - Double(wrong) / 3
            guard questions > 0 || correct > 0 || wrong > 0 || blank > 0 || data["SC\(index)"] != nil else { return nil }
            return ExamSubjectResult(
                lesson: Self.examLessons[index - 1],
                index: index,
                questionCount: questions,
                correct: correct,
                wrong: wrong,
                blank: blank,
                net: net,
                questions: questionAnalysis(index: index)
            )
        }
    }

    var score: Double? { data.numberValue("Puan") }
    var totalNet: Double? { data.numberValue("N7") }
    var totalCorrect: Int? { data.intValue("D7") }
    var totalWrong: Int? { data.intValue("Y7") }
    var totalQuestions: Int? {
        let reported = data.intValue("SR7") ?? 0
        if reported > 0 { return reported }
        guard let correct = totalCorrect, let wrong = totalWrong else { return nil }
        return correct + wrong + (data.intValue("B7") ?? 0)
    }
    var totalBlank: Int? {
        if let blank = data.intValue("B7") { return blank }
        guard let totalQuestions, let totalCorrect, let totalWrong else { return nil }
        return max(totalQuestions - totalCorrect - totalWrong, 0)
    }
    var classRank: Int? { data.intValue("SD") }
    var generalRank: Int? { data.intValue("GD") }

    func questionAnalysis(index: Int) -> [ExamQuestion] {
        let correctKey = Array(data.stringValue("SC\(index)") ?? "")
        let studentKey = Array(data.stringValue("OC\(index)") ?? "")
        let expectedCount = data.intValue("SR\(index)") ?? 0
        let count = max(expectedCount, correctKey.count, studentKey.count)
        guard count > 0 else { return [] }

        return (0..<count).map { offset in
            let correct = correctKey.indices.contains(offset) ? correctKey[offset] : nil
            let response = studentKey.indices.contains(offset) ? studentKey[offset] : nil
            let isBlank = response == nil || response!.isWhitespace
            let status: AnswerStatus = isBlank ? .blank : (response!.isUppercase ? .correct : .wrong)
            let answer = isBlank ? nil : String(response!).uppercased()
            return ExamQuestion(
                questionNumber: offset + 1,
                correctAnswer: correct.map(String.init),
                studentAnswer: answer,
                status: status
            )
        }
    }
}

enum AnswerStatus: String, Codable {
    case correct
    case wrong
    case blank
}

struct ExamQuestion: Identifiable, Codable {
    let questionNumber: Int
    let correctAnswer: String?
    let studentAnswer: String?
    let status: AnswerStatus
    var id: Int { questionNumber }
}

struct ExamSubjectResult: Identifiable {
    let lesson: String
    let index: Int
    let questionCount: Int
    let correct: Int
    let wrong: Int
    let blank: Int
    let net: Double
    let questions: [ExamQuestion]
    var id: Int { index }

    var answerCountsMatchSummary: Bool? {
        guard !questions.isEmpty else { return nil }
        let correctAnswers = questions.filter { $0.status == .correct }.count
        let wrongAnswers = questions.filter { $0.status == .wrong }.count
        let blankAnswers = questions.filter { $0.status == .blank }.count
        return correctAnswers == correct && wrongAnswers == wrong && blankAnswers == blank
    }
}

private extension KeyedDecodingContainer {
    func decodeNumber(forKey key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(String.self, forKey: key) { return Double(value) }
        return nil
    }

    func decodeInteger(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(String.self, forKey: key) { return Int(value) }
        if let value = try? decode(Double.self, forKey: key) { return Int(value) }
        return nil
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func numberValue(_ key: String) -> Double? { self[key]?.numberValue }
    func intValue(_ key: String) -> Int? { self[key]?.numberValue.map(Int.init) }
    func stringValue(_ key: String) -> String? { self[key]?.stringValue }
}

struct ExamsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if let dashboard = model.examDashboard {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if let kpi = dashboard.kpi {
                                sectionTitle("Genel Bakış")
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], alignment: .leading, spacing: 10) {
                                    if let count = kpi.examCount { ExamMetricTile(title: "Sınav sayısı", value: "\(count)") }
                                    if let value = kpi.avgPoint { ExamMetricTile(title: "Ortalama puan", value: value.formatted(.number.precision(.fractionLength(2)))) }
                                    if let value = kpi.lastPoint { ExamMetricTile(title: "Son puan", value: value.formatted(.number.precision(.fractionLength(2)))) }
                                    if let value = kpi.lastPointDelta { ExamMetricTile(title: "Son puan değişimi", value: signed(value)) }
                                    if let value = kpi.avgSuccess { ExamMetricTile(title: "Ortalama başarı", value: percent(value)) }
                                    if let value = kpi.maxPoint { ExamMetricTile(title: "En yüksek puan", value: value.formatted(.number.precision(.fractionLength(2))), detail: kpi.maxPointExamName) }
                                    if let lesson = kpi.bestLesson { ExamMetricTile(title: "En yüksek ders", value: percent(lesson.successRate), detail: lesson.lesson) }
                                    if let lesson = kpi.worstLesson { ExamMetricTile(title: "En düşük ders", value: percent(lesson.successRate), detail: lesson.lesson) }
                                }
                            }

                            if !dashboard.exams.isEmpty {
                                sectionTitle("Puan Grafiği")
                                Chart(Array(dashboard.exams.enumerated().reversed()), id: \.element.id) { index, exam in
                                    let point = dashboard.normalizedTrendPoints.indices.contains(index)
                                        ? dashboard.normalizedTrendPoints[index]
                                        : exam.point
                                    LineMark(
                                        x: .value("Sınav", "\(exam.examDate) · \(dashboard.exams.count - index)"),
                                        y: .value("Puan", point)
                                    )
                                    PointMark(
                                        x: .value("Sınav", "\(exam.examDate) · \(dashboard.exams.count - index)"),
                                        y: .value("Puan", point)
                                    )
                                }
                                .chartYAxisLabel("Puan")
                                .chartYScale(domain: 0...500)
                                .frame(height: 220)
                            }

                            if !dashboard.lessonSuccess.isEmpty {
                                sectionTitle("Ders Başarıları")
                                Chart(dashboard.lessonSuccess) { lesson in
                                    BarMark(
                                        x: .value("Başarı", lesson.successRate),
                                        y: .value("Ders", lesson.lesson)
                                    )
                                    .foregroundStyle(.tint)
                                }
                                .chartXAxisLabel("Başarı (%)")
                                .frame(height: max(130, CGFloat(dashboard.lessonSuccess.count) * 32))
                            }

                            sectionTitle("Sınavlar")
                            if dashboard.exams.isEmpty {
                                ContentUnavailableView("Sınav bulunamadı", systemImage: "pencil")
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(dashboard.exams) { exam in
                                        NavigationLink {
                                            ExamDetailView(exam: exam, model: model)
                                        } label: {
                                            ExamRow(exam: exam)
                                        }
                                        .buttonStyle(.plain)
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding(22)
                        .frame(maxWidth: 980, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if let error = model.error {
                    ContentUnavailableView("Sınavlar alınamadı", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    ProgressView("Sınavlar yükleniyor...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Sınavlar")
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.title3.weight(.semibold))
    }

    private func percent(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1))))%"
    }

    private func signed(_ value: Double) -> String {
        let formatted = value.formatted(.number.precision(.fractionLength(2)))
        return value > 0 ? "+\(formatted)" : formatted
    }
}

private struct ExamMetricTile: View {
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).lineLimit(1)
            if let detail, !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct ExamRow: View {
    let exam: StudentExam

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(exam.examName).font(.headline)
                Spacer()
                Text(exam.point.formatted(.number.precision(.fractionLength(2))))
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
            HStack {
                Text(exam.examDate)
                Spacer()
                Text("Net \(exam.net.formatted(.number.precision(.fractionLength(2))))")
                Text("D/Y/B \(exam.dogru)/\(exam.yanlis)/\(exam.bos)")
                Text("\(exam.successRate.formatted(.number.precision(.fractionLength(1))))%")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

struct ExamDetailView: View {
    enum Section: String, CaseIterable, Identifiable {
        case results = "Netler"
        case answers = "Cevaplar"
        case analysis = "Kazanım"

        var id: Self { self }
    }

    let exam: StudentExam
    @ObservedObject var model: AppModel
    @State private var section: Section = .results

    var body: some View {
        Group {
            if let report = model.examReport {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(exam.examName)
                            .font(.title2.weight(.semibold))
                        if !exam.examDate.isEmpty {
                            Text(exam.examDate)
                                .foregroundStyle(.secondary)
                        }
                        Picker("Sınav bölümü", selection: $section) {
                            ForEach(Section.allCases) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 420)
                        .padding(.top, 8)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    ExamDetailSectionContent(
                        section: section,
                        exam: exam,
                        report: report
                    )
                }
            } else if model.isLoadingExamReport {
                ProgressView("Sınav detayları yükleniyor...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.examReportError {
                ContentUnavailableView("Sınav detayı alınamadı", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView("Sınav detayları yükleniyor...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(exam.examName)
        .task(id: exam.id) {
            await model.loadExamReport(examId: exam.examId, examType: exam.examType)
        }
    }
}

private struct ExamDetailSectionContent: View {
    let section: ExamDetailView.Section
    let exam: StudentExam
    let report: ExamSchoolReport

    var body: some View {
        switch section {
        case .results:
            ExamResultsSection(exam: exam, report: report)
        case .answers:
            ExamAnswersSection(subjects: report.subjectResults())
        case .analysis:
            ExamAnalysisSection(lessons: report.achievementAnalyses())
        }
    }
}

private struct ExamResultsSection: View {
    let exam: StudentExam
    let report: ExamSchoolReport

    private var subjects: [ExamSubjectResult] { report.subjectResults() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ExamMetricTile(title: "Puan", value: (report.score ?? exam.point).formatted(.number.precision(.fractionLength(0...2))))
                    ExamMetricTile(title: "Net", value: (report.totalNet ?? exam.net).formatted(.number.precision(.fractionLength(0...2))))
                    ExamMetricTile(title: "Doğru", value: "\(report.totalCorrect ?? exam.dogru)")
                    ExamMetricTile(title: "Yanlış", value: "\(report.totalWrong ?? exam.yanlis)")
                    ExamMetricTile(title: "Boş", value: "\(report.totalBlank ?? exam.bos)")
                    ExamMetricTile(title: "Soru sayısı", value: "\(report.totalQuestions ?? exam.questionCount)")
                    if let rank = report.classRank {
                        ExamMetricTile(title: "Sınıf derecesi", value: "\(rank)")
                    }
                    if let rank = report.generalRank {
                        ExamMetricTile(title: "Genel derece", value: "\(rank)")
                    }
                }

                Text("Netler")
                    .font(.title3.weight(.semibold))
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                        GridRow {
                            Text("Ders")
                            Text("S.Say")
                            Text("Doğru")
                            Text("Yanlış")
                            Text("Boş")
                            Text("Net")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                        ForEach(subjects) { subject in
                            GridRow {
                                Text(subject.lesson).frame(minWidth: 150, alignment: .leading)
                                Text("\(subject.questionCount)").monospacedDigit()
                                Text("\(subject.correct)").monospacedDigit().foregroundStyle(.green)
                                Text("\(subject.wrong)").monospacedDigit().foregroundStyle(.red)
                                Text("\(subject.blank)").monospacedDigit().foregroundStyle(.secondary)
                                Text(subject.net.formatted(.number.precision(.fractionLength(0...2))))
                                    .monospacedDigit()
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ExamAnswersSection: View {
    let subjects: [ExamSubjectResult]

    private var subjectsWithAnswers: [ExamSubjectResult] {
        subjects.filter { !$0.questions.isEmpty }
    }

    var body: some View {
        if subjectsWithAnswers.isEmpty {
            ContentUnavailableView(
                "Cevap analizi bulunamadı",
                systemImage: "checklist",
                description: Text("Bu sınav için cevap anahtarı veya öğrenci cevabı paylaşılmamış.")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(subjectsWithAnswers) { subject in
                        ExamAnswerSubjectSection(subject: subject)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ExamAnswerSubjectSection: View {
    let subject: ExamSubjectResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(subject.lesson)
                .font(.title3.weight(.semibold))
            HStack {
                Text("Soru").frame(width: 48, alignment: .leading)
                Text("Cevap Anahtarı").frame(width: 100, alignment: .leading)
                Text("Öğrenci Cevabı").frame(width: 110, alignment: .leading)
                Text("Durum")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(subject.questions) { question in
                ExamQuestionRow(question: question)
            }
            if subject.answerCountsMatchSummary == false {
                Label("Cevap analizi özet D/Y/B değerleriyle uyuşmuyor.", systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct ExamAnalysisSection: View {
    let lessons: [ExamLessonAnalysis]

    var body: some View {
        if !lessons.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text("Kazanım Analizi")
                        .font(.title3.weight(.semibold))
                    ForEach(lessons) { lesson in
                        ExamLessonAnalysisSection(analysis: lesson)
                    }
                }
                .padding(20)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "Kazanım analizi bulunamadı",
                systemImage: "list.bullet.clipboard",
                description: Text("Bu sınav için kazanım bilgisi paylaşılmamış.")
            )
        }
    }
}

private struct ExamLessonAnalysisSection: View {
    let analysis: ExamLessonAnalysis

    var body: some View {
        GroupBox {
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        Text("Konu / Kazanım")
                        Text("Soru")
                        Text("Doğru")
                        Text("Yanlış")
                        Text("Başarı")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    Divider()
                        .gridCellColumns(5)

                    ForEach(analysis.topics) { topic in
                        GridRow {
                            Text(topic.topic)
                                .frame(minWidth: 260, maxWidth: 440, alignment: .leading)
                            analysisValue(topic.questionCount, color: .secondary)
                            analysisValue(topic.correct, color: .green)
                            analysisValue(topic.wrong, color: .red)
                            percentageValue(topic.successRate)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(analysis.lesson)
                    .font(.headline)
                Spacer()
                lessonSummary
            }
        }
    }

    private var lessonSummary: some View {
        HStack(spacing: 10) {
            if let count = analysis.questionCount {
                Text("\(count) soru")
            }
            if let correct = analysis.correct {
                Label("\(correct)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if let wrong = analysis.wrong {
                Label("\(wrong)", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
            if let successRate = analysis.successRate {
                Label(
                    successRate.formatted(.number.precision(.fractionLength(0...1))) + "%",
                    systemImage: "chart.bar.fill"
                )
                .foregroundStyle(.blue)
            }
        }
        .font(.caption.monospacedDigit())
        .labelStyle(.titleAndIcon)
    }

    private func analysisValue(_ value: Int?, color: Color) -> some View {
        Text(value.map(String.init) ?? "—")
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(minWidth: 48, alignment: .leading)
    }

    private func percentageValue(_ value: Double?) -> some View {
        Text(value.map { $0.formatted(.number.precision(.fractionLength(0...1))) + "%" } ?? "—")
            .monospacedDigit()
            .foregroundStyle(.blue)
            .frame(minWidth: 58, alignment: .leading)
    }
}

private struct ExamQuestionRow: View {
    let question: ExamQuestion

    private var statusColor: Color {
        switch question.status {
        case .correct: return .green
        case .wrong: return .red
        case .blank: return .secondary
        }
    }

    private var statusText: String {
        switch question.status {
        case .correct: return "✓ Doğru"
        case .wrong: return "✗ Yanlış"
        case .blank: return "Boş"
        }
    }

    var body: some View {
        HStack {
            Text(String(format: "%02d", question.questionNumber))
                .monospacedDigit().frame(width: 48, alignment: .leading)
            Text(question.correctAnswer ?? "—")
                .frame(width: 100, alignment: .leading)
            Text(question.studentAnswer ?? "Boş")
                .frame(width: 110, alignment: .leading)
            Text(statusText).foregroundStyle(statusColor)
        }
        .font(.callout.monospacedDigit())
        .padding(.vertical, 3)
    }
}

private struct JSONAnalysisView: View {
    let value: JSONValue
    let title: String

    var body: some View {
        switch value {
        case .object(let fields):
            DisclosureGroup(title) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(fields.keys.sorted(), id: \.self) { key in
                        JSONAnalysisView(value: fields[key] ?? .null, title: key)
                    }
                }
                .padding(.leading, 10)
            }
        case .array(let values):
            DisclosureGroup(title) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, child in
                        JSONAnalysisView(value: child, title: "\(index + 1)")
                    }
                }
                .padding(.leading, 10)
            }
        default:
            HStack {
                Text(title)
                Spacer()
                Text(displayValue).foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private var displayValue: String {
        switch value {
        case .string(let string): return string
        case .number(let number): return number.formatted(.number.precision(.fractionLength(0...2)))
        case .bool(let bool): return bool ? "Evet" : "Hayır"
        case .null: return "—"
        case .object, .array: return ""
        }
    }
}
