import Foundation

// ホーム画面のViewModel
@MainActor
final class HomeViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var isSearching = false
    @Published var nearbySpots: [SpotSummary] = []
    @Published var errorMessage: String?
    @Published var shouldNavigateToRoute = false

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

    // 周辺スポット検索
    func searchNearbySpots(lat: Double, lng: Double) async {
        isSearching = true
        errorMessage = nil

        // TODO: Firebase Auth トークン取得後に実装
        // do {
        //     let token = try await AuthService.shared.getToken()
        //     nearbySpots = try await APIService.shared.getNearbySpots(
        //         lat: lat, lng: lng, token: token
        //     )
        // } catch {
        //     errorMessage = error.localizedDescription
        // }

        // モックデータで表示確認
        nearbySpots = Self.mockNearbySpots()
        isSearching = false
    }

    var profileAvoidConditions: [AvoidCondition] {
        guard let rawValues = UserDefaults.standard.stringArray(forKey: "profile_avoidConditions") else {
            return []
        }
        return rawValues.compactMap { AvoidCondition(rawValue: $0) }
    }

    // 目的地検索を実行
    func submitSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        shouldNavigateToRoute = true
    }

    // プロファイルに基づくおすすめモックデータ
    static func mockRecommendedSpots(
        mobilityType: MobilityType,
        companions: [Companion],
        avoidConditions: [AvoidCondition]
    ) -> [SpotSummary] {
        var spots: [SpotSummary] = []

        // 全ユーザー共通のおすすめ
        spots.append(SpotSummary(
            spotId: "rec_1",
            name: "丸の内バリアフリー広場",
            category: .park,
            location: LatLng(lat: 35.6818, lng: 139.7660),
            accessibilityScore: 95,
            distanceFromRoute: 150
        ))

        // 車椅子ユーザー向け
        if mobilityType == .wheelchair {
            spots.append(contentsOf: [
                SpotSummary(
                    spotId: "rec_wc_1",
                    name: "車椅子対応エレベーター 東京駅",
                    category: .elevator,
                    location: LatLng(lat: 35.6814, lng: 139.7670),
                    accessibilityScore: 98,
                    distanceFromRoute: 30
                ),
                SpotSummary(
                    spotId: "rec_wc_2",
                    name: "多目的トイレ KITTE",
                    category: .restroom,
                    location: LatLng(lat: 35.6807, lng: 139.7649),
                    accessibilityScore: 96,
                    distanceFromRoute: 100
                ),
                SpotSummary(
                    spotId: "rec_wc_3",
                    name: "スロープ付きカフェ 大手町",
                    category: .cafe,
                    location: LatLng(lat: 35.6840, lng: 139.7635),
                    accessibilityScore: 90,
                    distanceFromRoute: 250
                )
            ])
        }

        // ベビーカーユーザー向け
        if mobilityType == .stroller {
            spots.append(contentsOf: [
                SpotSummary(
                    spotId: "rec_st_1",
                    name: "授乳室 丸ビル 3F",
                    category: .nursing_room,
                    location: LatLng(lat: 35.6822, lng: 139.7643),
                    accessibilityScore: 94,
                    distanceFromRoute: 80
                ),
                SpotSummary(
                    spotId: "rec_st_2",
                    name: "キッズスペース 新丸ビル",
                    category: .kids_space,
                    location: LatLng(lat: 35.6826, lng: 139.7650),
                    accessibilityScore: 92,
                    distanceFromRoute: 120
                ),
                SpotSummary(
                    spotId: "rec_st_3",
                    name: "おむつ替え付きトイレ 丸の内オアゾ",
                    category: .restroom,
                    location: LatLng(lat: 35.6832, lng: 139.7658),
                    accessibilityScore: 91,
                    distanceFromRoute: 180
                )
            ])
        }

        // 杖ユーザー・徒歩ユーザー向け
        if mobilityType == .cane || mobilityType == .walk {
            spots.append(contentsOf: [
                SpotSummary(
                    spotId: "rec_cw_1",
                    name: "休憩ベンチ 行幸通り",
                    category: .rest_area,
                    location: LatLng(lat: 35.6810, lng: 139.7655),
                    accessibilityScore: 85,
                    distanceFromRoute: 60
                ),
                SpotSummary(
                    spotId: "rec_cw_2",
                    name: "屋根付き休憩所 丸の内仲通り",
                    category: .rest_area,
                    location: LatLng(lat: 35.6828, lng: 139.7648),
                    accessibilityScore: 88,
                    distanceFromRoute: 140
                )
            ])
        }

        // 高齢者同行時
        if companions.contains(.elderly) {
            spots.append(SpotSummary(
                spotId: "rec_el_1",
                name: "バリアフリーレストラン 丸の内",
                category: .restaurant,
                location: LatLng(lat: 35.6816, lng: 139.7645),
                accessibilityScore: 93,
                distanceFromRoute: 110
            ))
        }

        // 子ども同行時
        if companions.contains(.child) {
            spots.append(SpotSummary(
                spotId: "rec_ch_1",
                name: "キッズメニューあり ファミリーカフェ",
                category: .cafe,
                location: LatLng(lat: 35.6824, lng: 139.7662),
                accessibilityScore: 87,
                distanceFromRoute: 160
            ))
        }

        // スコア順にソート
        return spots.sorted { $0.accessibilityScore > $1.accessibilityScore }
    }

    // モックデータ
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
