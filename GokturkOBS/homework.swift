import Foundation

struct HomeworkResponse: Codable {
    let success: Bool
    let data: [Homework]
}

struct Homework: Codable, Identifiable {
    let id: Int
    let title: String
    let teaNameSurname: String
    let typeName: String
    let startDate: String
    let endDate: String
    let iconClass: String
    let lesson: String
    let score: String
    let statusName: String
    let status: Int
    let willBeScored: Bool
    let isActive: Bool
    let hasAttachFile: Bool
    let hasAnswerFile: Bool
    let seen: Bool
    let stuCanAttachFile: Bool
    let attachFileCount: Int
    let answerFileCount: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case teaNameSurname
        case typeName
        case startDate
        case endDate
        case iconClass
        case lesson
        case score
        case statusName
        case status
        case willBeScored
        case isActive
        case hasAttachFile
        case hasAnswerFile
        case seen
        case stuCanAttachFile
        case attachFileCount
        case answerFileCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        teaNameSurname = try container.decodeIfPresent(String.self, forKey: .teaNameSurname) ?? ""
        typeName = try container.decodeIfPresent(String.self, forKey: .typeName) ?? ""
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate) ?? ""
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate) ?? ""
        iconClass = try container.decodeIfPresent(String.self, forKey: .iconClass) ?? ""
        lesson = try container.decodeIfPresent(String.self, forKey: .lesson) ?? ""
        if let value = try? container.decode(String.self, forKey: .score) {
            score = value
        } else if let value = try? container.decode(Int.self, forKey: .score) {
            score = String(value)
        } else {
            score = "-"
        }
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName) ?? ""
        status = try container.decodeIfPresent(Int.self, forKey: .status) ?? 0
        willBeScored = try container.decodeIfPresent(Bool.self, forKey: .willBeScored) ?? false
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        hasAttachFile = try container.decodeIfPresent(Bool.self, forKey: .hasAttachFile) ?? false
        hasAnswerFile = try container.decodeIfPresent(Bool.self, forKey: .hasAnswerFile) ?? false
        seen = try container.decodeIfPresent(Bool.self, forKey: .seen) ?? false
        stuCanAttachFile = try container.decodeIfPresent(Bool.self, forKey: .stuCanAttachFile) ?? false
        attachFileCount = try container.decodeIfPresent(Int.self, forKey: .attachFileCount) ?? 0
        if let value = try? container.decode(String.self, forKey: .answerFileCount) {
            answerFileCount = value
        } else if let value = try? container.decode(Int.self, forKey: .answerFileCount) {
            answerFileCount = String(value)
        } else {
            answerFileCount = "0"
        }
    }
}

struct HomeworkDetailResponse: Codable {
    let success: Bool
    let data: HomeworkDetail
}

struct HomeworkDetail: Codable, Identifiable {
    let id: Int
    let title: String
    let description: String
    let startDate: String
    let analysed: Int
    let endDate: String
    let konuAd: String?
    let willBeScored: Bool
    let teaNameSurname: String
    let typeName: String
    let lesson: String
    let score: String
    let teacherComment: String
    let status: Int
    let statusName: String
    let iconClass: String
    let isActive: Bool
    let stuCanAttachFile: Bool
    let seen: Bool
    let studentAttachFiles: [HomeworkFile]
    let attachFiles: [HomeworkFile]
    let answerFiles: [HomeworkFile]

    enum CodingKeys: String, CodingKey {
        case id, title, description, startDate, analysed, endDate, konuAd
        case willBeScored, teaNameSurname, typeName, lesson, score, teacherComment
        case status, statusName, iconClass, isActive, stuCanAttachFile, seen
        case studentAttachFiles, attachFiles, answerFiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate) ?? ""
        analysed = try container.decodeIfPresent(Int.self, forKey: .analysed) ?? 0
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate) ?? ""
        konuAd = try container.decodeIfPresent(String.self, forKey: .konuAd)
        willBeScored = try container.decodeIfPresent(Bool.self, forKey: .willBeScored) ?? false
        teaNameSurname = try container.decodeIfPresent(String.self, forKey: .teaNameSurname) ?? ""
        typeName = try container.decodeIfPresent(String.self, forKey: .typeName) ?? ""
        lesson = try container.decodeIfPresent(String.self, forKey: .lesson) ?? ""
        if let value = try? container.decode(String.self, forKey: .score) {
            score = value
        } else if let value = try? container.decode(Int.self, forKey: .score) {
            score = String(value)
        } else {
            score = "-"
        }
        teacherComment = try container.decodeIfPresent(String.self, forKey: .teacherComment) ?? ""
        status = try container.decodeIfPresent(Int.self, forKey: .status) ?? 0
        statusName = try container.decodeIfPresent(String.self, forKey: .statusName) ?? ""
        iconClass = try container.decodeIfPresent(String.self, forKey: .iconClass) ?? ""
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        stuCanAttachFile = try container.decodeIfPresent(Bool.self, forKey: .stuCanAttachFile) ?? false
        seen = try container.decodeIfPresent(Bool.self, forKey: .seen) ?? false
        studentAttachFiles = try container.decodeIfPresent([HomeworkFile].self, forKey: .studentAttachFiles) ?? []
        attachFiles = try container.decodeIfPresent([HomeworkFile].self, forKey: .attachFiles) ?? []
        answerFiles = try container.decodeIfPresent([HomeworkFile].self, forKey: .answerFiles) ?? []
    }
}

struct HomeworkFile: Codable, Identifiable {
    let fileId: Int
    let fileHash: String
    let fileName: String
    let fileType: Int

    var id: Int { fileId }

    enum CodingKeys: String, CodingKey {
        case fileId, fileHash, fileName, fileType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileId = try container.decode(Int.self, forKey: .fileId)
        fileHash = try container.decodeIfPresent(String.self, forKey: .fileHash) ?? ""
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        fileType = try container.decodeIfPresent(Int.self, forKey: .fileType) ?? 0
    }
}

extension OBSClient {
    private func homeworkData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        guard let cookies = currentCookieHeader,
              !cookies.isEmpty else {
            throw OBSClientError.sessionExpired
        }

        request.setValue(cookies, forHTTPHeaderField: "Cookie")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

        print("[OBS DEBUG] Request started: GET \(url.path); session cookie attached")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            print("[OBS DEBUG] Request failed: \(url.path) (\(String(describing: type(of: error))))")
            throw error
        }

        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            print("[OBS DEBUG] Request returned non-success status: \(statusCode.map(String.init) ?? "non-HTTP response")")
            throw OBSClientError.serverError
        }

        print("[OBS DEBUG] Request completed: \(url.path); status=\(http.statusCode); bytes=\(data.count)")
        return data
    }

    func loadHomework() async throws -> [Homework] {
        let url = URL(string: "https://www.tedemkolejiobs.com/obsapi/homework/getHomeworkList")!
        let data = try await homeworkData(from: url)
        let result = try JSONDecoder().decode(HomeworkResponse.self, from: data)

        guard result.success else {
            throw OBSClientError.serverError
        }

        return result.data
    }

    func loadHomeworkDetail(id: Int) async throws -> HomeworkDetail {
        var components = URLComponents(string: "https://www.tedemkolejiobs.com/obsapi/homework/getHomeworkDetail")!
        components.queryItems = [URLQueryItem(name: "id", value: String(id))]
        let data = try await homeworkData(from: components.url!)
        let result = try JSONDecoder().decode(HomeworkDetailResponse.self, from: data)

        guard result.success else {
            throw OBSClientError.serverError
        }

        return result.data
    }

    func downloadHomeworkFile(_ file: HomeworkFile) async throws -> Data {
        guard !file.fileHash.isEmpty else {
            throw OBSClientError.invalidResponse("Dosya indirme bilgisi eksik.")
        }

        var components = URLComponents(string: "https://www.tedemkolejiobs.com/download.php")!
        components.queryItems = [URLQueryItem(name: "file", value: file.fileHash)]
        guard let url = components.url else {
            throw OBSClientError.invalidResponse("Dosya indirme adresi oluşturulamadı.")
        }

        return try await homeworkData(from: url)
    }
}