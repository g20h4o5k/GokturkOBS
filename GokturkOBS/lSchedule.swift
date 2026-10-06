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

struct ScheduleView: View {
    let schedule: LessonSchedule
    let refresh: () -> Void
    private let days = ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]

    private func lesson(x: Int, y: Int) -> Lesson? {
        schedule.data.data.first { $0.x == x && $0.y == y }
    }

    private func timeText(for x: Int) -> String {
        let index = x - 1
        guard index >= 0, index < schedule.data.xInfo.count else { return "" }
        return schedule.data.xInfo[index].first ?? ""
    }

    private var lessonNumbers: [Int] {
        guard !schedule.data.xInfo.isEmpty else { return [] }
        return Array(1...schedule.data.xInfo.count)
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ders Programı").font(.largeTitle).bold()
                    if let period = schedule.periodList.first { Text(period.description).foregroundStyle(.secondary) }
                }
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Text("Saat").fontWeight(.semibold).frame(width: 80)
                        ForEach(days, id: \.self) { day in
                            Text(day).fontWeight(.semibold).frame(width: 140)
                        }
                    }
                    ForEach(lessonNumbers, id: \.self) { x in
                        GridRow {
                            Text(timeText(for: x)).font(.caption).fontWeight(.semibold).frame(width: 80, height: 80)
                            ForEach(Array(1...7), id: \.self) { y in
                                LessonCell(lesson: lesson(x: x, y: y))
                            }
                        }
                    }
                }
            }.padding(28)
        }
        .navigationTitle("Ders Programı")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { refresh() } label: { Label("Yenile", systemImage: "arrow.clockwise") }
            }
        }
    }
}

struct LessonCell: View {
    let lesson: Lesson?

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
        }.frame(width: 140, height: 80)
    }
}
