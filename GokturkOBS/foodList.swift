import SwiftUI
import PDFKit

struct FoodListResponse: Decodable {
    let hash: String
}

enum FoodListLoadState {
    case idle
    case loading
    case loaded(PDFDocument)
    case empty
    case error(String)
}

enum FoodListResult {
    case pdf(Data)
    case empty
}

extension OBSClient {
    func loadFoodList() async throws -> FoodListResult {
        do {
            let hash = try await loadFoodListHash()
            guard !hash.isEmpty else {
                return .empty
            }

            if let cachedData = try cachedFoodListData(for: hash),
               PDFDocument(data: cachedData) != nil {
                return .pdf(cachedData)
            }

            let data = try await downloadFoodListPDF(hash: hash)
            guard !data.isEmpty else {
                throw OBSClientError.invalidResponse("Yemek listesi PDF dosyası boş.")
            }
            guard PDFDocument(data: data) != nil else {
                throw OBSClientError.invalidResponse("Yemek listesi geçerli bir PDF dosyası değil.")
            }

            try cacheFoodList(data, hash: hash)
            return .pdf(data)
        } catch {
            if let cachedData = try? latestCachedFoodListData(),
               PDFDocument(data: cachedData) != nil {
                return .pdf(cachedData)
            }
            throw error
        }
    }

    private func loadFoodListHash() async throws -> String {
        let url = baseURL.appendingPathComponent("pages/student/require/foodListAction.php")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("request=get-food-list".utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        try attachFoodListSession(to: &request)

        let cookieNames = (currentCookieHeader ?? "")
            .split(separator: ";")
            .compactMap { $0.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1).first }
            .map(String.init)
            .sorted()
        print("[OBS DEBUG] [Food List API] Request: POST \(url.absoluteString)")
        print("[OBS DEBUG] [Food List API] Body: request=get-food-list")
        print("[OBS DEBUG] [Food List API] Headers: Content-Type, Cookie, X-Requested-With")
        print("[OBS DEBUG] [Food List API] Cookie names: \(cookieNames.joined(separator: ", "))")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            print(
                "[OBS DEBUG] [Food List API] Response: status=\(http.statusCode), " +
                "mime=\(http.mimeType ?? "<none>"), bytes=\(data.count), " +
                "finalURL=\(http.url?.absoluteString ?? "<none>")"
            )
        } else {
            print("[OBS DEBUG] [Food List API] Response is not HTTP")
        }
        try validateFoodListResponse(response, data: data)

        do {
            let result = try JSONDecoder().decode(FoodListResponse.self, from: data)
            print(
                "[OBS DEBUG] [Food List API] JSON decoded: hashPresent=\(!result.hash.isEmpty), " +
                "hashLength=\(result.hash.count); value redacted"
            )
            return result.hash
        } catch {
            print("[OBS DEBUG] [Food List API] JSON decoding failed: \(error.localizedDescription)")
            throw OBSClientError.invalidResponse("Yemek listesi yanıtı okunamadı.")
        }
    }

    private func downloadFoodListPDF(hash: String) async throws -> Data {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("download.php"), resolvingAgainstBaseURL: false) else {
            throw OBSClientError.invalidResponse("Yemek listesi indirme adresi oluşturulamadı.")
        }
        components.queryItems = [
            URLQueryItem(name: "file", value: hash),
            URLQueryItem(name: "view", value: nil)
        ]
        guard let url = components.url else {
            throw OBSClientError.invalidResponse("Yemek listesi indirme adresi oluşturulamadı.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        try attachFoodListSession(to: &request)

        let (data, response) = try await session.data(for: request)
        try validateFoodListResponse(response, data: data)
        return data
    }

    private func attachFoodListSession(to request: inout URLRequest) throws {
        guard let cookies = currentCookieHeader, !cookies.isEmpty else {
            throw OBSClientError.sessionExpired
        }
        request.setValue(cookies, forHTTPHeaderField: "Cookie")
    }

    private func validateFoodListResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OBSClientError.serverError
        }
        guard 200..<300 ~= http.statusCode else {
            throw OBSClientError.serverError
        }
        if String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "Access denied." {
            throw OBSClientError.sessionExpired
        }
    }

    private func foodListCacheDirectory() throws -> URL {
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw OBSClientError.invalidResponse("Yemek listesi cache klasörü bulunamadı.")
        }
        let directory = applicationSupport
            .appendingPathComponent("GokturkOBS", isDirectory: true)
            .appendingPathComponent("FoodList", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func cacheURL(for hash: String) throws -> URL {
        let safeHash = Data(hash.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return try foodListCacheDirectory().appendingPathComponent("\(safeHash).pdf")
    }

    private func cachedFoodListData(for hash: String) throws -> Data? {
        let url = try cacheURL(for: hash)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    private func cacheFoodList(_ data: Data, hash: String) throws {
        let directory = try foodListCacheDirectory()
        let destination = try cacheURL(for: hash)
        try data.write(to: destination, options: .atomic)

        let fileManager = FileManager.default
        let cachedFiles = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        for file in cachedFiles where file.pathExtension == "pdf" && file != destination {
            try? fileManager.removeItem(at: file)
        }
    }

    private func latestCachedFoodListData() throws -> Data? {
        let directory = try foodListCacheDirectory()
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: .skipsHiddenFiles
        )
        let latest = files
            .filter { $0.pathExtension == "pdf" }
            .max {
                let firstDate = try? $0.resourceValues(forKeys: keys).contentModificationDate
                let secondDate = try? $1.resourceValues(forKeys: keys).contentModificationDate
                return (firstDate ?? .distantPast) < (secondDate ?? .distantPast)
            }
        guard let latest else {
            return nil
        }
        return try Data(contentsOf: latest)
    }
}

struct FoodListView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        FoodListContent(state: model.foodListState) {
            Task {
                await model.loadFoodList(forceReload: true)
            }
        }
        .navigationTitle("Yemek Listesi")
        .task {
            await model.loadFoodList()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await model.loadFoodList(forceReload: true)
                    }
                } label: {
                    Label("Yenile", systemImage: "arrow.clockwise")
                }
                .disabled(model.foodListState.isLoading)
            }
        }
    }
}

private struct FoodListContent: View {
    let state: FoodListLoadState
    let retry: () -> Void

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView("Yemek listesi yükleniyor…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let document):
            PDFKitView(document: document)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView(
                "Yemek listesi bulunamadı",
                systemImage: "fork.knife",
                description: Text("Kurumunuz tarafından henüz yemek listesi yüklenmemiş.")
            )
        case .error(let message):
            ContentUnavailableView {
                Label("Yemek listesi yüklenemedi", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Tekrar Dene", action: retry)
            }
        }
    }
}

private struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.document = document
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
            pdfView.autoScales = true
        }
    }
}

private extension FoodListLoadState {
    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}
