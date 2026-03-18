import SwiftUI

// アプリのエントリーポイント
@main
struct AccessRouteApp: App {
    // オンボーディング完了フラグ
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    
    // 認証、位置情報、アプリ全体の状態を管理するViewModel
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if !onboardingCompleted {
                    OnboardingView(isOnboardingCompleted: $onboardingCompleted)
                } else if !authViewModel.isAuthenticated {
                    LoginView(authViewModel: authViewModel)
                } else {
                    ContentView()
                        .environmentObject(authViewModel)
                        .environmentObject(locationManager)
                        .environmentObject(appState)
                }
            }
            .preferredColorScheme(.light) // アプリ全体をライトモードに固定
        }
    }
}
