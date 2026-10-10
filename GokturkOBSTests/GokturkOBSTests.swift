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
