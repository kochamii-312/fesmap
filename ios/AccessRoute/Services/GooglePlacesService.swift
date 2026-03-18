import Foundation
import CoreLocation

// Google Places API サービス
enum GooglePlacesService {

    // MARK: - レスポンス構造

    struct NearbyResponse: Codable {
        let status: String
        let results: [PlaceResult]
    }

    struct PlaceResult: Codable {
        let place_id: String // swiftlint:disable:this identifier_name
        let name: String
        let vicinity: String?
        let geometry: PlaceGeometry
        let types: [String]?
        let rating: Double?
        let price_level: Int? // swiftlint:disable:this identifier_name
        let opening_hours: PlaceOpeningHoursBrief? // swiftlint:disable:this identifier_name
    }

    struct PlaceGeometry: Codable {
        let location: PlaceLocation
    }

    struct PlaceLocation: Codable {
        let lat: Double
        let lng: Double
    }

    struct PlaceOpeningHoursBrief: Codable {
        let open_now: Bool? // swiftlint:disable:this identifier_name
    }

    // 詳細レスポンス
    struct DetailResponse: Codable {
        let status: String
        let result: PlaceDetail?
    }

    struct PlaceDetail: Codable {
        let name: String?
        let formatted_address: String? // swiftlint:disable:this identifier_name
        let formatted_phone_number: String? // swiftlint:disable:this identifier_name
        let rating: Double?
        let price_level: Int? // swiftlint:disable:this identifier_name
        let wheelchair_accessible_entrance: Bool? // swiftlint:disable:this identifier_name
        let types: [String]?
        let website: String?
        let url: String?
        let opening_hours: PlaceOpeningHours? // swiftlint:disable:this identifier_name
        let reviews: [PlaceReview]?
    }

    struct PlaceOpeningHours: Codable {
        let open_now: Bool? // swiftlint:disable:this identifier_name
        let weekday_text: [String]? // swiftlint:disable:this identifier_name
    }

    struct PlaceReview: Codable {
        let text: String?
        let rating: Int?
    }

    // MARK: - アプリ用の詳細情報

    struct SpotDetailInfo {
        let address: String?
        let phone: String?
        let rating: Double?
        let priceLevel: Int? // 1-4
        let isWheelchairAccessible: Bool?
        let openNow: Bool?
        let openingHours: [String]
        let website: String?
        let googleMapsURL: String?
        let types: [String]
        let cuisineType: String? // 料理ジャンル
        let review: String? // 最新レビュー抜粋
    }

    // MARK: - API呼び出し

    // スポットの詳細情報を取得
    static func fetchDetail(
        name: String,
        coordinate: CLLocationCoordinate2D
    ) async -> SpotDetailInfo? {
        let apiKey = AppConfig.googleMapsAPIKey
        guard !apiKey.isEmpty else { return nil }

        // 1. Nearby Search でplace_idを取得
        guard let placeId = await findPlaceId(
            name: name, coordinate: coordinate, apiKey: apiKey
        ) else { return nil }

        // 2. Place Details で詳細取得
        return await fetchPlaceDetail(placeId: placeId, apiKey: apiKey)
    }

    // place_idを検索
    private static func findPlaceId(
        name: String,
        coordinate: CLLocationCoordinate2D,
        apiKey: String
    ) async -> String? {
        guard var components = URLComponents(
            string: "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
        ) else { return nil }

        components.queryItems = [
            URLQueryItem(name: "location", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "radius", value: "200"),
            URLQueryItem(name: "keyword", value: name),
            URLQueryItem(name: "language", value: "ja"),
            URLQueryItem(name: "key", value: apiKey),
        ]

        guard let url = components.url else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(NearbyResponse.self, from: data)
            return response.results.first?.place_id
        } catch {
            return nil
        }
    }

    // 詳細情報を取得
    private static func fetchPlaceDetail(
        placeId: String,
        apiKey: String
    ) async -> SpotDetailInfo? {
        guard var components = URLComponents(
            string: "https://maps.googleapis.com/maps/api/place/details/json"
        ) else { return nil }

        let fields = [
            "name", "formatted_address", "formatted_phone_number",
            "rating", "price_level", "wheelchair_accessible_entrance",
            "types", "website", "url", "opening_hours", "reviews"
        ].joined(separator: ",")

        components.queryItems = [
            URLQueryItem(name: "place_id", value: placeId),
            URLQueryItem(name: "fields", value: fields),
            URLQueryItem(name: "language", value: "ja"),
            URLQueryItem(name: "key", value: apiKey),
        ]

        guard let url = components.url else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(DetailResponse.self, from: data)

            guard let detail = response.result else { return nil }

            // 料理ジャンルを抽出
            let cuisineType = extractCuisineType(from: detail.types ?? [])

            // レビュー抜粋
            let reviewText = detail.reviews?.first?.text.map {
                String($0.prefix(100))
            }

            return SpotDetailInfo(
                address: detail.formatted_address,
                phone: detail.formatted_phone_number,
                rating: detail.rating,
                priceLevel: detail.price_level,
                isWheelchairAccessible: detail.wheelchair_accessible_entrance,
                openNow: detail.opening_hours?.open_now,
                openingHours: detail.opening_hours?.weekday_text ?? [],
                website: detail.website,
                googleMapsURL: detail.url,
                types: detail.types ?? [],
                cuisineType: cuisineType,
                review: reviewText
            )
        } catch {
            return nil
        }
    }

    // Google の types から料理ジャンルを抽出
    private static func extractCuisineType(from types: [String]) -> String? {
        let cuisineMap: [String: String] = [
            "japanese_restaurant": "和食",
            "sushi_restaurant": "寿司",
            "ramen_restaurant": "ラーメン",
            "chinese_restaurant": "中華料理",
            "italian_restaurant": "イタリアン",
            "french_restaurant": "フレンチ",
            "korean_restaurant": "韓国料理",
            "indian_restaurant": "インド料理",
            "thai_restaurant": "タイ料理",
            "mexican_restaurant": "メキシカン",
            "hamburger_restaurant": "ハンバーガー",
            "pizza_restaurant": "ピザ",
            "seafood_restaurant": "シーフード",
            "steak_house": "ステーキ",
            "bakery": "ベーカリー",
            "bar": "バー",
            "cafe": "カフェ",
            "meal_takeaway": "テイクアウト",
            "meal_delivery": "デリバリー",
        ]

        for type in types {
            if let cuisine = cuisineMap[type] {
                return cuisine
            }
        }

        if types.contains("restaurant") { return "レストラン" }
        if types.contains("food") { return "飲食店" }

        return nil
    }

    // 価格帯の表示テキスト
    static func priceLevelText(_ level: Int?) -> String? {
        switch level {
        case 1: return "¥ リーズナブル"
        case 2: return "¥¥ 普通"
        case 3: return "¥¥¥ やや高め"
        case 4: return "¥¥¥¥ 高級"
        default: return nil
        }
    }
}
