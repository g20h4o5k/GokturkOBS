import SwiftUI
import Foundation

struct TaramaExam: Decodable, Identifiable, Hashable {
    let examType: String
    let examCode: String
    let name: String
    let date: String?
    let point: Double?

    var id: String { examCode }

    private enum CodingKeys: String, CodingKey {
        case examType, sinavKod, sinavAd, sinavTarih, point
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        examType = values.taramaString(forKey: .examType) ?? ""
        guard let code = values.taramaString(forKey: .sinavKod), !code.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .sinavKod, in: values, debugDescription: "Tarama sınav kodu eksik.")
        }
        examCode = code
        name = values.taramaString(forKey: .sinavAd) ?? "Tarama"
        date = values.taramaString(forKey: .sinavTarih)
        point = values.taramaDouble(forKey: .point)
    }
}

struct TaramaLesson: Decodable, Identifiable {
    let lesson: String
    let group: String?
    var id: String { "\(group ?? "")|\(lesson)" }
}

struct TaramaLabeledValue: Decodable, Identifiable {
    let label: String
    let value: Double?
    var id: String { label }

    private enum CodingKeys: String, CodingKey { case label, value, puan }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        label = values.taramaString(forKey: .label) ?? ""
        value = values.taramaDouble(forKey: .value) ?? values.taramaDouble(forKey: .puan)
    }
}

struct TaramaDetail: Decodable {
    let lessons: [TaramaLesson]
    let questionCounts: [Double?]
    let correctCounts: [Double?]
    let incorrectCounts: [Double?]
    let nets: [Double?]
    let scores: [TaramaLabeledValue]
    let rankings: [[TaramaLabeledValue]]
    let participation: [TaramaLabeledValue]
    let answerKeys: [String]
    let studentAnswers: [String]

    private enum CodingKeys: String, CodingKey {
        case lessons, ss, d, y, n, p, derece, sayi, examKey, answer
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        lessons = (try? values.decode([TaramaLesson].self, forKey: .lessons)) ?? []
        questionCounts = values.taramaNumberArray(forKey: .ss)
        correctCounts = values.taramaNumberArray(forKey: .d)
        incorrectCounts = values.taramaNumberArray(forKey: .y)
        nets = values.taramaNumberArray(forKey: .n)
        scores = (try? values.decode([TaramaLabeledValue].self, forKey: .p)) ?? []
        rankings = (try? values.decode([[TaramaLabeledValue]].self, forKey: .derece)) ?? []
        participation = (try? values.decode([TaramaLabeledValue].self, forKey: .sayi)) ?? []
        answerKeys = values.taramaStringArray(forKey: .examKey)
        studentAnswers = values.taramaStringArray(forKey: .answer)
    }

    func lessonResult(at index: Int) -> TaramaLessonResult? {
        guard lessons.indices.contains(index),
              questionCounts.indices.contains(index),
              let questionCount = questionCounts[index], questionCount > 0 else { return nil }
        return TaramaLessonResult(
            lesson: lessons[index],
            questionCount: questionCount,
            correct: correctCounts[safe: index] ?? nil,
            incorrect: incorrectCounts[safe: index] ?? nil,
            net: nets[safe: index] ?? nil
        )
    }
}

struct TaramaLessonResult: Identifiable {
    let lesson: TaramaLesson
    let questionCount: Double
    let correct: Double?
    let incorrect: Double?
    let net: Double?
    var id: String { lesson.id }
}

struct TaramaSubjectAnalysis: Decodable, Identifiable {
    let lesson: String
    let topic: String
    let questionCount: Double?
    let correct: Double?
    let incorrect: Double?
    let performance: Double?
    let sequence: Int

    var id: String { "\(sequence)|\(lesson)|\(topic)" }

    private enum CodingKeys: String, CodingKey { case lesson, konuAd, SSay, Dog, Yan, Bas }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        lesson = values.taramaString(forKey: .lesson) ?? "Ders"
        topic = values.taramaString(forKey: .konuAd) ?? "—"
        questionCount = values.taramaDouble(forKey: .SSay)
        correct = values.taramaDouble(forKey: .Dog)
        incorrect = values.taramaDouble(forKey: .Yan)
        performance = values.taramaDouble(forKey: .Bas)
        sequence = decoder.codingPath.last?.intValue ?? 0
    }
}

struct TaramaAnswer: Identifiable {
    enum Status { case correct, incorrect, unanswered, unknown }
    let number: Int
    let key: Character?
    let answer: Character?
    let status: Status
    var id: Int { number }
}

struct TaramalarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoadingTaramalar && model.taramalar.isEmpty {
                    ProgressView("Taramalar yükleniyor...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.taramalarError, model.taramalar.isEmpty {
                    ContentUnavailableView {
                        Label("Tarama sonuçları alınamadı.", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Tekrar Dene") { Task { await model.loadTaramalar(forceReload: true) } }
                    }
                } else if model.taramalar.isEmpty {
                    ContentUnavailableView("Henüz tarama sonucu bulunamadı.", systemImage: "checklist")
                } else {
                    List(model.taramalar) { exam in
                        NavigationLink {
                            TaramaDetailView(exam: exam, model: model)
                        } label: {
                            TaramaRow(exam: exam)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Taramalar")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await model.loadTaramalar(forceReload: true) } } label: {
                        Label("Taramaları Yenile", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isLoadingTaramalar)
                }
            }
            .task { await model.loadTaramalar() }
        }
    }
}

private struct TaramaRow: View {
    let exam: TaramaExam

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exam.name).font(.headline).lineLimit(2)
                if let date = exam.date, !date.isEmpty {
                    Text(date).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let point = exam.point {
                Text(point.formatted(.number.precision(.fractionLength(0...2))))
                    .font(.body.weight(.semibold).monospacedDigit())
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

private struct TaramaDetailView: View {
    enum Section: String, CaseIterable, Identifiable {
        case results = "Netler"
        case answers = "Cevaplar"
        case analysis = "Kazanım"
        var id: Self { self }
    }

    let exam: TaramaExam
    @ObservedObject var model: AppModel
    @State private var section: Section = .results

    var body: some View {
        Group {
            if model.isLoadingTaramaDetail && model.taramaDetail == nil {
                ProgressView("Tarama detayları yükleniyor...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.taramaDetailError, model.taramaDetail == nil {
                ContentUnavailableView {
                    Label("Tarama detayları yüklenemedi.", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("Tekrar Dene") { Task { await model.loadTaramaDetail(examCode: exam.examCode) } }
                }
            } else if let detail = model.taramaDetail {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(exam.name).font(.title2.weight(.semibold))
                        if let date = exam.date { Text(date).foregroundStyle(.secondary) }
                        Picker("Tarama bölümü", selection: $section) {
                            ForEach(Section.allCases) { item in Text(item.rawValue).tag(item) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 420)
                        .padding(.top, 8)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    sectionContent(detail)
                }
            }
        }
        .navigationTitle("Tarama Detayı")
        .task(id: exam.examCode) { await model.loadTaramaDetail(examCode: exam.examCode) }
        .onChange(of: section) { _, newValue in
            guard newValue == .analysis else { return }
            Task { await model.loadTaramaSubjectAnalysis(examCode: exam.examCode) }
        }
    }

    @ViewBuilder
    private func sectionContent(_ detail: TaramaDetail) -> some View {
        switch section {
        case .results: TaramaResultsView(detail: detail)
        case .answers: TaramaAnswersView(detail: detail)
        case .analysis: TaramaAnalysisView(model: model, examCode: exam.examCode)
        }
    }
}

private struct TaramaResultsView: View {
    let detail: TaramaDetail
    private var results: [TaramaLessonResult] { detail.lessons.indices.compactMap(detail.lessonResult) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Netler").font(.title3.weight(.semibold))
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                        GridRow {
                            Text("Ders"); Text("S.Say"); Text("Doğru"); Text("Yanlış"); Text("Net")
                        }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            if index == 0 || result.lesson.group != results[index - 1].lesson.group,
                               let group = result.lesson.group, !group.isEmpty {
                                GridRow { Text(group).font(.headline).gridCellColumns(5) }
                            }
                            GridRow {
                                Text(result.lesson.lesson).frame(minWidth: 150, alignment: .leading)
                                metric(result.questionCount)
                                metric(result.correct).foregroundStyle(.green)
                                metric(result.incorrect).foregroundStyle(.red)
                                metric(result.net).foregroundStyle(.blue)
                            }
                        }
                    }
                }

                if !detail.scores.isEmpty {
                    labeledSection("Puan ve Dereceler", values: detail.scores, includeRankings: true)
                }
                let participation = detail.participation.filter { ($0.value ?? 0) > 0 }
                if !participation.isEmpty {
                    labeledSection("Sınava giren öğrenci sayıları", values: participation, includeRankings: false)
                }
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metric(_ value: Double?) -> Text {
        Text(value?.formatted(.number.precision(.fractionLength(0...2))) ?? "—").monospacedDigit()
    }

    private func labeledSection(_ title: String, values: [TaramaLabeledValue], includeRankings: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.title3.weight(.semibold))
            ForEach(Array(values.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline) {
                    Text(item.label)
                    Spacer()
                    metric(item.value).fontWeight(.semibold)
                    if includeRankings, detail.rankings.indices.contains(index) {
                        ForEach(detail.rankings[index].filter { ($0.value ?? 0) > 0 }) { ranking in
                            Text("\(ranking.label): \(ranking.value?.formatted(.number.precision(.fractionLength(0...2))) ?? "—")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
            }
        }
    }
}

private struct TaramaAnswersView: View {
    let detail: TaramaDetail

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(detail.lessons.indices, id: \.self) { index in
                    if let result = detail.lessonResult(at: index) {
                        let answers = answerRows(index: index, expectedCount: Int(result.questionCount))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(result.lesson.lesson).font(.title3.weight(.semibold))
                            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
                                GridRow { Text("Soru"); Text("Cevap Anahtarı"); Text("Öğrenci Cevabı"); Text("Durum") }
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(answers) { answer in TaramaAnswerRow(answer: answer) }
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func answerRows(index: Int, expectedCount: Int) -> [TaramaAnswer] {
        let keys = Array(detail.answerKeys[safe: index] ?? "")
        let answers = Array(detail.studentAnswers[safe: index] ?? "")
        return (0..<max(expectedCount, keys.count, answers.count)).map { position in
            let key = keys[safe: position]
            let answer = answers[safe: position]
            let blankMarkers: Set<Character> = [" ", "-", "_", "*"]
            let status: TaramaAnswer.Status
            if let answer, blankMarkers.contains(answer) { status = .unanswered }
            else if let key, let answer { status = String(key).caseInsensitiveCompare(String(answer)) == .orderedSame ? .correct : .incorrect }
            else if answer == nil { status = .unanswered }
            else { status = .unknown }
            return TaramaAnswer(number: position + 1, key: key, answer: answer, status: status)
        }
    }
}

private struct TaramaAnswerRow: View {
    let answer: TaramaAnswer
    var body: some View {
        GridRow {
            Text("\(answer.number)").monospacedDigit()
            Text(answer.key.map(String.init) ?? "—")
            Text(answer.answer.map(String.init) ?? "Boş")
            Label(statusText, systemImage: statusIcon).foregroundStyle(statusColor)
        }
    }
    private var statusText: String { switch answer.status { case .correct: "Doğru"; case .incorrect: "Yanlış"; case .unanswered: "Boş"; case .unknown: "Belirsiz" } }
    private var statusIcon: String { switch answer.status { case .correct: "checkmark.circle"; case .incorrect: "xmark.circle"; case .unanswered: "minus.circle"; case .unknown: "questionmark.circle" } }
    private var statusColor: Color { switch answer.status { case .correct: .green; case .incorrect: .red; case .unanswered, .unknown: .secondary } }
}

private struct TaramaAnalysisView: View {
    @ObservedObject var model: AppModel
    let examCode: String

    var body: some View {
        Group {
            if model.isLoadingTaramaAnalysis && model.taramaSubjectAnalysis.isEmpty {
                ProgressView("Kazanım analizi yükleniyor...")
            } else if let error = model.taramaAnalysisError, model.taramaSubjectAnalysis.isEmpty {
                ContentUnavailableView {
                    Label("Kazanım analizi yüklenemedi.", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("Tekrar Dene") { Task { await model.loadTaramaSubjectAnalysis(examCode: examCode, forceReload: true) } }
                }
            } else if model.taramaSubjectAnalysis.isEmpty {
                ContentUnavailableView("Sınava ait konu analizi tanımlanmamış.", systemImage: "list.bullet.clipboard")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(groupedAnalysis, id: \.lesson) { group in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(group.lesson).font(.title3.weight(.semibold))
                                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                                    GridRow { Text("Konu"); Text("SS"); Text("D"); Text("Y"); Text("%") }
                                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    ForEach(group.entries) { item in
                                        GridRow {
                                            Text(item.topic).frame(minWidth: 190, alignment: .leading)
                                            value(item.questionCount); value(item.correct); value(item.incorrect); value(item.performance)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groupedAnalysis: [(lesson: String, entries: [TaramaSubjectAnalysis])] {
        var result: [(String, [TaramaSubjectAnalysis])] = []
        for item in model.taramaSubjectAnalysis {
            if result.last?.0 == item.lesson { result[result.count - 1].1.append(item) }
            else { result.append((item.lesson, [item])) }
        }
        return result
    }

    private func value(_ number: Double?) -> Text {
        Text(number?.formatted(.number.precision(.fractionLength(0...2))) ?? "—").monospacedDigit()
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

private extension KeyedDecodingContainer {
    func taramaString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value.map(String.init) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value.map(String.init) }
        return nil
    }

    func taramaDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value.map(Double.init) }
        if let value = try? decodeIfPresent(String.self, forKey: key), let text = value {
            return Double(text.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    func taramaNumberArray(forKey key: Key) -> [Double?] {
        guard let values = try? decodeIfPresent([JSONValue].self, forKey: key) else { return [] }
        return (values ?? []).map(\.numberValue)
    }

    func taramaStringArray(forKey key: Key) -> [String] {
        guard let values = try? decodeIfPresent([JSONValue].self, forKey: key) else { return [] }
        return (values ?? []).map { value in
            value.stringValue ?? value.numberValue.map(String.init) ?? ""
        }
    }
}
