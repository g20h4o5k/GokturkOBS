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
    @Published var taramalar: [TaramaExam] = []
    @Published var taramaDetail: TaramaDetail?
    @Published var taramaSubjectAnalysis: [TaramaSubjectAnalysis] = []
    @Published var isLoadingTaramalar = false
    @Published var isLoadingTaramaDetail = false
    @Published var isLoadingTaramaAnalysis = false
    @Published var taramalarError: String?
    @Published var taramaDetailError: String?
    @Published var taramaAnalysisError: String?
    @Published var homeworkDetail: HomeworkDetail?
    @Published var isLoadingHomeworkDetail = false
    @Published var homeworkDetailError: String?
    @Published var foodListState: FoodListLoadState = .idle
    @Published var foodListSelectedDayID: FoodMenuDay.ID?
    @Published var isLoadingSchedule = true
    @Published var isLoadingHomework = true
    @Published var isLoadingExams = true
    @Published var scheduleError: String?
    @Published var homeworkError: String?
    @Published var examsError: String?
    @Published var studentProfile: StudentProfile?
    @Published var studentProfileImage: NSImage?
    @Published var isLoadingStudentProfile = false
    @Published var isLoading = true
    @Published var isLoggingIn = false
    @Published var youAreCooked = true
    @Published var authenticated = false
    @Published var error: String?
    @Published var isScreenshotMode = UserDefaults.standard.bool(forKey: "isScreenshotMode") {
        didSet {
            UserDefaults.standard.set(isScreenshotMode, forKey: "isScreenshotMode")
        }
    }
    @Published var rememberMe = UserDefaults.standard.bool(forKey: "rememberMe") {
        didSet {
            UserDefaults.standard.set(rememberMe, forKey: "rememberMe")
            if rememberMe {
                configureAutomaticRecovery()
                return
            }
            client.disableRecovery()
            do {
                try keychain.delete()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    let client = OBSClient()
    private let keychain = KeychainService()
    private var homeworkDetailRequestToken: UUID?
    private var examReportRequestToken: UUID?
    private var taramalarRequestToken: UUID?
    private var taramaDetailRequestToken: UUID?
    private var taramaAnalysisRequestToken: UUID?
    private var loadedTaramaDetailCode: String?
    private var loadedTaramaAnalysisCode: String?
    private var hasAttemptedStudentProfileLoad = false
    private var hasStarted = false
    private var attemptedRememberedLogin = false
    private var foodPhotoPrefetchTask: Task<Void, Never>?

    init() {
        configureAutomaticRecovery()
    }

    private func configureAutomaticRecovery() {
        guard !UserDefaults.standard.bool(forKey: "didManuallyLogout") else {
            client.disableRecovery()
            return
        }
        client.configureRecovery { [weak self] in
            guard let self, self.rememberMe else { return nil }
            return try self.keychain.load()
        }
    }

    func start() async {
        guard !hasStarted else {
            isLoading = false
            return
        }
        hasStarted = true
        configureAutomaticRecovery()
        isLoading = true
        error = nil
        if client.loadCookies() {
            do {
                schedule = try await client.loadIndex()
                authenticated = true
                if rememberMe, let credentials = try? keychain.load() {
                    do {
                        try await client.refreshMobileProfile(
                            username: credentials.username,
                            password: credentials.password
                        )
                    } catch {
                        print("[App] Mobile profile refresh failed; continuing with PHP session")
                    }
                }
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
            UserDefaults.standard.set(false, forKey: "didManuallyLogout")
            configureAutomaticRecovery()
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
            if case OBSClientError.loginFailed = error {
                do {
                    try client.clearCookies()
                } catch {
                    self.error = error.localizedDescription
                    return
                }
            }
            self.error = networkErrorMessage(for: error)
        }
    }

    private func networkErrorMessage(for error: Error) -> String {
        if case OBSClientError.recoveryUnavailable = error {
            return "Oturum yenilenemedi. Lütfen tekrar giriş yapın."
        }
        if case OBSClientError.loginFailed = error {
            return "Oturum yenilenemedi. Lütfen tekrar giriş yapın."
        }
        if case OBSClientError.temporaryServer = error {
            return "OBS sunucusuna ulaşılamıyor."
        }
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

        isLoadingSchedule = true
        scheduleError = nil
        do {
            schedule = try await client.loadIndex()
        } catch {
            if requiresExplicitLogin(after: error) {
                isLoadingSchedule = false
                authenticated = false
                self.error = "Oturum yenilenemedi. Lütfen tekrar giriş yapın."
                return
            }
            scheduleError = networkErrorMessage(for: error)
            failures.append("Ders programı alınamadı.")
        }
        isLoadingSchedule = false

        isLoadingHomework = true
        homeworkError = nil
        do {
            homework = try await client.loadHomework()
        } catch {
            homeworkError = networkErrorMessage(for: error)
            failures.append("Ödevler alınamadı.")
        }
        isLoadingHomework = false

        isLoadingExams = true
        examsError = nil
        do {
            examDashboard = try await client.loadStudentExams()
        } catch {
            if requiresExplicitLogin(after: error) {
                isLoadingExams = false
                authenticated = false
                self.error = "Oturum yenilenemedi. Lütfen tekrar giriş yapın."
                return
            }
            examsError = networkErrorMessage(for: error)
            failures.append("Sınavlar alınamadı.")
        }
        isLoadingExams = false

        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    func refreshHome(forceReload: Bool = false) async {
        guard authenticated else { return }
        if forceReload || schedule == nil || examDashboard == nil || homeworkError != nil {
            await refresh()
        }
        await loadFoodList(forceReload: forceReload)
    }

    func retryWithAutomaticLogin() async {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        error = nil
        defer { isLoggingIn = false }

        do {
            guard let credentials = try keychain.load() else {
                throw OBSClientError.recoveryUnavailable
            }
            try await client.login(
                username: credentials.username,
                password: credentials.password
            )
            authenticated = true
            UserDefaults.standard.set(false, forKey: "didManuallyLogout")
            configureAutomaticRecovery()

            hasAttemptedStudentProfileLoad = false
            studentProfile = nil
            studentProfileImage = nil
            await refreshHome(forceReload: true)
            await loadSidebarProfile()
        } catch {
            self.error = networkErrorMessage(for: error)
        }
    }

    private func requiresExplicitLogin(after error: Error) -> Bool {
        guard let clientError = error as? OBSClientError else { return false }
        switch clientError {
        case .sessionExpired, .recoveryUnavailable, .loginFailed:
            return true
        case .serverError, .temporaryServer, .invalidResponse:
            return false
        }
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
            let profile = try await client.loadCompleteStudentProfile()
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
                let days = FoodMenuParser.parse(document)
                foodListState = .loaded(document, days)
                startFoodPhotoPrefetch(for: days)
            case .empty:
                foodPhotoPrefetchTask?.cancel()
                foodListState = .empty
            }
        } catch {
            foodListState = .error(networkErrorMessage(for: error))
        }
    }

    private func startFoodPhotoPrefetch(for days: [FoodMenuDay]) {
        foodPhotoPrefetchTask?.cancel()
        let schoolDayEnded = schedule.map {
            ScheduleDashboardResolver.hasSchoolDayEnded(in: $0)
        } ?? false
        guard let day = FoodDashboardResolver.currentOrNextMeal(
            in: days,
            beginWithNextDay: schoolDayEnded
        )?.day else {
            foodPhotoPrefetchTask = nil
            return
        }

        let mealNames = day.items
        let menuDayID = day.id
        foodPhotoPrefetchTask = Task(priority: .utility) {
            await prefetchFoodPhotos(for: mealNames, menuDayID: menuDayID)
        }
    }

    func loadExamReport(examId: String, examType: String) async {
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
            let report = try await client.loadSchoolReport(examId: examId, examType: examType)
            guard examReportRequestToken == requestToken else { return }
            examReport = report
        } catch {
            guard examReportRequestToken == requestToken else { return }
            examReportError = error.localizedDescription
        }
    }

    func loadTaramalar(forceReload: Bool = false) async {
        guard forceReload || (taramalar.isEmpty && !isLoadingTaramalar) else { return }
        let requestToken = UUID()
        taramalarRequestToken = requestToken
        taramalarError = nil
        isLoadingTaramalar = true
        defer {
            if taramalarRequestToken == requestToken { isLoadingTaramalar = false }
        }

        do {
            let loaded = try await client.loadTaramalar()
            guard taramalarRequestToken == requestToken, !Task.isCancelled else { return }
            taramalar = Self.sortTaramalar(loaded)
        } catch {
            guard taramalarRequestToken == requestToken, !Task.isCancelled else { return }
            taramalarError = taramaErrorMessage(error, fallback: "Tarama sonuçları alınamadı.")
        }
    }

    func loadTaramaDetail(examCode: String) async {
        if loadedTaramaDetailCode == examCode, taramaDetail != nil { return }
        let requestToken = UUID()
        taramaDetailRequestToken = requestToken
        loadedTaramaDetailCode = nil
        loadedTaramaAnalysisCode = nil
        taramaDetail = nil
        taramaSubjectAnalysis = []
        taramaDetailError = nil
        taramaAnalysisError = nil
        isLoadingTaramaDetail = true
        defer {
            if taramaDetailRequestToken == requestToken { isLoadingTaramaDetail = false }
        }

        do {
            let detail = try await client.loadTaramaDetail(examCode: examCode)
            guard taramaDetailRequestToken == requestToken, !Task.isCancelled else { return }
            taramaDetail = detail
            loadedTaramaDetailCode = examCode
        } catch {
            guard taramaDetailRequestToken == requestToken, !Task.isCancelled else { return }
            taramaDetailError = taramaErrorMessage(error, fallback: "Tarama detayları yüklenemedi.")
        }
    }

    func loadTaramaSubjectAnalysis(examCode: String, forceReload: Bool = false) async {
        guard forceReload || loadedTaramaAnalysisCode != examCode else { return }
        guard !isLoadingTaramaAnalysis else { return }
        let requestToken = UUID()
        taramaAnalysisRequestToken = requestToken
        taramaAnalysisError = nil
        isLoadingTaramaAnalysis = true
        defer {
            if taramaAnalysisRequestToken == requestToken { isLoadingTaramaAnalysis = false }
        }

        do {
            let analysis = try await client.loadTaramaSubjectAnalysis(examCode: examCode)
            guard taramaAnalysisRequestToken == requestToken, !Task.isCancelled else { return }
            taramaSubjectAnalysis = analysis
            loadedTaramaAnalysisCode = examCode
        } catch {
            guard taramaAnalysisRequestToken == requestToken, !Task.isCancelled else { return }
            taramaAnalysisError = taramaErrorMessage(error, fallback: "Kazanım analizi yüklenemedi.")
        }
    }

    private func taramaErrorMessage(_ error: Error, fallback: String) -> String {
        if let clientError = error as? OBSClientError {
            switch clientError {
            case .sessionExpired, .recoveryUnavailable, .loginFailed:
                return "Mobil OBS oturumu yenilenemedi. Lütfen yeniden giriş yapın."
            case .invalidResponse(let message):
                return message
            case .serverError, .temporaryServer:
                return clientError.localizedDescription
            }
        }
        if error is CancellationError { return fallback }
        return error.localizedDescription
    }

    private static func sortTaramalar(_ exams: [TaramaExam]) -> [TaramaExam] {
        let formats = ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd", "dd.MM.yyyy", "dd/MM/yyyy"]
        let locale = Locale(identifier: "tr_TR")
        func date(_ text: String?) -> Date? {
            guard let text else { return nil }
            for format in formats {
                let formatter = DateFormatter()
                formatter.locale = locale
                formatter.dateFormat = format
                if let value = formatter.date(from: text) { return value }
            }
            return nil
        }
        return exams.enumerated().sorted { lhs, rhs in
            switch (date(lhs.element.date), date(rhs.element.date)) {
            case let (left?, right?): return left == right ? lhs.offset < rhs.offset : left > right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }.map(\.element)
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
        UserDefaults.standard.set(true, forKey: "didManuallyLogout")
        client.disableRecovery()
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
        isLoadingSchedule = true
        isLoadingHomework = true
        isLoadingExams = true
        scheduleError = nil
        homeworkError = nil
        examsError = nil
        examReport = nil
        examReportRequestToken = nil
        isLoadingExamReport = false
        examReportError = nil
        taramalar = []
        taramaDetail = nil
        taramaSubjectAnalysis = []
        taramalarRequestToken = nil
        taramaDetailRequestToken = nil
        taramaAnalysisRequestToken = nil
        loadedTaramaDetailCode = nil
        loadedTaramaAnalysisCode = nil
        isLoadingTaramalar = false
        isLoadingTaramaDetail = false
        isLoadingTaramaAnalysis = false
        taramalarError = nil
        taramaDetailError = nil
        taramaAnalysisError = nil
        homeworkDetail = nil
        homeworkDetailRequestToken = nil
        isLoadingHomeworkDetail = false
        homeworkDetailError = nil
        foodPhotoPrefetchTask?.cancel()
        foodPhotoPrefetchTask = nil
        foodListState = .idle
        foodListSelectedDayID = nil
        studentProfile = nil
        studentProfileImage = nil
        isLoadingStudentProfile = false
        hasAttemptedStudentProfileLoad = false
        username = ""
        password = ""
    }
}

struct HomeworkView: View {
    @ObservedObject var model: AppModel
    @State private var selectedHomework: Homework?

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
                        Button {
                            selectedHomework = item
                        } label: {
                            HomeworkRowView(homework: item)
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Ödevler")
            .sheet(item: $selectedHomework) { homework in
                HomeworkDetailSheet(homework: homework, model: model)
            }
        }
    }
}

private struct HomeworkDetailSheet: View {
    let homework: Homework
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text("Ödev Ayrıntısı")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.bar)

            Divider()

            HomeworkDetailView(homework: homework, model: model)

            Divider()

            HStack {
                Spacer()
                Button("Bitti") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.bar)
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 520, idealHeight: 680)
    }
}

private struct HomeworkRowView: View {
    let homework: Homework

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(homework.title).font(.headline)
                Spacer()
                Text(homework.statusName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            statusColor.opacity(0.22),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(statusColor.opacity(0.60), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ödev ayrıntılarını açar")
    }

    private var statusColor: Color {
        let normalizedStatus = homework.statusName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "tr_TR"))

        if normalizedStatus.contains("değerlendirilmedi") || normalizedStatus.contains("değelendirilmedi") {
            return hasDeadlinePassed ? .green : .gray
        }
        if normalizedStatus.contains("yapılmadı") {
            return .red
        }
        if normalizedStatus.contains("eksik") {
            return .yellow
        }
        if normalizedStatus.contains("yapıldı")
            || normalizedStatus.contains("tamamlandı")
            || normalizedStatus.contains("teslim edildi") {
            return .green
        }
        return .gray
    }

    private var hasDeadlinePassed: Bool {
        guard let endDate = parsedEndDate else { return false }

        if homework.endDate.contains(":") {
            return endDate < Date()
        }
        return endDate < Calendar.current.startOfDay(for: Date())
    }

    private var parsedEndDate: Date? {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss",
            "dd.MM.yyyy HH:mm",
            "dd/MM/yyyy HH:mm",
            "yyyy-MM-dd",
            "dd.MM.yyyy",
            "dd/MM/yyyy"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR_POSIX")

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: homework.endDate) {
                return date
            }
        }
        return nil
    }
}

private struct HomeworkDetailView: View {
    let homework: Homework
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if let detail = model.homeworkDetail, detail.id == homework.id {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "book.closed.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 46, height: 46)
                                .background(.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(detail.title)
                                    .font(.title2.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Label(detail.lesson, systemImage: "graduationcap")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 12)

                            Text(detail.statusName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(statusTint(for: detail.statusName))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    statusTint(for: detail.statusName).opacity(0.15),
                                    in: Capsule()
                                )
                        }
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 190), spacing: 10)],
                            alignment: .leading,
                            spacing: 10
                        ) {
                            detailItem("Öğretmen", value: detail.teaNameSurname, icon: "person.fill")
                            detailItem("Başlangıç", value: detail.startDate, icon: "calendar")
                            detailItem("Bitiş", value: detail.endDate, icon: "calendar.badge.clock")
                            detailItem("Tür", value: detail.typeName, icon: "tag.fill")
                            if let topic = detail.konuAd, !topic.isEmpty {
                                detailItem("Konu", value: topic, icon: "text.book.closed.fill")
                            }
                            if !detail.score.isEmpty, detail.score != "-" {
                                detailItem("Puan", value: detail.score, icon: "star.fill")
                            }
                            detailItem(
                                "Etkinlik",
                                value: detail.isActive ? "Aktif" : "Pasif",
                                icon: detail.isActive ? "checkmark.circle.fill" : "minus.circle.fill"
                            )
                        }

                        if !detail.description.isEmpty {
                            GroupBox {
                                Text(detail.description)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                            } label: {
                                Label("Açıklama", systemImage: "text.alignleft")
                                    .font(.headline)
                            }
                        }

                        if !detail.teacherComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            GroupBox {
                                Text(detail.teacherComment)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                            } label: {
                                Label("Öğretmen yorumu", systemImage: "quote.bubble.fill")
                                    .font(.headline)
                            }
                        }

                        filesSection("Ödev ekleri", files: detail.attachFiles)
                        filesSection("Yüklediğim dosyalar", files: detail.studentAttachFiles)
                        filesSection("Cevap dosyaları", files: detail.answerFiles)
                    }
                    .padding(20)
                    .frame(maxWidth: 720, alignment: .leading)
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
        .task(id: homework.id) {
            await model.loadHomeworkDetail(id: homework.id)
        }
    }

    private func detailItem(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value.isEmpty ? "—" : value)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func filesSection(_ title: String, files: [HomeworkFile]) -> some View {
        GroupBox {
            if files.isEmpty {
                Label("Dosya bulunmuyor", systemImage: "tray")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(files) { file in
                        HomeworkFileDownloadRow(file: file, model: model)
                    }
                }
            }
        } label: {
            Label(title, systemImage: "paperclip")
                .font(.headline)
        }
    }

    private func statusTint(for status: String) -> Color {
        let normalizedStatus = status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "tr_TR"))

        if normalizedStatus.contains("yapılmadı") { return .red }
        if normalizedStatus.contains("eksik") { return .yellow }
        if normalizedStatus.contains("yapıldı")
            || normalizedStatus.contains("tamamlandı")
            || normalizedStatus.contains("teslim edildi") {
            return .green
        }
        return .secondary
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
        .padding(10)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
    case practiceExams
    case taramalar
    case homework
    case foodList
    case messages
    case attendance
    case teachers
    case announcements
    case events
    case profile
}

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var selection: AppSection? = .home

    var body: some View {
        GeometryReader { proxy in
            let maximumSidebarWidth = min(320, max(180, proxy.size.width * 0.34))
            let idealSidebarWidth = min(sidebarContentWidth, maximumSidebarWidth)

            NavigationSplitView {
            AppSidebarView(
                selection: $selection,
                profile: model.studentProfile,
                profileImage: model.studentProfileImage,
                isLoadingProfile: model.isLoadingStudentProfile,
                isScreenshotMode: $model.isScreenshotMode
            ) {
                selection = .profile
            }
            .navigationTitle("GöktürkOBS")
            .task {
                await model.loadSidebarProfile()
            }
            .navigationSplitViewColumnWidth(
                min: 180,
                ideal: idealSidebarWidth,
                max: maximumSidebarWidth
            )
            } detail: {
            Group {
                if selection == .home {
                    HomeDashboardView(model: model, selection: $selection)
                } else if model.isScreenshotMode {
                    ScreenshotProtectedSectionView(section: selection)
                } else {
                    switch selection {
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
                    case .practiceExams:
                        ExamsView(model: model)
                    case .taramalar:
                        TaramalarView(model: model)
                    case .homework:
                        HomeworkView(model: model)
                    case .foodList:
                        FoodListView(model: model)
                    case .messages:
                        MessagesView(client: model.client)
                    case .attendance:
                        AttendanceView(client: model.client)
                    case .teachers:
                        TeachersView(client: model.client)
                    case .announcements:
                        AnnouncementsView(client: model.client)
                    case .events:
                        EventsView(client: model.client)
                    case .profile:
                        ProfileDetailView(
                            profile: model.studentProfile,
                            image: model.studentProfileImage
                        )
                    case .home:
                        EmptyView()
                    case nil:
                        ContentUnavailableView("Bir bölüm seçin", systemImage: "sidebar.left")
                    }
                }
            }.toolbar {
                ToolbarItemGroup(placement: .secondaryAction) {
                    Button {
                        Task { await model.retryWithAutomaticLogin() }
                    } label: {
                        Label("Yeniden Dene", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isLoggingIn)
                    Button { model.logout() } label: {
                        Label("Çıkış Yap", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            }
            .navigationSplitViewStyle(.balanced)
        }
    }

    private var sidebarContentWidth: CGFloat {
        let nameLength = model.isScreenshotMode ? 0 : model.studentProfile?.name.count ?? 0
        return min(300, 215 + CGFloat(max(nameLength - 14, 0)) * 5.5)
    }
}

private struct ScreenshotProtectedSectionView: View {
    let section: AppSection?

    var body: some View {
        ContentUnavailableView {
            Label(sectionTitle, systemImage: sectionImage)
        } description: {
            Text("Ekran görüntüsü modu açıkken kişisel bilgiler gizlenir.")
        }
        .navigationTitle(sectionTitle)
    }

    private var sectionTitle: String {
        switch section {
        case .schedule: "Ders Programı"
        case .practiceExams: "Deneme Sınavları"
        case .taramalar: "Taramalar"
        case .homework: "Ödevler"
        case .foodList: "Yemek Listesi"
        case .messages: "Mesajlar"
        case .attendance: "Devamsızlık"
        case .teachers: "Öğretmenlerim"
        case .announcements: "Duyurular"
        case .events: "Etkinlikler"
        case .profile: "Profil"
        case .home: "Ana Sayfa"
        case nil: "Bölüm"
        }
    }

    private var sectionImage: String {
        switch section {
        case .schedule: "calendar"
        case .practiceExams: "doc.text"
        case .taramalar: "checklist"
        case .homework: "book"
        case .foodList: "fork.knife"
        case .messages: "envelope"
        case .attendance: "calendar.badge.exclamationmark"
        case .teachers: "person.2"
        case .announcements: "megaphone"
        case .events: "calendar.day.timeline.left"
        case .profile: "person.crop.circle"
        case .home: "house"
        case nil: "eye.slash"
        }
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue

    var body: some View {
        Group {
            if model.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("i am groot").foregroundStyle(.secondary)
                }
            } else if model.authenticated {
                MainView(model: model)
            } else {
                LoginView(model: model)
            }
        }
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
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
        .windowResizability(.contentMinSize)
    }
}
