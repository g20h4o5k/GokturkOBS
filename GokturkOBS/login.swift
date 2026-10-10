import SwiftUI
import Foundation
import AppKit
import Security

struct LoginResponse: Decodable {
    let success: Bool
    let msg: String?
}

private struct MobileLoginRequest: Encodable {
    let loginAs = "standard"
    let username: String
    let password: String
}

private struct MobileLoginResponse: Decodable {
    let success: Bool
    let msg: String?
    let status: String?
    let userInfo: MobileUserInfo?

    private enum CodingKeys: String, CodingKey {
        case success, msg, status, userInfo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeFlexibleBool(forKey: .success) ?? false
        msg = try container.decodeFlexibleString(forKey: .msg)
        status = try container.decodeFlexibleString(forKey: .status)
        userInfo = try container.decodeIfPresent(MobileUserInfo.self, forKey: .userInfo)
    }
}

private struct MobileUserInfo: Decodable {
    let profilePhoto: String?
    let stuNo: String?
    let classId: String?
    let name: String?
    let surname: String?
    let nameSurname: String?
    let fullName: String?
    let studentName: String?
    let studentNameSurname: String?
    let stuName: String?
    let stuSurname: String?
    let userName: String?
    let userSurname: String?
    let firstName: String?
    let lastName: String?

    private enum CodingKeys: String, CodingKey {
        case profilePhoto, stuNo, classId, name, surname, nameSurname, fullName
        case studentName, studentNameSurname, stuName, stuSurname
        case userName, userSurname, firstName, lastName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profilePhoto = try container.decodeFlexibleString(forKey: .profilePhoto)
        stuNo = try container.decodeFlexibleString(forKey: .stuNo)
        classId = try container.decodeFlexibleString(forKey: .classId)
        name = try container.decodeFlexibleString(forKey: .name)
        surname = try container.decodeFlexibleString(forKey: .surname)
        nameSurname = try container.decodeFlexibleString(forKey: .nameSurname)
        fullName = try container.decodeFlexibleString(forKey: .fullName)
        studentName = try container.decodeFlexibleString(forKey: .studentName)
        studentNameSurname = try container.decodeFlexibleString(forKey: .studentNameSurname)
        stuName = try container.decodeFlexibleString(forKey: .stuName)
        stuSurname = try container.decodeFlexibleString(forKey: .stuSurname)
        userName = try container.decodeFlexibleString(forKey: .userName)
        userSurname = try container.decodeFlexibleString(forKey: .userSurname)
        firstName = try container.decodeFlexibleString(forKey: .firstName)
        lastName = try container.decodeFlexibleString(forKey: .lastName)
    }

    nonisolated var displayName: String? {
        let directCandidates = [nameSurname, fullName, studentNameSurname, studentName]
        if let directName = directCandidates.compactMap(Self.nonEmpty).first {
            return directName
        }

        let givenName = Self.nonEmpty(name) ?? Self.nonEmpty(stuName) ?? Self.nonEmpty(userName) ?? Self.nonEmpty(firstName)
        let familyName = Self.nonEmpty(surname) ?? Self.nonEmpty(stuSurname) ?? Self.nonEmpty(userSurname) ?? Self.nonEmpty(lastName)
        let combined = [givenName, familyName].compactMap { $0 }.joined(separator: " ")
        return Self.nonEmpty(combined)
    }

    private nonisolated static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleString(forKey key: Key) throws -> String? {
        guard contains(key) else { return nil }
        if try decodeNil(forKey: key) { return nil }
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        if let value = try? decode(Bool.self, forKey: key) { return String(value) }
        return nil
    }

    func decodeFlexibleBool(forKey key: Key) throws -> Bool? {
        guard contains(key) else { return nil }
        if try decodeNil(forKey: key) { return nil }
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return value != 0 }
        if let value = try? decode(String.self, forKey: key) {
            return ["true", "1", "success", "ok"].contains(value.lowercased())
        }
        return nil
    }
}

enum OBSClientError: LocalizedError {
    case serverError
    case temporaryServer(statusCode: Int, retryAfter: TimeInterval?)
    case loginFailed(String)
    case sessionExpired
    case recoveryUnavailable
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .serverError: return "OBS sunucusuna ulaşılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin."
        case .temporaryServer: return "OBS sunucusuna ulaşılamıyor."
        case .loginFailed(let message): return message
        case .sessionExpired: return "OBS oturumu geçersiz."
        case .recoveryUnavailable: return "Oturum yenilenemedi. Lütfen tekrar giriş yapın."
        case .invalidResponse(let message): return message
        }
    }
}

enum OBSSessionKind {
    case web
    case mobile
}

@MainActor
final class OBSClient {
    var currentCookieHeader: String?
    private(set) var studentProfile: StudentProfile?
    private var cachedStudentProfileImage: NSImage?
    private var studentProfileTask: Task<StudentProfile, Error>?
    private var mobileAuthenticated = false
    private var credentialProvider: (() throws -> StoredCredentials?)?
    private var webRecovery: (id: UUID, task: Task<Void, Error>)?
    private var mobileRecovery: (id: UUID, task: Task<Void, Error>)?

    private func verbose(_ message: String) { print("[OBS DEBUG] \(message)") }

    lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()

    private lazy var mobileSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        return URLSession(configuration: configuration)
    }()

    func configureRecovery(credentialProvider: @escaping () throws -> StoredCredentials?) {
        self.credentialProvider = credentialProvider
    }

    func disableRecovery() {
        credentialProvider = nil
        webRecovery?.task.cancel()
        mobileRecovery?.task.cancel()
        webRecovery = nil
        mobileRecovery = nil
    }

    private func cookieFileURL() -> URL {
        let fileManager = FileManager.default
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = applicationSupport
            .appendingPathComponent("GokturkOBS", isDirectory: true)
            .appendingPathComponent("Session", isDirectory: true)
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory.appendingPathComponent("obs-cookies.txt")
    }

    private func legacyCookieFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("GokturkOBS", isDirectory: true)
            .appendingPathComponent("obs-cookies.txt")
    }

    func clearCookies() throws {
        currentCookieHeader = nil
        studentProfile = nil
        cachedStudentProfileImage = nil
        mobileAuthenticated = false
        studentProfileTask?.cancel()
        studentProfileTask = nil
        let url = cookieFileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let legacyURL = legacyCookieFileURL()
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            try FileManager.default.removeItem(at: legacyURL)
        }
    }

    private func captureCookies(from response: HTTPURLResponse) {
        guard let setCookie = response.value(forHTTPHeaderField: "Set-Cookie") else {
            verbose("Response'ta Set-Cookie yok")
            return
        }
        verbose("Set-Cookie header present")
        let parsedCookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": setCookie], for: response.url ?? baseURL)
        guard !parsedCookies.isEmpty else {
            verbose("Set-Cookie parse edilemedi")
            return
        }

        var cookiesByName: [String: String] = [:]
        if let existing = currentCookieHeader {
            for part in existing.split(separator: ";") {
                let pieces = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
                guard pieces.count == 2 else { continue }
                cookiesByName[String(pieces[0])] = String(pieces[1])
            }
        }
        for cookie in parsedCookies {
            cookiesByName[cookie.name] = cookie.value
        }
        currentCookieHeader = cookiesByName.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")
        verbose("Session cookies updated: \(cookiesByName.count)")
    }

    private func saveCookies() {
        guard let cookieHeader = currentCookieHeader, !cookieHeader.isEmpty else { return }
        var output = """
        # Netscape HTTP Cookie File
        # Generated by GöktürkOBS

        """
        for part in cookieHeader.split(separator: ";") {
            let pieces = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            guard pieces.count == 2 else { continue }
            output += "tedemkolejiobs.com\tFALSE\t/\tFALSE\t0\t\(pieces[0])\t\(pieces[1])\n"
        }
        let url = cookieFileURL()
        try? output.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        verbose("Session cookies saved")
    }

    func loadCookies() -> Bool {
        let url = cookieFileURL()
        let legacyURL = legacyCookieFileURL()
        if !FileManager.default.fileExists(atPath: url.path),
           FileManager.default.fileExists(atPath: legacyURL.path),
           (try? FileManager.default.copyItem(at: legacyURL, to: url)) != nil {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: legacyURL)
        }
        verbose("Checking saved session")
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            verbose("Saved session unavailable")
            return false
        }
        var cookies: [String: String] = [:]
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 7 else { continue }
            cookies[parts[5]] = parts[6]
        }
        guard !cookies.isEmpty else {
            verbose("Cookie file empty")
            return false
        }
        currentCookieHeader = cookies.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")
        verbose("Saved session loaded: \(cookies.count) cookie(s)")
        return true
    }

    func login(username: String, password: String) async throws {
        disableActiveRecoveries()
        try await loginWeb(username: username, password: password)
        do {
            try await refreshMobileProfile(username: username, password: password)
        } catch {
            verbose("[Mobile Login] Profile unavailable; PHP session remains authenticated")
        }
    }

    private func loginWeb(username: String, password: String) async throws {
        verbose("Starting login")
        currentCookieHeader = nil
        studentProfile = nil
        cachedStudentProfileImage = nil
        studentProfileTask?.cancel()
        studentProfileTask = nil
        let url = baseURL.appendingPathComponent("require/class/login.php")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        func field(_ name: String, _ value: String) -> Data {
            var data = Data()
            data.append(Data("--\(boundary)\r\n".utf8))
            data.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            data.append(Data("\(value)\r\n".utf8))
            return data
        }
        var body = Data()
        body.append(field("request", "login"))
        body.append(field("loginAs", "standard"))
        body.append(field("isRegister", "0"))
        body.append(field("password", password))
        body.append(field("username", username))
        body.append(field("newUser", "0"))
        body.append(Data("--\(boundary)--\r\n".utf8))
        request.httpBody = body
        verbose("[Login] Request: \(request.httpMethod ?? "POST") \(url.absoluteString)")
        verbose("[Login] Content-Type: \(request.value(forHTTPHeaderField: "Content-Type") ?? "<none>")")
        verbose("[Login] Body bytes: \(body.count)")
        verbose("[Login] Form fields: request=login, loginAs=standard, isRegister=0, newUser=0")
        verbose("[Login] Credential lengths: username=\(username.count), password=\(password.count); values redacted")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            verbose("Login response was not HTTP")
            throw OBSClientError.serverError
        }
        verbose("[Login] Response: status=\(http.statusCode), finalURL=\(http.url?.absoluteString ?? "<none>")")
        verbose("[Login] Response metadata: mime=\(http.mimeType ?? "<none>"), bytes=\(data.count)")
        let setCookieNames = HTTPCookie.cookies(
            withResponseHeaderFields: http.allHeaderFields.reduce(into: [String: String]()) { result, entry in
                guard let key = entry.key as? String, let value = entry.value as? String else { return }
                result[key] = value
            },
            for: http.url ?? url
        ).map(\.name).sorted()
        verbose("[Login] Set-Cookie names: \(setCookieNames.isEmpty ? "<none>" : setCookieNames.joined(separator: ", "))")
        captureCookies(from: http)
        guard 200..<300 ~= http.statusCode else { throw OBSClientError.serverError }
        let result = try JSONDecoder().decode(LoginResponse.self, from: data)
        verbose("[Login] JSON decoded: success=\(result.success), messagePresent=\(result.msg?.isEmpty == false)")
        guard result.success else { throw OBSClientError.loginFailed(result.msg ?? "Giriş başarısız.") }
        guard currentCookieHeader != nil else {
            throw OBSClientError.invalidResponse("Giriş başarılı fakat sunucu oturum çerezi göndermedi.")
        }
        saveCookies()
    }

    func refreshMobileProfile(username: String, password: String) async throws {
        let url = baseURL
            .appendingPathComponent("obsapi", isDirectory: true)
            .appendingPathComponent("auth/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            MobileLoginRequest(username: username, password: password)
        )

        let (data, response) = try await mobileSession.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw OBSClientError.serverError
        }

        let result = try JSONDecoder().decode(MobileLoginResponse.self, from: data)
        let info = result.userInfo
        verbose("[Mobile Login] success=\(result.success), userInfoPresent=\(info != nil), messagePresent=\(result.msg?.isEmpty == false), statusPresent=\(result.status?.isEmpty == false)")
        verbose("[Mobile Login] profilePhotoPresent=\(info?.profilePhoto?.isEmpty == false), profilePhotoPath=\(sanitizedPhotoPath(info?.profilePhoto) ?? "<none>")")
        verbose("[Mobile Login] fields: stuNo=\(info?.stuNo != nil), classId=\(info?.classId != nil), nameSurname=\(info?.nameSurname != nil), fullName=\(info?.fullName != nil), studentName=\(info?.studentName != nil), studentNameSurname=\(info?.studentNameSurname != nil), stuName=\(info?.stuName != nil), stuSurname=\(info?.stuSurname != nil), name=\(info?.name != nil), surname=\(info?.surname != nil), userName=\(info?.userName != nil), userSurname=\(info?.userSurname != nil), firstName=\(info?.firstName != nil), lastName=\(info?.lastName != nil)")

        guard result.success else {
            throw OBSClientError.loginFailed(result.msg ?? result.status ?? "Mobil OBS girişi başarısız.")
        }
        mobileAuthenticated = true
        guard let info,
              let stuNo = info.stuNo?.trimmingCharacters(in: .whitespacesAndNewlines), !stuNo.isEmpty,
              let classId = info.classId?.trimmingCharacters(in: .whitespacesAndNewlines), !classId.isEmpty,
              let name = info.displayName else {
            verbose("[Mobile Login] userInfo is incomplete; legacy profile fallback will be used")
            return
        }

        studentProfile = StudentProfile(
            stuNo: stuNo,
            classId: classId,
            name: name,
            photoURL: profilePhotoURL(from: info.profilePhoto)
        )
        cachedStudentProfileImage = nil
        verbose("[Mobile Login] StudentProfile cached from userInfo")
    }

    func loadIndex() async throws -> LessonSchedule {
        try await performRead(for: .web) { [self] in
            try await loadIndexOnce()
        }
    }

    private func loadIndexOnce() async throws -> LessonSchedule {
        let url = baseURL.appendingPathComponent("pages/student/require/indexAction.php")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("request=loadIndex".utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        guard let cookies = currentCookieHeader, !cookies.isEmpty else {
            throw OBSClientError.sessionExpired
        }
        request.setValue(cookies, forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OBSClientError.serverError
        }
        let raw = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
        try validateHTTPResponse(http)
        if raw.trimmingCharacters(in: .whitespacesAndNewlines) == "Access denied." {
            throw OBSClientError.sessionExpired
        }
        do {
            let result = try JSONDecoder().decode(OBSResponse.self, from: data)
            guard result.success else { throw OBSClientError.sessionExpired }
            return result.data.lessonSchedule
        } catch {
            throw error
        }
    }

    func performRead<T>(
        for sessionKind: OBSSessionKind,
        operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        var transientRetryCount = 0
        var recoveredSession = false

        while true {
            try Task.checkCancellation()
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch OBSClientError.sessionExpired where !recoveredSession {
                recoveredSession = true
                try await recover(sessionKind)
            } catch {
                guard transientRetryCount < 3, let delay = retryDelay(for: error, retryNumber: transientRetryCount) else {
                    throw error
                }
                transientRetryCount += 1
                try await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func validateHTTPResponse(_ response: HTTPURLResponse) throws {
        guard 200..<300 ~= response.statusCode else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw OBSClientError.sessionExpired
            }
            if [429, 502, 503, 504].contains(response.statusCode) {
                throw OBSClientError.temporaryServer(
                    statusCode: response.statusCode,
                    retryAfter: boundedRetryAfter(response.value(forHTTPHeaderField: "Retry-After"))
                )
            }
            throw OBSClientError.serverError
        }
    }

    func mobileResponseIndicatesExpiredSession(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["success"] as? Bool) == false else { return false }
        let message = [object["msg"], object["status"], object["message"]]
            .compactMap { $0 as? String }
            .joined(separator: " ")
            .lowercased()
        return ["session", "oturum", "login", "giriş", "unauthorized", "access denied"]
            .contains { message.contains($0) }
    }

    func ensureMobileSession() throws {
        guard mobileAuthenticated else { throw OBSClientError.sessionExpired }
    }

    func mobileData(for request: URLRequest) async throws -> Data {
        try ensureMobileSession()
        let (data, response) = try await mobileSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OBSClientError.serverError }
        try validateHTTPResponse(http)
        if mobileResponseIndicatesExpiredSession(data) {
            mobileAuthenticated = false
            throw OBSClientError.sessionExpired
        }
        return data
    }

    private func recover(_ kind: OBSSessionKind) async throws {
        switch kind {
        case .web:
            if let webRecovery { return try await webRecovery.task.value }
        case .mobile:
            if let mobileRecovery { return try await mobileRecovery.task.value }
        }

        guard let credentials = try credentialProvider?() else {
            throw OBSClientError.recoveryUnavailable
        }
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { throw OBSClientError.recoveryUnavailable }
            switch kind {
            case .web:
                try await self.loginWeb(username: credentials.username, password: credentials.password)
            case .mobile:
                try await self.refreshMobileProfile(username: credentials.username, password: credentials.password)
            }
        }
        switch kind {
        case .web: webRecovery = (id, task)
        case .mobile: mobileRecovery = (id, task)
        }
        do {
            try await task.value
            clearRecovery(kind, id: id)
        } catch {
            clearRecovery(kind, id: id)
            throw error
        }
    }

    private func clearRecovery(_ kind: OBSSessionKind, id: UUID) {
        switch kind {
        case .web where webRecovery?.id == id: webRecovery = nil
        case .mobile where mobileRecovery?.id == id: mobileRecovery = nil
        default: break
        }
    }

    private func disableActiveRecoveries() {
        webRecovery?.task.cancel()
        mobileRecovery?.task.cancel()
        webRecovery = nil
        mobileRecovery = nil
    }

    private func retryDelay(for error: Error, retryNumber: Int) -> TimeInterval? {
        if case OBSClientError.temporaryServer(_, let retryAfter) = error {
            return retryAfter ?? pow(2, Double(retryNumber + 1))
        }
        guard let urlError = error as? URLError,
              [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
               .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable]
                .contains(urlError.code) else { return nil }
        return pow(2, Double(retryNumber + 1))
    }

    private func boundedRetryAfter(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = TimeInterval(value) { return min(max(seconds, 1), 60) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return nil }
        return min(max(date.timeIntervalSinceNow, 1), 60)
    }

    func loadStudentProfile() async throws -> StudentProfile {
        if let studentProfile {
            return studentProfile
        }
        if let studentProfileTask {
            return try await studentProfileTask.value
        }

        let task = Task { @MainActor [weak self] () throws -> StudentProfile in
            guard let self else {
                throw OBSClientError.sessionExpired
            }
            return try await self.fetchLegacyStudentProfile()
        }
        studentProfileTask = task

        do {
            let profile = try await task.value
            studentProfile = profile
            studentProfileTask = nil
            verbose("Student profile loaded")
            return profile
        } catch {
            studentProfileTask = nil
            throw error
        }
    }

    private func fetchLegacyStudentProfile() async throws -> StudentProfile {
        let url = baseURL.appendingPathComponent("pages/student/profile.php")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        try attachAuthenticatedSession(to: &request)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        verbose("[Legacy Profile] Loading profile.php fallback")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            verbose("[Profile] Response is not HTTP")
            throw OBSClientError.serverError
        }
        verbose("[Profile] Response: status=\(http.statusCode), finalURL=\(http.url?.absoluteString ?? "<none>")")
        verbose("[Profile] Response metadata: mime=\(http.mimeType ?? "<none>"), bytes=\(data.count)")
        guard 200..<300 ~= http.statusCode else {
            throw OBSClientError.serverError
        }
        guard let html = String(data: data, encoding: .utf8) else {
            verbose("[Profile] Response could not be decoded as UTF-8")
            throw OBSClientError.invalidResponse("Öğrenci profili okunamadı.")
        }
        guard let profile = StudentProfileHTMLParser().parse(
            html: html,
            profilePageURL: http.url ?? url
        ) else {
            verbose("[Profile] HTML parser did not produce a student profile")
            throw OBSClientError.invalidResponse("Öğrenci profili okunamadı.")
        }
        let photoComponents = profile.photoURL.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }
        let photoQueryNames = photoComponents?.queryItems?.map(\.name).sorted() ?? []
        verbose(
            "[Profile] Parsed: nameLength=\(profile.name.count), studentNumberLength=\(profile.stuNo.count), " +
            "classCodeLength=\(profile.classId.count)"
        )
        verbose(
            "[Profile] Photo source: path=\(profile.photoURL?.path ?? "<none>"), " +
            "queryKeys=\(photoQueryNames.isEmpty ? "<none>" : photoQueryNames.joined(separator: ", "))"
        )
        return profile
    }

    private func profilePhotoURL(from value: String?) -> URL? {
        guard let value else { return nil }
        let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        if let absoluteURL = URL(string: path),
           let scheme = absoluteURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return absoluteURL
        }
        return URL(string: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), relativeTo: baseURL.appendingPathComponent("/"))?.absoluteURL
    }

    private func sanitizedPhotoPath(_ value: String?) -> String? {
        guard let value, let components = URLComponents(string: value) else { return nil }
        return components.path.isEmpty ? nil : components.path
    }

    func loadStudentProfileImage(for profile: StudentProfile) async throws -> NSImage? {
        guard let photoURL = profile.photoURL else {
            verbose("[Profile Photo] No photo URL; using avatar fallback")
            return nil
        }
        if let cachedStudentProfileImage {
            verbose("[Profile Photo] Memory cache hit")
            return cachedStudentProfileImage
        }

        var request = URLRequest(url: photoURL)
        request.httpMethod = "GET"
        if let cookies = currentCookieHeader, !cookies.isEmpty {
            request.setValue(cookies, forHTTPHeaderField: "Cookie")
        }
        request.setValue("image/avif,image/webp,image/png,image/jpeg,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let queryNames = URLComponents(
            url: photoURL,
            resolvingAgainstBaseURL: false
        )?.queryItems?.map(\.name).sorted() ?? []
        verbose("[Profile Photo] Request: GET \(photoURL.path)")
        verbose("[Profile Photo] Query keys: \(queryNames.isEmpty ? "<none>" : queryNames.joined(separator: ", "))")
        verbose("[Profile Photo] Cookie attached: \(request.value(forHTTPHeaderField: "Cookie") != nil)")

        let (data, response) = try await mobileSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            verbose("[Profile Photo] Response is not HTTP")
            throw OBSClientError.serverError
        }
        verbose(
            "[Profile Photo] Response: status=\(http.statusCode), mime=\(http.mimeType ?? "<none>"), " +
            "bytes=\(data.count), finalPath=\(http.url?.path ?? "<none>")"
        )
        guard 200..<300 ~= http.statusCode else {
            throw OBSClientError.serverError
        }
        guard !data.isEmpty else {
            verbose("[Profile Photo] Response data is empty")
            throw OBSClientError.invalidResponse("Profil fotoğrafı boş.")
        }
        guard let image = NSImage(data: data), image.isValid else {
            verbose("[Profile Photo] NSImage decoding failed")
            throw OBSClientError.invalidResponse("Profil fotoğrafı okunamadı.")
        }

        verbose("[Profile Photo] Decoded image: \(Int(image.size.width))x\(Int(image.size.height))")
        cachedStudentProfileImage = image
        verbose("[Profile Photo] Stored in memory cache")
        return image
    }

    private func attachAuthenticatedSession(to request: inout URLRequest) throws {
        guard let cookies = currentCookieHeader, !cookies.isEmpty else {
            throw OBSClientError.sessionExpired
        }
        request.setValue(cookies, forHTTPHeaderField: "Cookie")
        let cookieNames = cookies
            .split(separator: ";")
            .compactMap { part -> String? in
                let name = part.trimmingCharacters(in: .whitespaces)
                    .split(separator: "=", maxSplits: 1)
                    .first
                return name.map(String.init)
            }
            .sorted()
        verbose("[Auth] Attached cookie names: \(cookieNames.joined(separator: ", "))")
    }

    func loadStudentExams() async throws -> ExamDashboard {
        try await performRead(for: .web) { [self] in
            let profile = try await loadStudentProfile()
            let data = try await postExamDashboard(fields: [
                ("request", "getStudentExams"),
                ("stuNo", profile.stuNo),
                ("classId", profile.classId),
                ("stuType", "SBS")
            ])
            let result = try JSONDecoder().decode(ExamDashboard.self, from: data)
            guard result.success else { throw OBSClientError.serverError }
            return result
        }
    }

    func loadSchoolReport(examId: String) async throws -> ExamSchoolReport {
        try await performRead(for: .web) { [self] in
            let profile = try await loadStudentProfile()
            let data = try await postExamDashboard(fields: [
                ("request", "getSchoolReport"),
                ("examType", "SBS"),
                ("examId", examId),
                ("stuNo", profile.stuNo),
                ("classId", profile.classId)
            ])
            let result = try JSONDecoder().decode(ExamSchoolReport.self, from: data)
            guard result.success else { throw OBSClientError.serverError }
            return result
        }
    }

    private func postExamDashboard(fields: [(String, String)]) async throws -> Data {
        let url = URL(string: "https://www.tedemkolejiobs.com/pages/student/require/examDashboard.php")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        guard let cookies = currentCookieHeader, !cookies.isEmpty else {
            throw OBSClientError.sessionExpired
        }
        request.setValue(cookies, forHTTPHeaderField: "Cookie")

        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OBSClientError.serverError }
        try validateHTTPResponse(http)
        if String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "Access denied." {
            throw OBSClientError.sessionExpired
        }
        return data
    }


}

struct LoginView: View {
    @ObservedObject var model: AppModel
    @FocusState private var focusedField: Field?
    enum Field { case username, password }

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Image(systemName: "graduationcap.fill").font(.system(size: 42)).foregroundStyle(.tint)
                Text("GöktürkOBS").font(.system(size: 30, weight: .bold))
                Text("Akbim OBS").foregroundStyle(.secondary)
            }
            Form {
                Section {
                    TextField("TC Kimlik No", text: $model.username)
                        .textContentType(.username).focused($focusedField, equals: .username)
                        .onSubmit { focusedField = .password }
                    SecureField("Şifre", text: $model.password)
                        .textContentType(.password).focused($focusedField, equals: .password)
                        .onSubmit { if !model.isLoggingIn { Task { await model.login() } } }
                    Toggle("Beni Hatırla", isOn: $model.rememberMe)
                }
                if let error = model.error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
                Section {
                    Button { Task { await model.login() } } label: {
                        HStack {
                            if model.isLoggingIn { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.right") }
                            Text(model.isLoggingIn ? "Giriş yapılıyor..." : "Giriş Yap")
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.glassProminent)
                        .disabled(model.username.isEmpty || model.password.isEmpty || model.isLoggingIn)
                }
            }.formStyle(.grouped).frame(width: 380)
        }.padding(40).frame(minWidth: 500, minHeight: 520)
            .onAppear {
                model.prepareRememberedUsername()
                DispatchQueue.main.async { focusedField = .username }
            }
    }
}
