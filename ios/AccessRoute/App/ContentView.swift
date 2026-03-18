import SwiftUI

// メインコンテンツ（TabView）
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("ホーム", systemImage: "map.fill")
                }
                .tag(0)
                .accessibilityLabel("ホームタブ")

            RouteView()
                .tabItem {
                    Label("ルート", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                }
                .tag(1)
                .accessibilityLabel("ルート検索タブ")

            ChatView()
                .tabItem {
                    Label("チャット", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(2)
                .accessibilityLabel("AIチャットタブ")

            DestinationSpotsView()
                .tabItem {
                    Label("スポット", systemImage: "mappin.and.ellipse")
                }
                .tag(3)
                .accessibilityLabel("スポット検索タブ")

            ProfileView()
                .tabItem {
                    Label("設定", systemImage: "gearshape.fill")
                }
                .tag(4)
                .accessibilityLabel("プロファイル設定タブ")
        }
        // チャットから「マップで表示」が押されたらホームタブに切替
        .onChange(of: appState.spotsToShowOnMap) { _, spots in
            if !spots.isEmpty {
                selectedTab = 0
            }
        }
    }
}
