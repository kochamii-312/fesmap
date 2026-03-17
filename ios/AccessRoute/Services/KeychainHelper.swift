import Foundation
import Security

// Keychainによるセキュアなトークン保管ヘルパー
enum KeychainHelper {
    private static let service = "com.accessroute.app"

    // Keychainに文字列を保存
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // 既存の値を削除してから保存
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    // Keychainから文字列を取得
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    // Keychainから値を削除
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }

    // 全トークンを削除
    static func deleteAll() {
        let keys = ["authToken", "authRefreshToken", "authUserId", "authExpiresAt"]
        for key in keys {
            delete(key: key)
        }
    }
}
