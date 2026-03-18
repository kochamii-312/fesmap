import Foundation
import CoreLocation

// ホーム画面のViewModel
@MainActor
final class HomeViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var isSearching = false
    @Published var nearbySpots: [SpotSummary] = []
    @Published var chatRecommendedSpots: [SpotSummary] = [] // AIチャットからの推薦スポット
    @Published var errorMessage: String?
    @Published var shouldNavigateToRoute = false
    @Published var suggestions: [PlaceSuggestion] = []
    @Published var showSuggestions = false
    @Published var currentAddress = ""

    // デバウンス用タスク
    private var suggestionTask: Task<Void, Never>?

    // 周辺スポットから距離が近い上位5件をおすすめとして表示する
    var recommendedNearbySpots: [SpotSummary] {
        Array(nearbySpots
            .sorted { $0.distanceFromRoute < $1.distanceFromRoute }
            .prefix(5))
    }

    // 保存されたプロファイルからサマリー情報を取得
    var profileMobilityType: MobilityType {
        if let raw = UserDefaults.standard.string(forKey: "profile_mobilityType"),
           let type = MobilityType(rawValue: raw) {
            return type
        }
        return .walk
    }

    var profileMaxDistance: Double {
        let distance = UserDefaults.standard.double(forKey: "profile_maxDistance")
        return distance > 0 ? distance : 1000
    }

    var profileCompanions: [Companion] {
        guard let rawValues = UserDefaults.standard.stringArray(forKey: "profile_companions") else {
            return []
        }
        return rawValues.compactMap { Companion(rawValue: $0) }
    }

    var profileAvoidConditions: [AvoidCondition] {
        guard let rawValues = UserDefaults.standard.stringArray(forKey: "profile_avoidConditions") else {
            return []
        }
        return rawValues.compactMap { AvoidCondition(rawValue: $0) }
    }

    // MARK: - 検索候補（オートコンプリート）

    // 検索テキスト変更時に候補を取得（300msデバウンス）
    func fetchSuggestions(for text: String) {
        suggestionTask?.cancel()

        guard text.count >= 2 else {
            suggestions = []
            showSuggestions = false
            return
        }

        suggestionTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            let results = await GeocodingService.shared.getPlaceSuggestions(input: text)
            guard !Task.isCancelled else { return }

            suggestions = results
            showSuggestions = !results.isEmpty
        }
    }

    // 検索候補を選択
    func selectSuggestion(_ suggestion: PlaceSuggestion) {
        searchText = suggestion.description
        suggestions = []
        showSuggestions = false
        shouldNavigateToRoute = true
    }

    // クイックアクション（トイレ/EV/休憩所）
    func quickSearch(_ keyword: String) {
        searchText = keyword
        shouldNavigateToRoute = true
    }

    // MARK: - 周辺スポット検索（ユーザーの好みに基づく）

    func searchNearbySpots(lat: Double, lng: Double) async {
        isSearching = true
        errorMessage = nil

        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)

        // MKLocalSearch でユーザーの好みに基づいたリアルなスポットを検索
        let spots = await MapSpotSearchService.searchPreferredSpots(
            near: coordinate,
            radius: 500
        )

        if spots.isEmpty {
            // スポットが見つからない場合はモックデータ
            nearbySpots = Self.mockNearbySpots()
        } else {
            nearbySpots = spots
        }

        isSearching = false
    }

    // 逆ジオコーディングで現在地住所を取得
    func updateCurrentAddress(lat: Double, lng: Double) async {
        let address = await GeocodingService.shared.reverseGeocode(
            LatLng(lat: lat, lng: lng)
        )
        currentAddress = address
    }

    // 目的地検索を実行
    func submitSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        showSuggestions = false
        shouldNavigateToRoute = true
    }

    // MARK: - AIチャット連携

    /// AIチャットから受け取った推薦スポットを表示する
    func displaySpotsFromChat(_ spots: [RecommendedSpot]) {
        // 既存のスポットをクリア
        self.chatRecommendedSpots = []
        
        // ChatのRecommendedSpotを地図表示用のSpotSummaryに変換
        let summaries = spots.map { spot -> SpotSummary in
            return SpotSummary(
                spotId: spot.id,
                name: spot.name,
                category: .other, // チャット経由のスポットは汎用カテゴリ
                location: LatLng(lat: spot.latitude, lng: spot.longitude),
                accessibilityScore: 75, // 固定スコア（または非表示）
                distanceFromRoute: 0 // 距離は不明
            )
        }
        
        self.chatRecommendedSpots = summaries
    }

    // MARK: - モックデータ

    static func mockNearbySpots() -> [SpotSummary] {
        [
            SpotSummary(
                spotId: "spot_nearby_1",
                name: "バリアフリートイレ 丸の内",
                category: .restroom,
                location: LatLng(lat: 35.6815, lng: 139.7675),
                accessibilityScore: 95,
                distanceFromRoute: 50
            ),
            SpotSummary(
                spotId: "spot_nearby_2",
                name: "休憩ベンチ 日比谷通り",
                category: .rest_area,
                location: LatLng(lat: 35.6808, lng: 139.7665),
                accessibilityScore: 80,
                distanceFromRoute: 120
            ),
            SpotSummary(
                spotId: "spot_nearby_3",
                name: "カフェ アクセス",
                category: .cafe,
                location: LatLng(lat: 35.6820, lng: 139.7680),
                accessibilityScore: 72,
                distanceFromRoute: 200
            ),
            SpotSummary(
                spotId: "spot_nearby_4",
                name: "エレベーター 地下鉄出口",
                category: .elevator,
                location: LatLng(lat: 35.6805, lng: 139.7668),
                accessibilityScore: 88,
                distanceFromRoute: 80
            )
        ]
    }
}
