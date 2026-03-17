import SwiftUI

// アプリのエントリーポイント
@main
struct AccessRouteApp: App {
    // オンボーディング完了フラグ
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @StateObject private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            if !onboardingCompleted {
                OnboardingView(isOnboardingCompleted: $onboardingCompleted)
            } else if !authViewModel.isAuthenticated {
                LoginView(authViewModel: authViewModel)
            } else {
                ContentView()
                    .environmentObject(authViewModel)
            }
        }
    }
}
