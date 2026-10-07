import SwiftUI
import Charts
import Foundation

struct StudentProfile: Codable {
    let stuNo: String
    let classId: String
    let name: String
    let photoURL: URL?
}

struct ExamDashboard: Codable {
    let success: Bool
    let exams: [StudentExam]
    let kpi: ExamKPI?
    let lessonSuccess: [ExamLessonSuccess]
    let trend: JSONValue?
    let lessons: [JSONValue]

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

    var id: String { examId }

    enum CodingKeys: String, CodingKey {
        case examId, examName, examDate, point, net, dogru, yanlis, bos
        case questionCount, successRate, TD, GD, SD
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
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    subscript(key: String) -> JSONValue? {
        guard case .object(let values) = self else { return nil }
        return values[key]
    }
}

struct ExamSchoolReport: Codable {
    private static let examLessons = [
        "TÜRKÇE",
        "SOSYAL BİL.",
        "DİN. KÜL.",
        "Y.DİL",
        "MATEMATİK",
        "FEN VE TEKN."
    ]

    let success: Bool
    let data: [String: JSONValue]
    let subanal: JSONValue?
    let graphs: JSONValue?

    enum CodingKeys: String, CodingKey { case success, data, subanal, graphs }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        data = (try? container.decode([String: JSONValue].self, forKey: .data)) ?? [:]
        subanal = try container.decodeIfPresent(JSONValue.self, forKey: .subanal)
        graphs = try container.decodeIfPresent(JSONValue.self, forKey: .graphs)
    }

    func subjectResults() -> [ExamSubjectResult] {
        (1...6).compactMap { index in
            let questions = data.intValue("SR\(index)") ?? 0
            let correct = data.intValue("D\(index)") ?? 0
            let wrong = data.intValue("Y\(index)") ?? 0
            let net = data.numberValue("N\(index)") ?? Double(correct) - Double(wrong) / 3
            guard questions > 0 || correct > 0 || wrong > 0 || data["SC\(index)"] != nil else { return nil }
            return ExamSubjectResult(
                lesson: Self.examLessons[index - 1],
                index: index,
                questionCount: questions,
                correct: correct,
                wrong: wrong,
                blank: max(questions - correct - wrong, 0),
                net: net,
                questions: questionAnalysis(index: index)
            )
        }
    }

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
                                Chart(Array(dashboard.exams.enumerated()), id: \.element.id) { index, exam in
                                    let point = dashboard.normalizedTrendPoints.indices.contains(index)
                                        ? dashboard.normalizedTrendPoints[index]
                                        : exam.point
                                    LineMark(
                                        x: .value("Sınav", "\(exam.examDate) · \(index + 1)"),
                                        y: .value("Puan", point)
                                    )
                                    PointMark(
                                        x: .value("Sınav", "\(exam.examDate) · \(index + 1)"),
                                        y: .value("Puan", point)
                                    )
                                }
                                .chartYAxisLabel("Puan")
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

private struct ExamDetailView: View {
    let exam: StudentExam
    @ObservedObject var model: AppModel

    private var subjects: [ExamSubjectResult] {
        model.examReport?.subjectResults() ?? []
    }

    var body: some View {
        Group {
            if let report = model.examReport {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(exam.examName).font(.title2.weight(.semibold))
                            Text(exam.examDate).foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 8) {
                                ExamMetricTile(title: "Puan", value: exam.point.formatted(.number.precision(.fractionLength(2))))
                                ExamMetricTile(title: "Net", value: exam.net.formatted(.number.precision(.fractionLength(2))))
                                ExamMetricTile(title: "Doğru", value: "\(exam.dogru)")
                                ExamMetricTile(title: "Yanlış", value: "\(exam.yanlis)")
                                ExamMetricTile(title: "Boş", value: "\(exam.bos)")
                                ExamMetricTile(title: "Soru sayısı", value: "\(exam.questionCount)")
                                ExamMetricTile(title: "Başarı", value: "\(exam.successRate.formatted(.number.precision(.fractionLength(1))))%")
                            }
                        }

                        if !subjects.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Ders Sonuçları").font(.title3.weight(.semibold))
                                ForEach(subjects) { subject in
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack {
                                            Text(subject.lesson).font(.headline)
                                            Spacer()
                                            Text("\(subject.questionCount) soru")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        HStack(spacing: 14) {
                                            Text("\(subject.correct) doğru")
                                            Text("\(subject.wrong) yanlış")
                                            Text("\(subject.blank) boş")
                                            Spacer()
                                            Text("\(subject.net.formatted(.number.precision(.fractionLength(2)))) net")
                                                .fontWeight(.medium)
                                        }
                                        .font(.caption)
                                        if subject.answerCountsMatchSummary == false {
                                            Label("Cevap analizi özet D/Y/B değerleriyle uyuşmuyor.", systemImage: "exclamationmark.circle")
                                                .font(.caption2).foregroundStyle(.orange)
                                        }
                                    }
                                    .padding(.vertical, 7)
                                    Divider()
                                }
                            }
                        }

                        if let subanal = report.subanal, subanal != .null {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Konu Analizi").font(.title3.weight(.semibold))
                                JSONAnalysisView(value: subanal, title: "Dersler")
                            }
                        }

                        ForEach(subjects.filter { !$0.questions.isEmpty }) { subject in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(subject.lesson) · Soru Analizi")
                                    .font(.title3.weight(.semibold))
                                HStack {
                                    Text("Soru").frame(width: 48, alignment: .leading)
                                    Text("Doğru cevap").frame(width: 100, alignment: .leading)
                                    Text("Öğrenci cevabı").frame(width: 110, alignment: .leading)
                                    Text("Sonuç")
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                ForEach(subject.questions) { question in
                                    ExamQuestionRow(question: question)
                                }
                            }
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: 850, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            await model.loadExamReport(examId: exam.examId)
        }
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
