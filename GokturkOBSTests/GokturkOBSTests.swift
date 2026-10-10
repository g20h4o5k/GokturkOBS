import Foundation
import Testing

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
