import SwiftUI
import PDFKit

struct FoodListResponse: Decodable {
    let hash: String
}

enum FoodListLoadState {
    case idle
    case loading
    case loaded(PDFDocument, [FoodMenuDay])
    case empty
    case error(String)
}

enum FoodListResult {
    case pdf(Data)
    case empty
}

private struct FoodPhoto: Sendable {
    let thumbnailURL: URL
    let sourcePageURL: URL?
}

private actor FoodPhotoService {
    static let shared = FoodPhotoService()

    private enum CachedResult {
        case found(FoodPhoto)
        case missing
    }

    private struct SearchResponse: Decodable {
        let data: SearchData

        enum CodingKeys: String, CodingKey {
            case data = "Data"
        }
    }

    private struct SearchData: Decodable {
        let recipes: [Recipe]

        enum CodingKeys: String, CodingKey {
            case recipes = "Recipe"
        }
    }

    private struct Recipe: Decodable {
        let title: String
        let permalink: URL
        let featuredImage: FeaturedImage?

        enum CodingKeys: String, CodingKey {
            case title = "Title"
            case permalink = "Permalink"
            case featuredImage = "FeaturedImage"
        }
    }

    private struct FeaturedImage: Decodable {
        let mediaData: [String: ImageVariant]

        enum CodingKeys: String, CodingKey {
            case mediaData = "MediaData"
        }
    }

    private struct ImageVariant: Decodable {
        let path: URL

        enum CodingKeys: String, CodingKey {
            case path = "Path"
        }
    }

    private var cache: [String: CachedResult] = [:]

    func photo(for mealName: String) async -> FoodPhoto? {
        let cacheKey = mealName.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "tr_TR")
        )
        if let cached = cache[cacheKey] {
            switch cached {
            case .found(let photo): return photo
            case .missing: return nil
            }
        }

        if let photo = stockPhoto(for: mealName) {
            cache[cacheKey] = .found(photo)
            return photo
        }

        guard !isIgnoredMeal(mealName) else {
            cache[cacheKey] = .missing
            return nil
        }

        let mealNames = candidateMealNames(for: mealName)
        guard !mealNames.isEmpty else {
            cache[cacheKey] = .missing
            return nil
        }

        for candidateMealName in mealNames {
            var recipesByURL: [URL: Recipe] = [:]
            for searchQuery in searchQueries(for: candidateMealName) {
                if let recipes = try? await searchRecipes(query: searchQuery) {
                    for recipe in recipes {
                        recipesByURL[recipe.permalink] = recipe
                    }
                }
                if let best = bestRecipe(for: candidateMealName, among: Array(recipesByURL.values)),
                   best.score >= 0.82,
                   let photo = photo(from: best.recipe) {
                    cache[cacheKey] = .found(photo)
                    return photo
                }
            }

            if let best = bestRecipe(for: candidateMealName, among: Array(recipesByURL.values)),
               best.score >= 0.62,
               let photo = photo(from: best.recipe) {
                cache[cacheKey] = .found(photo)
                return photo
            }
        }

        cache[cacheKey] = .missing
        return nil
    }

    private func searchRecipes(query: String) async throws -> [Recipe] {
        guard var components = URLComponents(string: "https://yemek.com/ara/sonuclar/") else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "rows", value: "12"),
            URLQueryItem(name: "recipes_start", value: "0"),
            URLQueryItem(name: "posts_start", value: "0")
        ]
        guard let url = components.url else {
            return []
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("GokturkOBS/2.0 (macOS food menu)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .returnCacheDataElseLoad
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(SearchResponse.self, from: data).data.recipes
    }

    private func stockPhoto(for mealName: String) -> FoodPhoto? {
        let normalized = mealName.uppercased(with: Locale(identifier: "tr_TR"))
        let imageAddress: String?
        let sourceAddress: String?
        if normalized.contains("BARDAK SU") {
            imageAddress = "https://images.pexels.com/photos/25595771/pexels-photo-25595771/free-photo-of-glass-of-water-on-a-table.jpeg?auto=compress&w=320&h=240&fit=crop"
            sourceAddress = "https://www.pexels.com/photo/glass-of-water-on-a-table-25595771/"
        } else if normalized.contains("SALATBAR") || normalized.contains("SALATA BAR") {
            imageAddress = "https://images.pexels.com/photos/38881945/pexels-photo-38881945/free-photo-of-elegant-salad-buffet-display-at-event.jpeg?auto=compress&w=320&h=240&fit=crop"
            sourceAddress = "https://www.pexels.com/photo/elegant-salad-buffet-display-at-event-38881945/"
        } else if normalized.contains("SOĞUK İÇECEK") {
            imageAddress = "https://images.pexels.com/photos/4021983/pexels-photo-4021983.jpeg?auto=compress&w=320&h=240&fit=crop"
            sourceAddress = "https://www.pexels.com/photo/glass-of-fresh-drink-on-white-background-4021983/"
        } else if normalized.contains("MEVSİM MEYVE") {
            imageAddress = "https://images.pexels.com/photos/1128678/pexels-photo-1128678.jpeg?auto=compress&w=320&h=240&fit=crop"
            sourceAddress = "https://www.pexels.com/photo/assorted-sliced-fruits-1128678/"
        } else if normalized == "TATLI" {
            imageAddress = "https://images.pexels.com/photos/11745425/pexels-photo-11745425.jpeg?auto=compress&w=320&h=240&fit=crop"
            sourceAddress = "https://www.pexels.com/photo/assorted-desserts-on-a-table-11745425/"
        } else {
            imageAddress = nil
            sourceAddress = nil
        }
        guard let imageAddress,
              let imageURL = URL(string: imageAddress) else {
            return nil
        }
        return FoodPhoto(
            thumbnailURL: imageURL,
            sourcePageURL: sourceAddress.flatMap(URL.init(string:))
        )
    }

    private func photo(from recipe: Recipe) -> FoodPhoto? {
        let variants = recipe.featuredImage?.mediaData
        guard let imageURL = variants?["ymk-medium"]?.path ?? variants?["ymk-thumbnail"]?.path else {
            return nil
        }
        return FoodPhoto(thumbnailURL: imageURL, sourcePageURL: recipe.permalink)
    }

    private func searchableMealName(_ mealName: String) -> String {
        mealName
            .replacingOccurrences(of: "T.Y", with: "tereyağlı", options: .caseInsensitive)
            .replacingOccurrences(of: "Z.Y", with: "zeytinyağlı", options: .caseInsensitive)
            .replacingOccurrences(of: "ekmek arası", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func candidateMealNames(for mealName: String) -> [String] {
        let expanded = searchableMealName(mealName)
        guard !expanded.isEmpty else {
            return []
        }

        let withoutStuffed = expanded
            .replacingOccurrences(of: "İÇLİ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "içli", with: "", options: .caseInsensitive)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        var candidates = [withoutStuffed]
        let words = Set(normalizedWords(in: withoutStuffed))
        if words.contains("pirinc") && words.contains("pilav") {
            candidates.append("pirinç pilavı")
        }
        return candidates.reduce(into: [String]()) { result, candidate in
            guard !candidate.isEmpty,
                  !result.contains(where: { normalized($0) == normalized(candidate) }) else {
                return
            }
            result.append(candidate)
        }
    }

    private func searchQueries(for mealName: String) -> [String] {
        let distinctiveWords = normalizedWords(in: mealName)
            .filter { $0.count >= 4 && !genericMealWords.contains($0) }
        return ([mealName] + distinctiveWords).reduce(into: [String]()) { result, query in
            if !result.contains(query) {
                result.append(query)
            }
        }
    }

    private func bestRecipe(for mealName: String, among recipes: [Recipe]) -> (recipe: Recipe, score: Double)? {
        let expected = Set(normalizedWords(in: mealName))
        guard !expected.isEmpty else {
            return nil
        }
        let distinctive = expected.subtracting(genericMealWords)
        let focus = distinctive.isEmpty ? expected : distinctive
        return recipes.compactMap { recipe -> (recipe: Recipe, score: Double)? in
            let recipeName = recipe.title.split(separator: ":").last.map(String.init) ?? recipe.title
            let actual = Set(normalizedWords(in: recipeName))
            guard !actual.isEmpty else { return nil }
            let focusMatches = focus.intersection(actual).count
            let allMatches = expected.intersection(actual).count
            let focusRecall = Double(focusMatches) / Double(focus.count)
            let allRecall = Double(allMatches) / Double(expected.count)
            let precision = Double(allMatches) / Double(actual.count)
            return (recipe, focusRecall * 0.8 + allRecall * 0.15 + precision * 0.05)
        }
        .max { $0.score < $1.score }
    }

    private func normalizedWords(in value: String) -> [String] {
        let suffixes: [String: String] = [
            "corbasi": "corba", "pilavi": "pilav", "koftesi": "kofte",
            "kizartmasi": "kizartma", "yahnisi": "yahni", "yemegi": "yemek"
        ]
        return normalized(value)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { suffixes[$0] ?? $0 }
    }

    private func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "tr_TR")
        )
        .replacingOccurrences(of: "ı", with: "i")
        .replacingOccurrences(of: "ş", with: "s")
        .replacingOccurrences(of: "ğ", with: "g")
        .replacingOccurrences(of: "ü", with: "u")
        .replacingOccurrences(of: "ö", with: "o")
        .replacingOccurrences(of: "ç", with: "c")
    }

    private func isIgnoredMeal(_ mealName: String) -> Bool {
        normalized(mealName) == "tatil"
    }

    private var genericMealWords: Set<String> {
        [
            "corba", "pilav", "kizartma", "yemek", "etli", "soslu",
            "tereyagli", "zeytinyagli", "yahni"
        ]
    }

}

extension OBSClient {
    func loadFoodList() async throws -> FoodListResult {
        do {
            return try await performRead(for: .web) { [self] in
                try await loadFoodListOnce()
            }
        } catch {
            if let cachedData = try? latestCachedFoodListData(),
               PDFDocument(data: cachedData) != nil {
                return .pdf(cachedData)
            }
            throw error
        }
    }

    private func loadFoodListOnce() async throws -> FoodListResult {
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
        try validateHTTPResponse(http)
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
        FoodListContent(
            state: model.foodListState,
            preferredSelectedID: model.foodListSelectedDayID
        ) {
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
    let preferredSelectedID: FoodMenuDay.ID?
    let retry: () -> Void

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView("Yemek listesi yükleniyor…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let document, let days):
            ParsedFoodMenuView(
                document: document,
                days: days,
                preferredSelectedID: preferredSelectedID
            )
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

struct PDFKitView: NSViewRepresentable {
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

private struct ParsedFoodMenuView: View {
    let document: PDFDocument
    let days: [FoodMenuDay]
    let preferredSelectedID: FoodMenuDay.ID?
    @State private var selectedID: FoodMenuDay.ID?
    @State private var showsPDF = false

    var body: some View {
        if days.isEmpty {
            VStack(spacing: 12) {
                ContentUnavailableView("Menü otomatik ayrıştırılamadı", systemImage: "doc.text.magnifyingglass", description: Text("Yanlış bilgi göstermemek için orijinal PDF'yi açabilirsiniz."))
                Button("Orijinal PDF") { showsPDF = true }
            }
            .sheet(isPresented: $showsPDF) { PDFKitView(document: document).frame(minWidth: 760, minHeight: 620) }
        } else {
            VStack(spacing: 0) {
                FoodMenuToolbar(
                    days: days,
                    selectedID: $selectedID,
                    showPDF: { showsPDF = true }
                )
                Divider()
                if let day = days.first(where: { $0.id == selectedID }) ?? days.first {
                    FoodMenuDayView(day: day)
                        .navigationTitle(day.heading)
                }
            }
            .onAppear {
                if selectedID == nil {
                    selectedID = validPreferredID ?? days.first?.id
                }
            }
            .onChange(of: preferredSelectedID) { _, _ in
                if let validPreferredID {
                    selectedID = validPreferredID
                }
            }
            .sheet(isPresented: $showsPDF) { PDFKitView(document: document).frame(minWidth: 760, minHeight: 620) }
        }
    }

    private var validPreferredID: FoodMenuDay.ID? {
        guard let preferredSelectedID,
              days.contains(where: { $0.id == preferredSelectedID }) else {
            return nil
        }
        return preferredSelectedID
    }
}

private struct FoodMenuToolbar: View {
    let days: [FoodMenuDay]
    @Binding var selectedID: FoodMenuDay.ID?
    let showPDF: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label("Gün", systemImage: "calendar")
                .foregroundStyle(.secondary)
            Picker("Gün", selection: $selectedID) {
                ForEach(days) { day in
                    Text(day.heading).tag(Optional(day.id))
                }
            }
            .labelsHidden()
            .frame(minWidth: 220)

            Spacer()

            Button(action: showPDF) {
                Label("Orijinal PDF", systemImage: "doc.richtext")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

private struct FoodMenuDayView: View {
    private struct MenuEntry: Identifiable {
        let id: String
        let number: Int
        let name: String
    }

    let day: FoodMenuDay
    private let entries: [MenuEntry]

    init(day: FoodMenuDay) {
        self.day = day
        var occurrences: [String: Int] = [:]
        entries = day.items.enumerated().map { index, item in
            let occurrence = occurrences[item, default: 0]
            occurrences[item] = occurrence + 1
            return MenuEntry(
                id: "\(item)|\(occurrence)",
                number: index + 1,
                name: item
            )
        }
    }

    var body: some View {
        ScrollView {
            GroupBox {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        FoodMenuItemRow(
                            number: entry.number,
                            name: entry.name
                        )
                        if entry.id != entries.last?.id {
                            Divider()
                        }
                    }
                }

                Link(
                    "Görseller: Yemek.com tarifleri",
                    destination: URL(string: "https://yemek.com/tarifler/")!
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .trailing)
            } label: {
                Label(day.heading, systemImage: "fork.knife")
                    .font(.headline)
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct FoodMenuItemRow: View {
    let number: Int
    let name: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            FoodPhotoView(mealName: name)

            Text(name)
                .font(.body)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(number). \(name)")
    }
}

struct FoodPhotoView: View {
    let mealName: String
    let linksToSource: Bool
    @State private var photo: FoodPhoto?
    @State private var finishedSearching = false

    init(mealName: String, linksToSource: Bool = true) {
        self.mealName = mealName
        self.linksToSource = linksToSource
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)

            if let photo {
                AsyncImage(url: photo.thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                    case .failure:
                        fallbackIcon
                    @unknown default:
                        fallbackIcon
                    }
                }
            } else if finishedSearching {
                fallbackIcon
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: 86, height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
        .overlay {
            if linksToSource, let sourcePageURL = photo?.sourcePageURL {
                Link(destination: sourcePageURL) {
                    Color.clear
                }
                .accessibilityLabel("\(mealName) görselinin kaynak sayfasını aç")
            }
        }
        .task(id: mealName) {
            finishedSearching = false
            photo = await FoodPhotoService.shared.photo(for: mealName)
            finishedSearching = true
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "fork.knife")
            .font(.title3)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
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
