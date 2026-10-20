import Foundation
import Testing
@testable import GokturkOBS

private enum RetryPolicy {
    static func boundedRetryAfter(_ value: String?) -> TimeInterval? {
        guard let value, let seconds = TimeInterval(value) else { return nil }
        return min(max(seconds, 1), 60)
    }

    static func isTemporary(statusCode: Int) -> Bool {
        [429, 502, 503, 504].contains(statusCode)
    }

    static func isExpiredMobileResponse(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["success"] as? Bool) == false else { return false }
        let message = [object["msg"], object["status"], object["message"]]
            .compactMap { $0 as? String }
            .joined(separator: " ")
            .lowercased()
        return ["session", "oturum", "login", "giriş", "unauthorized", "access denied"]
            .contains { message.contains($0) }
    }
}

@MainActor
struct TaramaDecodingTests {
    @Test
    func listDecodesFlexibleValuesAndKeepsExamType() throws {
        let data = Data(#"{"success":true,"result":[{"examType":"DBS","sinavKod":42,"sinavAd":"Tarama","sinavTarih":"10.10.2026","point":"387,5"}]}"#.utf8)
        let response = try JSONDecoder().decode(TaramaListResponse.self, from: data)

        #expect(response.success)
        #expect(response.result?.first?.examType == "DBS")
        #expect(response.result?.first?.examCode == "42")
        #expect(response.result?.first?.point == 387.5)
    }

    @Test
    func detailHandlesUnequalParallelArrays() throws {
        let data = Data(#"{"success":true,"data":{"lessons":[{"lesson":"Türkçe"},{"lesson":"Matematik"}],"ss":[20,0],"d":[18],"y":[2],"n":[17.33],"p":[],"derece":[],"sayi":[],"examKey":["AB-CD"],"answer":["AB_CD"]}}"#.utf8)
        let response = try JSONDecoder().decode(TaramaDetailResponse.self, from: data)

        #expect(response.data?.lessonResult(at: 0)?.correct == 18)
        #expect(response.data?.lessonResult(at: 1) == nil)
        #expect(response.data?.answerKeys.first == "AB-CD")
    }

    @Test
    func subjectAnalysisPreservesBackendPerformanceScale() throws {
        let data = Data(#"{"success":true,"data":[{"lesson":"Matematik","konuAd":"Oran","SSay":"4","Dog":3,"Yan":"1","Bas":"0,75"}]}"#.utf8)
        let response = try JSONDecoder().decode(TaramaSubjectAnalysisResponse.self, from: data)

        #expect(response.data?.first?.performance == 0.75)
    }

    @Test
    func subjectAnalysisGroupsNonAdjacentLessonsWithoutDroppingEntries() throws {
        let data = Data(#"{"success":true,"data":[{"lesson":"Matematik","konuAd":"Oran"},{"lesson":"Türkçe","konuAd":"Fiil"},{"lesson":"Matematik","konuAd":"Geometri"}]}"#.utf8)
        let response = try JSONDecoder().decode(TaramaSubjectAnalysisResponse.self, from: data)
        let groups = TaramaAnalysisGrouping.group(response.data ?? [])

        #expect(groups.map(\.lesson) == ["Matematik", "Türkçe"])
        #expect(groups.first?.entries.map(\.topic) == ["Oran", "Geometri"])
    }

    @Test
    func webExamRecordKeepsServerExamType() throws {
        let data = Data(#"{"sinavKod":"17","sinavAd":"Ölçme","sinavTarih":"10.10.2026","examType":"dbs"}"#.utf8)
        let record = try JSONDecoder().decode(WebExamRecord.self, from: data)

        #expect(record.examType == "DBS")
        #expect(TaramaExam(indexRecord: record).examCode == "17")
    }

    @Test
    func limeExamReportLessonOrderAndCommaNumbersArePreserved() throws {
        let data = Data(#"{"success":true,"data":{"SR1":20,"D1":18,"Y1":2,"N1":"17,33","SR2":20,"D2":15,"Y2":3,"N2":"14,00","Puan":"421,5","N7":"82,25"}}"#.utf8)
        let report = try JSONDecoder().decode(ExamSchoolReport.self, from: data)

        #expect(report.subjectResults().map(\.lesson) == ["TÜRKÇE", "MATEMATİK"])
        #expect(report.subjectResults().first?.net == 17.33)
        #expect(report.score == 421.5)
        #expect(report.totalNet == 82.25)
    }

    @Test
    func zeroQuestionCountFallsBackToCorrectWrongAndBlankSum() throws {
        let data = Data(#"{"success":true,"data":{"SR1":0,"D1":12,"Y1":3,"B1":5,"N1":11}}"#.utf8)
        let report = try JSONDecoder().decode(ExamSchoolReport.self, from: data)

        #expect(report.subjectResults().first?.questionCount == 20)
        #expect(report.subjectResults().first?.blank == 5)
    }
}

struct SessionRecoveryPolicyTests {
    @Test
    func temporaryServerStatusesAreLimited() {
        #expect(RetryPolicy.isTemporary(statusCode: 429))
        #expect(RetryPolicy.isTemporary(statusCode: 503))
        #expect(!RetryPolicy.isTemporary(statusCode: 500))
    }

    @Test
    func retryAfterIsBounded() {
        #expect(RetryPolicy.boundedRetryAfter("120") == 60)
        #expect(RetryPolicy.boundedRetryAfter("0") == 1)
        #expect(RetryPolicy.boundedRetryAfter(nil) == nil)
    }

    @Test
    func mobileSessionMessageDoesNotConfuseDataErrorsWithExpiry() {
        let expired = Data(#"{"success":false,"msg":"Oturum süresi doldu, giriş yapın."}"#.utf8)
        let unrelatedFailure = Data(#"{"success":false,"msg":"Veri formatı geçersiz."}"#.utf8)
        let malformed = Data("not-json".utf8)

        #expect(RetryPolicy.isExpiredMobileResponse(expired))
        #expect(!RetryPolicy.isExpiredMobileResponse(unrelatedFailure))
        #expect(!RetryPolicy.isExpiredMobileResponse(malformed))
    }

    @Test
    func cancellationStopsSleepImmediately() async {
        let task = Task {
            try await Task.sleep(for: .seconds(8))
        }
        task.cancel()

        do {
            try await task.value
            Issue.record("İptal edilen bekleme başarılı olmamalıydı.")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("İptal CancellationError üretmeliydi: \(error)")
        }
    }
}

struct FoodMealSearchStrategyTests {
    @Test
    func expandsAbbreviationsAndBuildsGenericFallbacks() {
        let zeytinyagli = FoodMealSearchStrategy.candidates(for: "ZY BEZELYE")
        let stuffedRice = FoodMealSearchStrategy.candidates(for: "İÇLİ PİRİNÇ PİLAVI")
        let starSoup = FoodMealSearchStrategy.candidates(for: "YILDIZ ÇORBA")
        let noodlePasta = FoodMealSearchStrategy.candidates(for: "ERİŞTE MAKARNA")

        #expect(zeytinyagli.first == "zeytinyağlı BEZELYE")
        #expect(stuffedRice.contains("PİRİNÇ PİLAVI"))
        #expect(starSoup == ["YILDIZ ÇORBA", "YILDIZ"])
        #expect(noodlePasta == ["ERİŞTE MAKARNA", "ERİŞTE"])
    }

    @Test
    func removesServingPhraseWithoutRemovingTheDish() {
        let candidates = FoodMealSearchStrategy.candidates(for: "EKMEK ARASI ET DÖNER")

        #expect(candidates.first == "ET DÖNER sandviç")
        #expect(candidates.contains("ET DÖNER"))
        #expect(FoodMealSearchStrategy.candidates(for: "EKMEK ARASI TAVUK").first == "TAVUK sandviç")
    }

    @Test
    func buildsDirectRecipeSlugsWithTurkishCharacters() {
        #expect(FoodMealSearchStrategy.recipeSlug(for: "TAVUK ROTİ") == "tavuk-roti")
        #expect(FoodMealSearchStrategy.recipeSlug(for: "İÇLİ PİRİNÇ PİLAVI") == "icli-pirinc-pilav")
    }

    @Test
    func searchesWithCategoryContextBeforeThePlainCandidate() {
        #expect(FoodMealSearchStrategy.contextualQueries(
            for: "ERİŞTE",
            originalMealName: "ERİŞTE MAKARNA"
        ) == ["ERİŞTE makarna"])
        #expect(FoodMealSearchStrategy.contextualQueries(
            for: "TAVUK ROTİ",
            originalMealName: "TAVUK ROTİ"
        ) == ["TAVUK ROTİ"])
    }

    @Test
    func matchesTurkishInflectionsAndMinorSpellingDifferences() {
        let cauliflower = FoodMealSearchStrategy.matchScore(
            expected: "KARNABAHAR KIZARTMA",
            actual: "Çıtırlığının Sırları Var: Karnabahar Kızartması"
        )
        let potato = FoodMealSearchStrategy.matchScore(
            expected: "ELMA DİLİMİ PATATES",
            actual: "Elma Dilim Patates"
        )
        let cabbage = FoodMealSearchStrategy.matchScore(
            expected: "ZEYTİNYAĞLI KABUSKA",
            actual: "Zeytinyağlı Kapuska"
        )

        #expect(cauliflower >= 0.82)
        #expect(potato >= 0.82)
        #expect(cabbage >= 0.82)
    }

    @Test
    func rejectsRecipesWithANameOrDishTypeMismatch() {
        #expect(!FoodMealSearchStrategy.isValidMatch(
            candidate: "MEVLANA BÖREĞİ",
            originalMealName: "MEVLANA BÖREĞİ",
            actual: "Mevlana Şerbeti"
        ))
        #expect(!FoodMealSearchStrategy.isValidMatch(
            candidate: "MEVLANA BÖREĞİ",
            originalMealName: "MEVLANA BÖREĞİ",
            actual: "Biber Böreği"
        ))
        #expect(!FoodMealSearchStrategy.isValidMatch(
            candidate: "TAVUK ROTİ",
            originalMealName: "TAVUK ROTİ",
            actual: "Tavuk Sote"
        ))
        #expect(!FoodMealSearchStrategy.isValidMatch(
            candidate: "SOSLU TAVUK",
            originalMealName: "SOSLU TAVUK PANE",
            actual: "Köri Soslu Tavuk"
        ))
        #expect(!FoodMealSearchStrategy.isValidMatch(
            candidate: "ERİŞTE MAKARNA",
            originalMealName: "ERİŞTE MAKARNA",
            actual: "Makarna Pasta"
        ))
        #expect(FoodMealSearchStrategy.isValidMatch(
            candidate: "ERİŞTE",
            originalMealName: "ERİŞTE MAKARNA",
            actual: "Erişte Tarifi"
        ))
        #expect(FoodMealSearchStrategy.isValidMatch(
            candidate: "YILDIZ",
            originalMealName: "YILDIZ ÇORBA",
            actual: "Yıldız Şehriye Çorbası"
        ))
    }

    @Test
    func producesSafeStockCategoriesForUnknownMealNames() {
        #expect(FoodMealSearchStrategy.fallbackCategories(for: "MEVLANA BÖREĞİ") == ["börek"])
        #expect(FoodMealSearchStrategy.fallbackCategories(for: "SARAY USULÜ TAVUK") == ["tavuk"])
        #expect(FoodMealSearchStrategy.fallbackCategories(for: "ETLİ BİLİNMEYEN YEMEK") == ["et"])
        #expect(FoodMealSearchStrategy.fallbackCategories(for: "TAVUKLU MAKARNA") == ["makarna", "tavuk"])
        #expect(FoodMealSearchStrategy.fallbackCategories(for: "MEVSİM TÜRLÜSÜ") == ["türlü"])
        #expect(FoodMealSearchStrategy.fallbackCategories(for: "EKMEK ARASI HAMBURGER KÖFTE").first == "hamburger")
        #expect(!FoodMealSearchStrategy.fallbackCategories(for: "TATLI KABAK YAHNİ").contains("tatlı"))
        #expect(FoodMealSearchStrategy.fallbackQueries(for: "et") == ["et", "et yemeği"])
    }
}
