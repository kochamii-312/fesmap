import Foundation

// Firebase Auth REST APIによる認証サービス
actor AuthService {
    static let shared = AuthService()

    private let authBaseURL = "https://identitytoolkit.googleapis.com/v1"
    private let tokenRefreshURL = "https://securetoken.googleapis.com/v1/token"

    // Firebase APIキー（AppConfigから取得）
    private var apiKey: String {
        AppConfig.firebaseAPIKey
    }

    private init() {}

    // MARK: - 認証レスポンス

    private struct AuthResult: Codable {
        let idToken: String
        let refreshToken: String
        let localId: String
        let expiresIn: String
    }

    private struct RefreshResult: Codable {
        // swiftlint:disable identifier_name
        let id_token: String
        let refresh_token: String
        let expires_in: String
        // swiftlint:enable identifier_name
    }

    // MARK: - 認証操作

    // 匿名サインイン
    func signInAnonymously() async throws -> String {
        let result = try await authRequest(
            endpoint: "accounts:signUp",
            body: ["returnSecureToken": true]
        )
        saveAuth(result)
        return result.localId
    }

    // メール・パスワードでサインイン
    func signInWithEmail(_ email: String, _ password: String) async throws -> String {
        let result = try await authRequest(
            endpoint: "accounts:signInWithPassword",
            body: ["email": email, "password": password, "returnSecureToken": true]
        )
        saveAuth(result)
        return result.localId
    }

    // メール・パスワードで新規登録
    func signUpWithEmail(_ email: String, _ password: String) async throws -> String {
        let result = try await authRequest(
            endpoint: "accounts:signUp",
            body: ["email": email, "password": password, "returnSecureToken": true]
        )
        saveAuth(result)
        return result.localId
    }

    // サインアウト
    func signOut() {
        KeychainHelper.deleteAll()
    }

    // MARK: - トークン管理

    // 現在のユーザーIDを取得
    nonisolated func getCurrentUserId() -> String? {
        KeychainHelper.load(key: "authUserId")
    }

    // IDトークンを取得（期限切れの場合はリフレッシュ）
    func getIdToken() async -> String? {
        guard let token = KeychainHelper.load(key: "authToken"),
              let refreshToken = KeychainHelper.load(key: "authRefreshToken") else {
            return nil
        }

        let expiresAt = Int64(KeychainHelper.load(key: "authExpiresAt") ?? "0") ?? 0
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        // 5分前にリフレッシュ
        if now > expiresAt - 5 * 60 * 1000 {
            do {
                return try await refreshIdToken(refreshToken)
            } catch {
                return nil
            }
        }

        return token
    }

    // ログイン状態を確認
    func isAuthenticated() async -> Bool {
        await getIdToken() != nil
    }

    // MARK: - 内部処理

    private func saveAuth(_ result: AuthResult) {
        let expiresIn = Int64(result.expiresIn) ?? 3600
        let expiresAt = Int64(Date().timeIntervalSince1970 * 1000) + expiresIn * 1000

        KeychainHelper.save(key: "authToken", value: result.idToken)
        KeychainHelper.save(key: "authRefreshToken", value: result.refreshToken)
        KeychainHelper.save(key: "authUserId", value: result.localId)
        KeychainHelper.save(key: "authExpiresAt", value: String(expiresAt))
    }

    private func refreshIdToken(_ refreshToken: String) async throws -> String {
        guard let url = URL(string: "\(tokenRefreshURL)?key=\(apiKey)") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=refresh_token&refresh_token=\(refreshToken)"
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.tokenRefreshFailed
        }

        let result = try JSONDecoder().decode(RefreshResult.self, from: data)
        let expiresIn = Int64(result.expires_in) ?? 3600
        let expiresAt = Int64(Date().timeIntervalSince1970 * 1000) + expiresIn * 1000

        KeychainHelper.save(key: "authToken", value: result.id_token)
        KeychainHelper.save(key: "authRefreshToken", value: result.refresh_token)
        KeychainHelper.save(key: "authExpiresAt", value: String(expiresAt))

        return result.id_token
    }

    private func authRequest(
        endpoint: String,
        body: [String: Any]
    ) async throws -> AuthResult {
        guard let url = URL(string: "\(authBaseURL)/\(endpoint)?key=\(apiKey)") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }

        if httpResponse.statusCode != 200 {
            // エラーレスポンスからメッセージを取得
            if let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJSON["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AuthError.firebaseError(Self.getErrorMessage(message))
            }
            throw AuthError.networkError
        }

        return try JSONDecoder().decode(AuthResult.self, from: data)
    }

    private static func getErrorMessage(_ code: String) -> String {
        switch code {
        case "EMAIL_NOT_FOUND":
            return "アカウントが見つかりません"
        case "INVALID_PASSWORD", "INVALID_LOGIN_CREDENTIALS":
            return "メールアドレスまたはパスワードが間違っています"
        case "EMAIL_EXISTS":
            return "このメールアドレスは既に使用されています"
        case "WEAK_PASSWORD":
            return "パスワードが弱すぎます（6文字以上にしてください）"
        case "INVALID_EMAIL":
            return "メールアドレスの形式が正しくありません"
        case "TOO_MANY_ATTEMPTS_TRY_LATER":
            return "ログイン試行回数が多すぎます。しばらくしてからお試しください"
        default:
            return "認証に失敗しました。もう一度お試しください"
        }
    }
}

// 認証エラー
enum AuthError: LocalizedError {
    case invalidURL
    case networkError
    case tokenRefreshFailed
    case firebaseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "無効なURLです"
        case .networkError:
            return "ネットワークエラーが発生しました"
        case .tokenRefreshFailed:
            return "トークンの更新に失敗しました。再ログインしてください"
        case .firebaseError(let message):
            return message
        }
    }
}
