import SwiftUI
import Foundation
import AppKit
import Combine

let baseURL = URL(string: "https://tedemkolejiobs.com")!

@MainActor
final class AppModel: ObservableObject {
    @Published var username = ""
    @Published var password = ""
    @Published var schedule: LessonSchedule?
    @Published var homework: [Homework] = []
    @Published var examDashboard: ExamDashboard?
    @Published var examReport: ExamSchoolReport?
    @Published var isLoadingExamReport = false
    @Published var examReportError: String?
    @Published var homeworkDetail: HomeworkDetail?
    @Published var isLoadingHomeworkDetail = false
    @Published var homeworkDetailError: String?
    @Published var isLoading = true
    @Published var isLoggingIn = false
    @Published var authenticated = false
    @Published var error: String?

    private let client = OBSClient()
    private var homeworkDetailRequestToken: UUID?
    private var examReportRequestToken: UUID?

    func start() async {
        isLoading = true
        error = nil
        if client.loadCookies() {
            authenticated = true
            await refresh()
        } else {
            authenticated = false
        }
        isLoading = false
    }

    func login() async {
        guard !username.isEmpty, !password.isEmpty else { return }
        isLoggingIn = true
        error = nil
        do {
            try await client.login(username: username, password: password)
            password = ""
            authenticated = true
            await refresh()
        } catch {
            self.error = error.localizedDescription
            print("[App] Login failed")
        }
        isLoggingIn = false
    }

    func refresh() async {
        guard authenticated else { return }
        var failures: [String] = []

        do {
            schedule = try await client.loadIndex()
        } catch {
            failures.append("Ders programı alınamadı.")
        }

        do {
            homework = try await client.loadHomework()
        } catch {
            failures.append("Ödevler alınamadı.")
        }

        do {
            examDashboard = try await client.loadStudentExams()
        } catch {
            failures.append("Sınavlar alınamadı.")
        }

        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    func loadHomeworkDetail(id: Int) async {
        let requestToken = UUID()
        homeworkDetailRequestToken = requestToken
        homeworkDetail = nil
        homeworkDetailError = nil
        isLoadingHomeworkDetail = true

        defer {
            if homeworkDetailRequestToken == requestToken {
                isLoadingHomeworkDetail = false
            }
        }

        do {
            let detail = try await client.loadHomeworkDetail(id: id)
            guard homeworkDetailRequestToken == requestToken else { return }
            homeworkDetail = detail
        } catch {
            guard homeworkDetailRequestToken == requestToken else { return }
            homeworkDetailError = error.localizedDescription
        }
    }

    func loadExamReport(examId: String) async {
        let requestToken = UUID()
        examReportRequestToken = requestToken
        examReport = nil
        examReportError = nil
        isLoadingExamReport = true
        defer {
            if examReportRequestToken == requestToken {
                isLoadingExamReport = false
            }
        }

        do {
            let report = try await client.loadSchoolReport(examId: examId)
            guard examReportRequestToken == requestToken else { return }
            examReport = report
        } catch {
            guard examReportRequestToken == requestToken else { return }
            examReportError = error.localizedDescription
        }
    }

    func openHomeworkFile(_ file: HomeworkFile) async throws -> URL {
        let fileManager = FileManager.default
        guard let downloadsDirectory = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw OBSClientError.invalidResponse("İndirilenler klasörü bulunamadı.")
        }
        try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)

        let requestedName = URL(fileURLWithPath: file.fileName).lastPathComponent
        let safeName = requestedName.isEmpty || requestedName == "/"
            ? "homework-\(file.fileId)"
            : requestedName
        let existingURL = downloadsDirectory.appendingPathComponent(safeName)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: existingURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            guard NSWorkspace.shared.open(existingURL) else {
                throw OBSClientError.invalidResponse("Dosya açılamadı: \(safeName)")
            }
            return existingURL
        }

        let data = try await client.downloadHomeworkFile(file)
        let originalURL = URL(fileURLWithPath: safeName)
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let fileExtension = originalURL.pathExtension
        var suffix = 1

        while true {
            let candidateName: String
            if suffix == 1 {
                candidateName = safeName
            } else if fileExtension.isEmpty {
                candidateName = "\(baseName) (\(suffix))"
            } else {
                candidateName = "\(baseName) (\(suffix)).\(fileExtension)"
            }
            let destination = downloadsDirectory.appendingPathComponent(candidateName)

            do {
                try data.write(to: destination, options: .withoutOverwriting)
                guard NSWorkspace.shared.open(destination) else {
                    throw OBSClientError.invalidResponse("Dosya indirildi ancak varsayılan uygulamayla açılamadı.")
                }
                return destination
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                suffix += 1
            }
        }
    }

    func logout() {
        authenticated = false
        schedule = nil
        homework = []
        examDashboard = nil
        examReport = nil
        examReportRequestToken = nil
        isLoadingExamReport = false
        examReportError = nil
        homeworkDetail = nil
        homeworkDetailRequestToken = nil
        isLoadingHomeworkDetail = false
        homeworkDetailError = nil
        username = ""
        password = ""
        error = nil
    }
}

struct HomeView: View {
    var body: some View {
        ContentUnavailableView("Ana Sayfa", systemImage: "house", description: Text("GöktürkOBS ana sayfası.")).navigationTitle("Ana Sayfa")
    }
}

struct HomeworkView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.homework.isEmpty {
                    ContentUnavailableView(
                        model.error == nil ? "Ödev yok" : "Ödevler alınamadı",
                        systemImage: "book",
                        description: Text(model.error ?? "Gösterilecek ödev bulunamadı.")
                    )
                } else {
                    List(model.homework) { item in
                        NavigationLink {
                            HomeworkDetailView(homework: item, model: model)
                        } label: {
                            HomeworkRowView(homework: item)
                        }
                    }
                }
            }
            .navigationTitle("Ödevler")
        }
    }
}

private struct HomeworkRowView: View {
    let homework: Homework

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(homework.title).font(.headline)
                Spacer()
                Text(homework.statusName).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(homework.lesson).font(.subheadline)
                Spacer()
                Text(homework.isActive ? "Aktif" : "Pasif")
                    .font(.caption)
                    .foregroundStyle(homework.isActive ? .green : .secondary)
            }
            Text(homework.teaNameSurname)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Label("Başlangıç: \(homework.startDate)", systemImage: "calendar")
                Spacer()
                Label("Bitiş: \(homework.endDate)", systemImage: "calendar.badge.clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusColor: Color {
        if homework.statusName == "Yapılmadı" {
            return .red
        }

        if !homework.isActive {
            return .gray
        }

        switch homework.statusName {
        case "Değerlendirilmedi":
            return .blue
        default:
            return .yellow
        }
    }
}

private struct HomeworkDetailView: View {
    let homework: Homework
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if let detail = model.homeworkDetail, detail.id == homework.id {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(detail.title).font(.title2.weight(.semibold))
                            LabeledContent("Ders", value: detail.lesson)
                            LabeledContent("Öğretmen", value: detail.teaNameSurname)
                            LabeledContent("Tür", value: detail.typeName)
                            LabeledContent("Başlangıç", value: detail.startDate)
                            LabeledContent("Bitiş", value: detail.endDate)
                            if let topic = detail.konuAd, !topic.isEmpty {
                                LabeledContent("Konu", value: topic)
                            }
                            LabeledContent("Durum", value: detail.statusName)
                            LabeledContent("Etkinlik", value: detail.isActive ? "Aktif" : "Pasif")
                            LabeledContent("Puan", value: detail.score)
                        }

                        if !detail.description.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Açıklama").font(.headline)
                                Text(detail.description)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if !detail.teacherComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Öğretmen yorumu").font(.headline)
                                Text(detail.teacherComment)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }

                        filesSection("Ödev ekleri", files: detail.attachFiles)
                        filesSection("Yüklediğim dosyalar", files: detail.studentAttachFiles)
                        filesSection("Cevap dosyaları", files: detail.answerFiles)
                    }
                    .padding(20)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if model.isLoadingHomeworkDetail {
                ProgressView("Ödev yükleniyor...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = model.homeworkDetailError {
                ContentUnavailableView("Ödev yüklenemedi", systemImage: "exclamationmark.triangle", description: Text(message))
            } else {
                ProgressView("Ödev yükleniyor...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(homework.title)
        .task(id: homework.id) {
            await model.loadHomeworkDetail(id: homework.id)
        }
    }

    private func filesSection(_ title: String, files: [HomeworkFile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if files.isEmpty {
                Text("Dosya yok").foregroundStyle(.secondary)
            } else {
                ForEach(files) { file in
                    HomeworkFileDownloadRow(file: file, model: model)
                }
            }
        }
    }
}

private struct HomeworkFileDownloadRow: View {
    let file: HomeworkFile
    @ObservedObject var model: AppModel
    @State private var isDownloading = false
    @State private var savedFilename: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(file.fileName.isEmpty ? "Dosya \(file.fileId)" : file.fileName, systemImage: "doc")
                    .textSelection(.enabled)
                Spacer()
                if isDownloading {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await download() }
                } label: {
                    Label("Aç / İndir", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.borderless)
                .disabled(isDownloading)
            }
            if let savedFilename {
                Label("Açıldı: \(savedFilename)", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 3)
    }

    @MainActor
    private func download() async {
        isDownloading = true
        savedFilename = nil
        errorMessage = nil
        defer { isDownloading = false }

        do {
            let url = try await model.openHomeworkFile(file)
            savedFilename = url.lastPathComponent
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum AppSection: Hashable {
    case home
    case schedule
    case exams
    case homework
}

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var selection: AppSection? = .schedule

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("Ana Sayfa", systemImage: "house").tag(AppSection.home)
                    Label("Ders Programı", systemImage: "calendar").tag(AppSection.schedule)
                    Label("Sınavlar", systemImage: "pencil").tag(AppSection.exams)
                    Label("Ödevler", systemImage: "book").tag(AppSection.homework)
                }
            }.navigationTitle("GöktürkOBS")
        } detail: {
            Group {
                switch selection {
                case .home:
                    HomeView()
                case .schedule:
                    if let schedule = model.schedule {
                        ScheduleView(schedule: schedule) {
                            Task { await model.refresh() }
                        }
                    } else {
                        ContentUnavailableView(
                            "Ders programı yok",
                            systemImage: "calendar",
                            description: Text(model.error ?? "Gösterilecek ders programı bulunamadı.")
                        )
                    }
                case .exams:
                    ExamsView(model: model)
                case .homework:
                    HomeworkView(model: model)
                case nil:
                    ContentUnavailableView("Bir bölüm seçin", systemImage: "sidebar.left")
                }
            }.toolbar {
                ToolbarItemGroup(placement: .secondaryAction) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("Yenile", systemImage: "arrow.clockwise")
                    }
                    Button { model.logout() } label: {
                        Label("Çıkış Yap", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        }
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if model.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("GöktürkOBS başlatılıyor...").foregroundStyle(.secondary)
                }
            } else if model.authenticated {
                MainView(model: model)
            } else {
                LoginView(model: model)
            }
        }
    }
}

@main
struct GokturkOBSApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model).task {
                NSApplication.shared.activate(ignoringOtherApps: true)
                await model.start()
            }
        }
        .windowResizability(.automatic)
    }
}
