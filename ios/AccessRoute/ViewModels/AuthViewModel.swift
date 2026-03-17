import SwiftUI

// 認証状態管理ViewModel
@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var userId: String?
    @Published var errorMessage: String?

    init() {
        // 保存済みユーザーIDを復元
        userId = AuthService.shared.getCurrentUserId()
        isAuthenticated = userId != nil
    }

    // ゲスト（匿名）ログイン
    func signInAsGuest() async {
        isLoading = true
        errorMessage = nil
        do {
            let id = try await AuthService.shared.signInAnonymously()
            userId = id
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // メール・パスワードでログイン
    func signInWithEmail(_ email: String, _ password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let id = try await AuthService.shared.signInWithEmail(email, password)
            userId = id
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // メール・パスワードで新規登録
    func signUpWithEmail(_ email: String, _ password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let id = try await AuthService.shared.signUpWithEmail(email, password)
            userId = id
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // サインアウト
    func signOut() async {
        await AuthService.shared.signOut()
        userId = nil
        isAuthenticated = false
    }

    // IDトークンを取得（API呼び出し用）
    func getToken() async -> String? {
        await AuthService.shared.getIdToken()
    }
}
