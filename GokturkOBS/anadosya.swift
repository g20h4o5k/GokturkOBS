import SwiftUI
import Foundation
import AppKit
import PDFKit
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
    @Published var foodListState: FoodListLoadState = .idle
    @Published var studentProfile: StudentProfile?
    @Published var studentProfileImage: NSImage?
    @Published var isLoadingStudentProfile = false
    @Published var isLoading = true
    @Published var isLoggingIn = false
    @Published var authenticated = false
    @Published var error: String?
    @Published var rememberMe = UserDefaults.standard.bool(forKey: "rememberMe") {
        didSet {
            UserDefaults.standard.set(rememberMe, forKey: "rememberMe")
            guard !rememberMe else { return }
            do {
                try keychain.delete()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private let client = OBSClient()
    private let keychain = KeychainService()
    private var homeworkDetailRequestToken: UUID?
    private var examReportRequestToken: UUID?
    private var hasAttemptedStudentProfileLoad = false
    private var hasStarted = false
    private var attemptedRememberedLogin = false

    func start() async {
        guard !hasStarted else {
            isLoading = false
            return
        }
        hasStarted = true
        isLoading = true
        error = nil
        if client.loadCookies() {
            do {
                schedule = try await client.loadIndex()
                authenticated = true
                await refresh()
            } catch OBSClientError.sessionExpired {
                do {
                    try client.clearCookies()
                    await attemptRememberedLogin()
                } catch {
                    self.error = error.localizedDescription
                }
            } catch {
                authenticated = false
                self.error = networkErrorMessage(for: error)
            }
        } else {
            authenticated = false
            await attemptRememberedLogin()
        }
        isLoading = false
    }

    func login() async {
        guard !username.isEmpty, !password.isEmpty else { return }
        isLoggingIn = true
        error = nil
        let submittedUsername = username
        let submittedPassword = password
        do {
            try await client.login(username: submittedUsername, password: submittedPassword)
            var credentialError: String?
            do {
                if rememberMe {
                    try keychain.save(username: submittedUsername, password: submittedPassword)
                } else {
                    try keychain.delete()
                }
            } catch {
                credentialError = error.localizedDescription
            }
            password = ""
            authenticated = true
            await refresh()
            if let credentialError {
                error = credentialError
            }
        } catch {
            self.error = networkErrorMessage(for: error)
            print("[App] Login failed")
        }
        isLoggingIn = false
    }

    func prepareRememberedUsername() {
        guard rememberMe else { return }
        do {
            if let credentials = try keychain.load(), username.isEmpty {
                username = credentials.username
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func attemptRememberedLogin() async {
        guard rememberMe, !attemptedRememberedLogin else { return }
        attemptedRememberedLogin = true
        do {
            guard let credentials = try keychain.load() else { return }
            username = credentials.username
            try await client.login(username: credentials.username, password: credentials.password)
            schedule = try await client.loadIndex()
            authenticated = true
            await refresh()
        } catch {
            authenticated = false
            do {
                try client.clearCookies()
            } catch {
                self.error = error.localizedDescription
                return
            }
            self.error = networkErrorMessage(for: error)
        }
    }

    private func networkErrorMessage(for error: Error) -> String {
        if let clientError = error as? OBSClientError, case .serverError = clientError {
            return "OBS sunucusuna ulaşılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin."
        }
        if error is URLError {
            return "OBS sunucusuna ulaşılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin."
        }
        return error.localizedDescription
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

    func loadSidebarProfile() async {
        guard authenticated,
              !isLoadingStudentProfile,
              !hasAttemptedStudentProfileLoad else {
            return
        }

        hasAttemptedStudentProfileLoad = true
        isLoadingStudentProfile = true
        defer {
            isLoadingStudentProfile = false
        }

        do {
            let profile = try await client.loadStudentProfile()
            studentProfile = profile
            do {
                studentProfileImage = try await client.loadStudentProfileImage(for: profile)
            } catch {
                studentProfileImage = nil
            }
        } catch {
            studentProfile = nil
            studentProfileImage = nil
        }
    }

    func loadFoodList(forceReload: Bool = false) async {
        if !forceReload {
            switch foodListState {
            case .loading, .loaded, .empty:
                return
            case .idle, .error:
                break
            }
        }

        foodListState = .loading
        do {
            switch try await client.loadFoodList() {
            case .pdf(let data):
                guard let document = PDFDocument(data: data) else {
                    throw OBSClientError.invalidResponse("Yemek listesi geçerli bir PDF dosyası değil.")
                }
                foodListState = .loaded(document)
            case .empty:
                foodListState = .empty
            }
        } catch {
            foodListState = .error(networkErrorMessage(for: error))
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
        error = nil
        do {
            try client.clearCookies()
        } catch {
            self.error = error.localizedDescription
        }
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
        foodListState = .idle
        studentProfile = nil
        studentProfileImage = nil
        isLoadingStudentProfile = false
        hasAttemptedStudentProfileLoad = false
        username = ""
        password = ""
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
    case foodList
    case profile
}

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var selection: AppSection? = .schedule

    var body: some View {
        NavigationSplitView {
            AppSidebarView(
                selection: $selection,
                profile: model.studentProfile,
                profileImage: model.studentProfileImage,
                isLoadingProfile: model.isLoadingStudentProfile
            ) {
                selection = .profile
            }
            .navigationTitle("GöktürkOBS")
            .task {
                await model.loadSidebarProfile()
            }
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
                case .foodList:
                    FoodListView(model: model)
                case .profile:
                    ProfileDetailView(
                        profile: model.studentProfile,
                        image: model.studentProfileImage
                    )
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
