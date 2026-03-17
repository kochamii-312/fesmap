import SwiftUI

// プレビュー用モックデータとヘルパー

// MARK: - モックデータ

@MainActor
enum PreviewMockData {
    // スポット概要のモックデータ
    static let spots: [SpotSummary] = [
        SpotSummary(
            spotId: "preview_spot_1",
            name: "バリアフリートイレ 丸の内",
            category: .restroom,
            location: LatLng(lat: 35.6815, lng: 139.7675),
            accessibilityScore: 95,
            distanceFromRoute: 50
        ),
        SpotSummary(
            spotId: "preview_spot_2",
            name: "休憩ベンチ 日比谷通り",
            category: .rest_area,
            location: LatLng(lat: 35.6808, lng: 139.7665),
            accessibilityScore: 80,
            distanceFromRoute: 120
        ),
        SpotSummary(
            spotId: "preview_spot_3",
            name: "カフェ アクセス",
            category: .cafe,
            location: LatLng(lat: 35.6820, lng: 139.7680),
            accessibilityScore: 72,
            distanceFromRoute: 200
        ),
    ]

    // スポット詳細のモックデータ
    static let spotDetail = SpotViewModel.mockSpotDetail(spotId: "preview_spot_1")

    // ルート結果のモックデータ
    static let routeResults = RouteViewModel.mockRouteResults()

    // チャットメッセージのモックデータ
    static let chatMessages: [ChatMessage] = [
        ChatMessage(role: .user, content: "車椅子で東京駅に行きたいです"),
        ChatMessage(role: .assistant, content: "車椅子でのお出かけですね。バリアフリー対応のルートをお探しでしょうか？目的地をお教えいただければ、段差のない安全なルートをご提案いたします。"),
        ChatMessage(role: .user, content: "はい、丸の内方面でお願いします"),
        ChatMessage(role: .assistant, content: "丸の内方面への車椅子ルートをご案内いたします。東京駅丸の内北口からのルートが最もバリアフリーです。エレベーターを利用して地上に出られます。"),
    ]

    // ニーズ抽出のモックデータ
    static let extractedNeeds = ExtractedNeeds(
        mobilityType: .wheelchair,
        companions: nil,
        maxDistanceMeters: 1000,
        avoidConditions: [.stairs],
        preferConditions: [.restroom]
    )
}

// MARK: - プレビュー用ViewModifier

// ダークモード・ライトモード両方でプレビュー
struct DualModePreview<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group {
            content
                .preferredColorScheme(.light)
                .previewDisplayName("ライトモード")

            content
                .preferredColorScheme(.dark)
                .previewDisplayName("ダークモード")
        }
    }
}

// 大きいフォントサイズでのプレビュー
struct LargeFontPreview<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.sizeCategory, .accessibilityExtraLarge)
            .previewDisplayName("大きいフォント")
    }
}

// MARK: - 主要画面のプレビュー

#Preview("ホーム画面") {
    DualModePreview {
        HomeView()
    }
}

#Preview("ルート検索") {
    DualModePreview {
        RouteView()
    }
}

#Preview("ルート詳細") {
    DualModePreview {
        NavigationStack {
            RouteDetailView(route: PreviewMockData.routeResults[0])
        }
    }
}

#Preview("チャット画面") {
    DualModePreview {
        ChatView()
    }
}

#Preview("スポット一覧") {
    DualModePreview {
        SpotView()
    }
}

#Preview("スポット詳細") {
    DualModePreview {
        NavigationStack {
            SpotDetailView(spotId: "preview_spot_1")
        }
    }
}

#Preview("プロファイル") {
    DualModePreview {
        ProfileView()
    }
}

#Preview("オンボーディング") {
    DualModePreview {
        OnboardingView(isOnboardingCompleted: .constant(false))
    }
}

#Preview("ホーム画面 - 大フォント") {
    LargeFontPreview {
        HomeView()
    }
}

#Preview("チャット画面 - 大フォント") {
    LargeFontPreview {
        ChatView()
    }
}

#Preview("ルート詳細 - 大フォント") {
    LargeFontPreview {
        NavigationStack {
            RouteDetailView(route: PreviewMockData.routeResults[0])
        }
    }
}
