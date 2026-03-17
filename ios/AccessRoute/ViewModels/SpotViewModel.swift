import Foundation

// スポット画面のViewModel（座標検索・展開式カード対応）
@MainActor
final class SpotViewModel: ObservableObject {
    // 座標入力
    @Published var latText = "35.6812"
    @Published var lngText = "139.7671"

    // 検索状態
    @Published var isSearching = false
    @Published var hasSearched = false
    @Published var coordError: String?

    // スポット一覧
    @Published var spots: [SpotSummary] = []

    // 展開中のスポットID
    @Published var expandedSpotId: String?

    // スポット詳細キャッシュ
    @Published var spotDetails: [String: SpotDetail] = [:]
    @Published var loadingDetailId: String?

    // 詳細画面用（既存互換）
    @Published var spotDetail: SpotDetail?
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - 座標検索

    // 座標でスポットを検索
    func searchByCoordinates() async {
        guard let lat = Double(latText), let lng = Double(lngText) else {
            coordError = "緯度・経度に有効な数値を入力してください"
            return
        }
        coordError = nil
        isSearching = true
        hasSearched = true
        expandedSpotId = nil

        let scoredSpots = await NearbySpotService.fetchPersonalizedSpots(
            lat: lat, lng: lng
        )
        spots = scoredSpots.map(\.spot)
        isSearching = false
    }

    // MARK: - カード展開・詳細取得

    // スポットカードの展開をトグル
    func toggleExpand(spotId: String) {
        if expandedSpotId == spotId {
            expandedSpotId = nil
            return
        }
        expandedSpotId = spotId

        // 詳細がキャッシュにない場合は取得
        if spotDetails[spotId] == nil {
            loadingDetailId = spotId
            Task {
                await loadDetail(spotId: spotId)
            }
        }
    }

    // スポット詳細を取得
    private func loadDetail(spotId: String) async {
        do {
            let detail = try await APIService.shared.getSpotDetail(spotId: spotId)
            spotDetails[spotId] = detail
        } catch {
            // APIエラー時はモック詳細を使用
            if let spot = spots.first(where: { $0.spotId == spotId }) {
                spotDetails[spotId] = Self.mockDetailFromSummary(spot)
            }
        }
        loadingDetailId = nil
    }

    // MARK: - 詳細画面用（既存互換）

    // スポット詳細取得
    func loadSpotDetail(spotId: String) async {
        isLoading = true
        errorMessage = nil
        spotDetail = Self.mockSpotDetail(spotId: spotId)
        isLoading = false
    }

    // MARK: - モックデータ

    // SpotSummaryからモック詳細を生成
    static func mockDetailFromSummary(_ spot: SpotSummary) -> SpotDetail {
        let details: [String: (address: String, phone: String?, hours: String?,
                               elevator: Bool, restroom: Bool, door: Bool, desc: String)] = [
            "mock_1": ("東京都千代田区丸の内1-9-1 地下1階", nil, "5:30〜24:30（年中無休）",
                       true, true, true,
                       "車椅子対応の多目的トイレ。オストメイト対応設備あり。ベビーベッド設置。"),
            "mock_2": ("東京都千代田区日比谷通り沿い", nil, "24時間利用可能",
                       false, false, false,
                       "屋根付きの休憩スペース。ベンチ3台設置。"),
            "mock_3": ("東京都千代田区丸の内2-4-1 1階", "03-1234-5678", "月〜金: 7:00〜21:00",
                       false, false, true,
                       "バリアフリー対応カフェ。テーブル間隔が広く車椅子でも利用しやすい。"),
            "mock_4": ("東京都千代田区丸の内1丁目 地下鉄丸ノ内線出口", nil, "5:00〜25:00",
                       true, false, true,
                       "地上と地下鉄コンコースを結ぶエレベーター。車椅子・ベビーカー対応。")
        ]

        let info = details[spot.spotId]
        return SpotDetail(
            spotId: spot.spotId,
            name: spot.name,
            description: info?.desc ?? "バリアフリー対応施設",
            category: spot.category,
            location: spot.location,
            address: info?.address ?? "住所情報なし",
            accessibilityScore: spot.accessibilityScore,
            accessibility: AccessibilityInfo(
                wheelchairAccessible: true,
                hasElevator: info?.elevator ?? false,
                hasAccessibleRestroom: info?.restroom ?? false,
                hasBabyChangingStation: false,
                hasNursingRoom: false,
                floorType: .flat,
                notes: []
            ),
            photoUrls: [],
            openingHours: info?.hours,
            phoneNumber: info?.phone,
            website: nil
        )
    }

    // プレビュー用モックデータ
    static func mockSpotDetail(spotId: String) -> SpotDetail {
        SpotDetail(
            spotId: spotId,
            name: "バリアフリーカフェ サンプル",
            description: "車椅子でもゆったり過ごせるバリアフリー対応のカフェです。段差なしの入口、広い通路、多目的トイレを完備しています。",
            category: .cafe,
            location: LatLng(lat: 35.6812, lng: 139.7671),
            address: "東京都千代田区丸の内1-1-1",
            accessibilityScore: 85,
            accessibility: AccessibilityInfo(
                wheelchairAccessible: true,
                hasElevator: true,
                hasAccessibleRestroom: true,
                hasBabyChangingStation: true,
                hasNursingRoom: false,
                floorType: .flat,
                notes: ["入口にスロープあり", "テーブル間隔が広い"]
            ),
            photoUrls: [],
            openingHours: "9:00 - 21:00",
            phoneNumber: "03-1234-5678",
            website: "https://example.com"
        )
    }
}
