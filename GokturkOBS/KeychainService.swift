import Foundation
import Security

struct StoredCredentials {
    let username: String
    let password: String
}

enum KeychainServiceError: LocalizedError {
    case operationFailed(OSStatus)
    case invalidStoredCredentials

    var errorDescription: String? {
        switch self {
        case .operationFailed(let status):
            let message = SecCopyErrorMessageString(status, nil) as String?
            return "Keychain işlemi başarısız: \(message ?? "bilinmeyen hata")"
        case .invalidStoredCredentials:
            return "Keychain'deki giriş bilgileri okunamadı"
        }
    }
}

struct KeychainService {
    private let service = "com.gokturk.GokturkOBS.credentials"

    func save(username: String, password: String) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw KeychainServiceError.invalidStoredCredentials
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainServiceError.operationFailed(addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainServiceError.operationFailed(status)
        }

        let oldItemsQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        let queryStatus = SecItemCopyMatching(oldItemsQuery as CFDictionary, &result)
        guard queryStatus == errSecSuccess || queryStatus == errSecItemNotFound else {
            throw KeychainServiceError.operationFailed(queryStatus)
        }
        let items = result as? [[String: Any]] ?? []
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  account != username else { continue }
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
            guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                throw KeychainServiceError.operationFailed(deleteStatus)
            }
        }
    }

    func load() throws -> StoredCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainServiceError.operationFailed(status)
        }
        guard let item = result as? [String: Any],
              let username = item[kSecAttrAccount as String] as? String,
              let passwordData = item[kSecValueData as String] as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            throw KeychainServiceError.invalidStoredCredentials
        }
        return StoredCredentials(username: username, password: password)
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.operationFailed(status)
        }
    }
}
