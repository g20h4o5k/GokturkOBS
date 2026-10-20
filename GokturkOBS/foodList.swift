import SwiftUI
import AppKit
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

enum FoodMealSearchStrategy {
    nonisolated private static let locale = Locale(identifier: "tr_TR")
    nonisolated private static let genericWords: Set<String> = [
        "corba", "pilav", "kizartma", "yemek", "etli", "soslu",
        "tereyagli", "zeytinyagli", "yahni", "firinda", "sebzeli",
        "kasarli", "usul", "arasi", "ekmek", "mevsim"
    ]
    nonisolated private static let dishTypeWords: Set<String> = [
        "corba", "pilav", "borek", "kofte", "yahni", "kizartma",
        "makarna", "salata", "tatli", "pide", "pizza", "kebap", "kebabi"
    ]
    nonisolated private static let dishTypeAliases: [String: Set<String>] = [
        "makarna": ["eriste", "spagetti"]
    ]

    nonisolated static func candidates(for mealName: String, limit: Int = 12) -> [String] {
        let expanded = searchableName(mealName)
        let words = expanded.split(whereSeparator: \Character.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }

        var result: [String] = []
        func append(_ words: [String]) {
            let candidate = words.joined(separator: " ")
            guard !candidate.isEmpty,
                  !result.contains(where: { normalized($0) == normalized(candidate) }) else { return }
            result.append(candidate)
        }

        if containsServingPhrase(mealName) {
            append(words + ["sandviç"])
        }
        append(words)
        if words.count > 2 {
            for keptCount in stride(from: words.count - 1, through: 2, by: -1) {
                for indices in combinations(of: Array(words.indices), taking: keptCount) {
                    append(indices.map { words[$0] })
                    if result.count >= limit { return result }
                }
            }
        }
        if words.count == 2 {
            let meaningfulWords = words.filter { word in
                let normalizedWord = stem(normalized(word))
                return !genericWords.contains(normalizedWord)
                    && !dishTypeWords.contains(normalizedWord)
            }
            if meaningfulWords.count == 1 {
                append(meaningfulWords)
            }
        }
        return Array(result.prefix(limit))
    }

    nonisolated static func matchScore(expected: String, actual: String) -> Double {
        let expectedWords = tokenSet(searchableName(expected))
        let actualWords = tokenSet(actual)
        guard !expectedWords.isEmpty, !actualWords.isEmpty else { return 0 }

        let distinctive = expectedWords.filter { word in
            !genericWords.contains(word)
                && !genericWords.contains(where: { generic in
                    word.count > generic.count && word.contains(generic)
                })
        }
        let focus = distinctive.isEmpty ? expectedWords : distinctive
        let focusMatches = matchedCount(from: focus, in: actualWords)
        let allMatches = matchedCount(from: expectedWords, in: actualWords)
        let actualMatches = matchedCount(from: actualWords, in: expectedWords)
        let focusRecall = Double(focusMatches) / Double(focus.count)
        let allRecall = Double(allMatches) / Double(expectedWords.count)
        let precision = Double(actualMatches) / Double(actualWords.count)
        return focusRecall * 0.6 + allRecall * 0.35 + precision * 0.05
    }

    nonisolated static func isValidMatch(
        candidate: String,
        originalMealName: String,
        actual: String
    ) -> Bool {
        let candidateWords = wordList(candidate)
        let originalWords = wordList(searchableName(originalMealName))
        let actualWords = Set(wordList(actual))
        guard !candidateWords.isEmpty, !actualWords.isEmpty else { return false }

        let candidateIsCovered = candidateWords.allSatisfy { expectedWord in
            actualWords.contains { wordsMatch(expectedWord, $0) }
        }
        guard candidateIsCovered else { return false }

        let requiredDistinctiveWords = originalWords.filter { word in
            !genericWords.contains(word) && !dishTypeWords.contains(word)
        }
        guard requiredDistinctiveWords.allSatisfy({ expectedWord in
            actualWords.contains { wordsMatch(expectedWord, $0) }
        }) else { return false }

        let requiredTypes = originalWords.filter(dishTypeWords.contains)
        return requiredTypes.allSatisfy { expectedType in
            actualWords.contains { wordsMatch(expectedType, $0) }
                || dishTypeAliases[expectedType, default: []].contains { alias in
                    candidateWords.contains { wordsMatch(alias, $0) }
                        && actualWords.contains { wordsMatch(alias, $0) }
                }
        }
    }

    nonisolated static func fallbackCategories(for mealName: String) -> [String] {
        let words = wordList(mealName)
        let categoryNames: [String: String] = [
            "corba": "çorba", "pilav": "pilav", "borek": "börek",
            "kofte": "köfte", "yahni": "yahni", "kizartma": "kızartma",
            "makarna": "makarna", "salata": "salata", "pide": "pide",
            "pizza": "pizza", "hamburger": "hamburger", "kebap": "kebap", "turlu": "türlü"
        ]

        var categories = words.compactMap { categoryNames[$0] }
        if words.contains(where: { $0 == "tavuk" || $0.hasPrefix("tavuk") }) {
            categories.append("tavuk")
        }
        if words.contains(where: { $0 == "et" || $0.hasPrefix("etli") }) {
            categories.append("et")
        }
        return categories.reduce(into: [String]()) { result, category in
            if !result.contains(category) { result.append(category) }
        }
    }

    nonisolated static func fallbackQueries(for category: String) -> [String] {
        [category, "\(category) yemeği"]
    }

    nonisolated static func contextualQueries(
        for candidate: String,
        originalMealName: String
    ) -> [String] {
        let candidateWords = Set(wordList(candidate))
        let categories = fallbackCategories(for: originalMealName)
        guard !categories.isEmpty else { return [candidate] }

        var queries: [String] = []
        for category in categories {
            let categoryWords = wordList(category)
            let alreadyContainsCategory = categoryWords.allSatisfy(candidateWords.contains)
            let query = alreadyContainsCategory ? candidate : "\(candidate) \(category)"
            if !queries.contains(where: { normalized($0) == normalized(query) }) {
                queries.append(query)
            }
        }
        return queries
    }

    nonisolated static func recipeSlug(for mealName: String) -> String {
        wordList(mealName).joined(separator: "-")
    }

    nonisolated private static func containsServingPhrase(_ mealName: String) -> Bool {
        let words = mealName.split(whereSeparator: \Character.isWhitespace).map { normalized(String($0)) }
        guard words.count > 1 else { return false }

        return words.indices.dropLast().contains { index in
            words[index] == "ekmek" && words[index + 1] == "arasi"
        }
    }

    nonisolated private static func searchableName(_ mealName: String) -> String {
        var value = mealName
        let abbreviations = [
            (#"(?i)(?<![\p{L}])T\s*\.?\s*Y\s*\.?(?![\p{L}])"#, "tereyağlı"),
            (#"(?i)(?<![\p{L}])Z\s*\.?\s*Y\s*\.?(?![\p{L}])"#, "zeytinyağlı")
        ]
        for (pattern, replacement) in abbreviations {
            value = value.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        let words = value.split(whereSeparator: \Character.isWhitespace).map(String.init)
        var retainedWords: [String] = []
        var index = 0
        while index < words.count {
            if index + 1 < words.count,
               normalized(words[index]) == "ekmek",
               normalized(words[index + 1]) == "arasi" {
                index += 2
            } else {
                retainedWords.append(words[index])
                index += 1
            }
        }
        value = retainedWords.joined(separator: " ")
        return value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func combinations(of values: [Int], taking count: Int) -> [[Int]] {
        guard count > 0, count <= values.count else { return [] }
        if count == 1 { return values.map { [$0] } }
        if count == values.count { return [values] }
        guard let first = values.first else { return [] }
        let tail = Array(values.dropFirst())
        return combinations(of: tail, taking: count - 1).map { [first] + $0 }
            + combinations(of: tail, taking: count)
    }

    nonisolated private static func tokenSet(_ value: String) -> Set<String> {
        let words = wordList(value)
        var tokens = Set(words)
        if words.count > 1 {
            for index in 0..<(words.count - 1) {
                tokens.insert(words[index] + words[index + 1])
            }
        }
        return tokens
    }

    nonisolated private static func wordList(_ value: String) -> [String] {
        normalized(value)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map(stem)
    }

    nonisolated private static func stem(_ word: String) -> String {
        let replacements: [String: String] = [
            "corbasi": "corba", "pilavi": "pilav", "koftesi": "kofte",
            "kizartmasi": "kizartma", "yahnisi": "yahni", "yemegi": "yemek",
            "boregi": "borek", "dilimi": "dilim", "usulu": "usul",
            "kebabi": "kebap"
        ]
        if let replacement = replacements[word] { return replacement }
        if word.count >= 6, let last = word.last, "iu".contains(last) {
            return String(word.dropLast())
        }
        return word
    }

    nonisolated private static func matchedCount(from source: Set<String>, in target: Set<String>) -> Int {
        source.filter { word in target.contains(where: { wordsMatch(word, $0) }) }.count
    }

    nonisolated private static func wordsMatch(_ first: String, _ second: String) -> Bool {
        if first == second { return true }
        if min(first.count, second.count) >= 4,
           (first.contains(second) || second.contains(first)) {
            return true
        }
        guard min(first.count, second.count) >= 5,
              abs(first.count - second.count) <= 1 else { return false }
        return editDistanceAtMostOne(first, second)
    }

    nonisolated private static func editDistanceAtMostOne(_ first: String, _ second: String) -> Bool {
        let lhs = Array(first)
        let rhs = Array(second)
        var leftIndex = 0
        var rightIndex = 0
        var edits = 0
        while leftIndex < lhs.count, rightIndex < rhs.count {
            if lhs[leftIndex] == rhs[rightIndex] {
                leftIndex += 1
                rightIndex += 1
            } else {
                edits += 1
                if edits > 1 { return false }
                if lhs.count > rhs.count {
                    leftIndex += 1
                } else if rhs.count > lhs.count {
                    rightIndex += 1
                } else {
                    leftIndex += 1
                    rightIndex += 1
                }
            }
        }
        if leftIndex < lhs.count || rightIndex < rhs.count { edits += 1 }
        return edits <= 1
    }

    nonisolated private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "ş", with: "s")
            .replacingOccurrences(of: "ğ", with: "g")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ç", with: "c")
    }
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
    private var searchCache: [String: [Recipe]] = [:]
    private var directPhotoCache: [String: CachedResult] = [:]
    private var imageDataCache: [URL: Data] = [:]
    private var imageDownloadTasks: [URL: Task<Data?, Never>] = [:]
    private var persistentImageDirectory: URL?

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

        let mealNames = FoodMealSearchStrategy.candidates(for: mealName)
        guard !mealNames.isEmpty else {
            cache[cacheKey] = .missing
            return nil
        }

        for candidateMealName in mealNames {
            var recipesByURL: [URL: Recipe] = [:]
            let contextualQueries = FoodMealSearchStrategy.contextualQueries(
                for: candidateMealName,
                originalMealName: mealName
            )
            for searchQuery in contextualQueries {
                if let recipes = try? await searchRecipes(query: searchQuery) {
                    for recipe in recipes {
                        recipesByURL[recipe.permalink] = recipe
                    }
                }
                if let best = bestRecipe(
                    for: candidateMealName,
                    originalMealName: mealName,
                    among: Array(recipesByURL.values)
                ),
                   best.score >= 0.82,
                   let photo = photo(from: best.recipe) {
                    cache[cacheKey] = .found(photo)
                    return photo
                }
            }

            if let photo = await directRecipePhoto(
                for: candidateMealName,
                originalMealName: mealName
            ) {
                cache[cacheKey] = .found(photo)
                return photo
            }

            let candidateWasSearched = contextualQueries.contains { query in
                normalized(query) == normalized(candidateMealName)
            }
            if !candidateWasSearched,
               let recipes = try? await searchRecipes(query: candidateMealName) {
                for recipe in recipes {
                    recipesByURL[recipe.permalink] = recipe
                }
                if let best = bestRecipe(
                    for: candidateMealName,
                    originalMealName: mealName,
                    among: Array(recipesByURL.values)
                ),
                   best.score >= 0.82,
                   let photo = photo(from: best.recipe) {
                    cache[cacheKey] = .found(photo)
                    return photo
                }
            }
        }

        for category in FoodMealSearchStrategy.fallbackCategories(for: mealName) {
            if let photo = stockPhoto(for: category) {
                cache[cacheKey] = .found(photo)
                return photo
            }

            var recipesByURL: [URL: Recipe] = [:]
            for query in FoodMealSearchStrategy.fallbackQueries(for: category) {
                guard let recipes = try? await searchRecipes(query: query) else { continue }
                for recipe in recipes {
                    recipesByURL[recipe.permalink] = recipe
                }
            }
            guard let best = bestRecipe(
                    for: category,
                    originalMealName: category,
                    among: Array(recipesByURL.values)
                  ),
                  best.score >= 0.82,
                  let photo = photo(from: best.recipe) else { continue }
            cache[cacheKey] = .found(photo)
            return photo
        }

        cache[cacheKey] = .missing
        return nil
    }

    func imageData(for url: URL, persistToApplicationSupport: Bool = false) async -> Data? {
        if let cached = imageDataCache[url] {
            if persistToApplicationSupport {
                saveImageData(cached, for: url)
            }
            return cached
        }
        if let stored = loadImageData(for: url) {
            imageDataCache[url] = stored
            return stored
        }
        if let activeDownload = imageDownloadTasks[url] {
            let data = await activeDownload.value
            if persistToApplicationSupport, let data {
                saveImageData(data, for: url)
            }
            return data
        }

        let task = Task<Data?, Never> {
            let request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 20
            )
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled,
                      !data.isEmpty,
                      let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode),
                      httpResponse.mimeType?.hasPrefix("image/") == true else {
                    return nil
                }
                return data
            } catch {
                return nil
            }
        }
        imageDownloadTasks[url] = task
        let data = await task.value
        imageDownloadTasks[url] = nil
        if let data {
            imageDataCache[url] = data
            if persistToApplicationSupport {
                saveImageData(data, for: url)
            }
        }
        return data
    }

    func prefetch(mealNames: [String], menuDayID: String) async {
        preparePersistentCache(for: menuDayID)
        var seen = Set<String>()
        let uniqueNames = mealNames.filter { mealName in
            seen.insert(mealName).inserted
        }

        for mealName in uniqueNames {
            guard !Task.isCancelled else { return }
            guard let photo = await photo(for: mealName) else { continue }
            _ = await imageData(for: photo.thumbnailURL, persistToApplicationSupport: true)
        }
    }

    private func preparePersistentCache(for menuDayID: String) {
        let fileManager = FileManager.default
        guard let applicationSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return }

        let appDirectory = applicationSupport
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "GokturkOBS", isDirectory: true)
        let cacheRoot = appDirectory.appendingPathComponent("FoodPhotos", isDirectory: true)
        let dayDirectory = cacheRoot.appendingPathComponent("CurrentMenuDay", isDirectory: true)
        let markerURL = cacheRoot.appendingPathComponent("menu-day.txt", isDirectory: false)

        do {
            try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
            let storedDayID = try? String(contentsOf: markerURL, encoding: .utf8)
            if storedDayID != menuDayID, fileManager.fileExists(atPath: dayDirectory.path) {
                try fileManager.removeItem(at: dayDirectory)
                imageDataCache.removeAll()
            }
            try fileManager.createDirectory(at: dayDirectory, withIntermediateDirectories: true)
            try menuDayID.write(to: markerURL, atomically: true, encoding: .utf8)
            persistentImageDirectory = dayDirectory
        } catch {
            persistentImageDirectory = nil
        }
    }

    private func loadImageData(for url: URL) -> Data? {
        guard let fileURL = persistentFileURL(for: url) else { return nil }
        return try? Data(contentsOf: fileURL, options: .mappedIfSafe)
    }

    private func saveImageData(_ data: Data, for url: URL) {
        guard let fileURL = persistentFileURL(for: url) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func persistentFileURL(for url: URL) -> URL? {
        guard let persistentImageDirectory else { return nil }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return persistentImageDirectory.appendingPathComponent(String(hash, radix: 16) + ".image")
    }

    private func searchRecipes(query: String) async throws -> [Recipe] {
        let cacheKey = query.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "tr_TR")
        )
        if let cached = searchCache[cacheKey] {
            return cached
        }
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
        let recipes = try JSONDecoder().decode(SearchResponse.self, from: data).data.recipes
        searchCache[cacheKey] = recipes
        return recipes
    }

    private func directRecipePhoto(
        for candidateMealName: String,
        originalMealName: String
    ) async -> FoodPhoto? {
        let slug = FoodMealSearchStrategy.recipeSlug(for: candidateMealName)
        guard !slug.isEmpty else { return nil }

        if let cached = directPhotoCache[slug] {
            switch cached {
            case .found(let photo): return photo
            case .missing: return nil
            }
        }

        guard let pageURL = URL(string: "https://yemek.com/tarif/\(slug)/") else {
            directPhotoCache[slug] = .missing
            return nil
        }

        var request = URLRequest(url: pageURL)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("GokturkOBS/2.0 (macOS food menu)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .returnCacheDataElseLoad

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode,
              let html = String(data: data, encoding: .utf8),
              let recipeTitle = metaContent(named: "og:title", in: html),
              FoodMealSearchStrategy.isValidMatch(
                candidate: candidateMealName,
                originalMealName: originalMealName,
                actual: recipeTitle
              ),
              let imageAddress = metaContent(named: "og:image", in: html),
              let imageURL = URL(string: imageAddress) else {
            directPhotoCache[slug] = .missing
            return nil
        }

        let photo = FoodPhoto(thumbnailURL: imageURL, sourcePageURL: pageURL)
        directPhotoCache[slug] = .found(photo)
        return photo
    }

    private func metaContent(named property: String, in html: String) -> String? {
        let escapedProperty = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            #"<meta[^>]+property=[\"']"# + escapedProperty + #"[\"'][^>]+content=[\"']([^\"']+)[\"'][^>]*>"#,
            #"<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+property=[\"']"# + escapedProperty + #"[\"'][^>]*>"#
        ]

        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            guard let match = expression.firstMatch(in: html, range: range),
                  let contentRange = Range(match.range(at: 1), in: html) else { continue }
            return String(html[contentRange])
                .replacingOccurrences(of: "&amp;", with: "&")
        }
        return nil
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
        } else if normalized == "TAVUK" {
            imageAddress = "https://images.pexels.com/photos/2338407/pexels-photo-2338407.jpeg?auto=compress&w=320&h=240&fit=crop"
            sourceAddress = "https://www.pexels.com/photo/cooked-food-on-white-ceramic-plate-2338407/"
        } else if normalized == "MAKARNA" {
            imageAddress = "https://images.pexels.com/photos/1279330/pexels-photo-1279330.jpeg?auto=compress&w=320&h=240&fit=crop"
            sourceAddress = "https://www.pexels.com/photo/pasta-with-tomato-and-basil-1279330/"
        } else if normalized == "PİZZA" {
            imageAddress = "https://images.pexels.com/photos/825661/pexels-photo-825661.jpeg?auto=compress&w=320&h=240&fit=crop"
            sourceAddress = "https://www.pexels.com/photo/pizza-on-brown-wooden-table-825661/"
        } else if normalized == "BÖREK" {
            imageAddress = "https://imgrosetta.yemek.com/file/159630/159630-1250x833.jpg"
            sourceAddress = "https://yemek.com/tarif/klasik-tepsi-boregi/"
        } else if normalized == "HAMBURGER" {
            imageAddress = "https://images.pexels.com/photos/1639557/pexels-photo-1639557.jpeg?auto=compress&w=320&h=240&fit=crop"
            sourceAddress = "https://www.pexels.com/photo/close-up-photo-of-burger-1639557/"
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

    private func bestRecipe(
        for mealName: String,
        originalMealName: String,
        among recipes: [Recipe]
    ) -> (recipe: Recipe, score: Double)? {
        let candidateWordCount = mealName.split(whereSeparator: \Character.isWhitespace).count
        return recipes.compactMap { recipe -> (recipe: Recipe, score: Double)? in
            let recipeName = recipe.title.split(separator: ":").last.map(String.init) ?? recipe.title
            guard FoodMealSearchStrategy.isValidMatch(
                candidate: mealName,
                originalMealName: originalMealName,
                actual: recipeName
            ) else { return nil }
            let originalScore = FoodMealSearchStrategy.matchScore(
                expected: originalMealName,
                actual: recipeName
            )
            guard candidateWordCount > 1 else {
                return (recipe, originalScore)
            }
            let candidateScore = FoodMealSearchStrategy.matchScore(
                expected: mealName,
                actual: recipeName
            ) * 0.9
            return (recipe, max(originalScore, candidateScore))
        }
        .max { $0.score < $1.score }
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
    @State private var imageData: Data?
    @State private var finishedSearching = false

    init(mealName: String, linksToSource: Bool = true) {
        self.mealName = mealName
        self.linksToSource = linksToSource
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)

            if let imageData, let image = NSImage(data: imageData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if photo != nil, !finishedSearching {
                ProgressView()
                    .controlSize(.small)
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
            imageData = nil
            let resolvedPhoto = await FoodPhotoService.shared.photo(for: mealName)
            guard !Task.isCancelled else { return }
            photo = resolvedPhoto
            if let resolvedPhoto {
                imageData = await FoodPhotoService.shared.imageData(for: resolvedPhoto.thumbnailURL)
            }
            guard !Task.isCancelled else { return }
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

func prefetchFoodPhotos(for mealNames: [String], menuDayID: String) async {
    await FoodPhotoService.shared.prefetch(mealNames: mealNames, menuDayID: menuDayID)
}

private extension FoodListLoadState {
    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}
