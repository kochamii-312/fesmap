import Foundation
import CoreLocation
@preconcurrency import MapKit

// ジオコーディングサービス
// 5段フォールバック: 既知地名 → キャッシュ → Backend API → Nominatim → MKLocalSearch
actor GeocodingService {
    static let shared = GeocodingService()

    private let nominatimBaseURL = "https://nominatim.openstreetmap.org"
    private let nominatimTimeout: TimeInterval = 10

    // ランタイムキャッシュ
    private var geocodeCache: [String: LatLng] = [:]

    private init() {}

    // MARK: - 既知の地名データベース

    // swiftlint:disable line_length
    private static let knownPlaces: [String: LatLng] = [
        // 東京主要駅
        "東京駅": LatLng(lat: 35.6812, lng: 139.7671),
        "新宿駅": LatLng(lat: 35.6896, lng: 139.7006),
        "渋谷駅": LatLng(lat: 35.6580, lng: 139.7016),
        "池袋駅": LatLng(lat: 35.7295, lng: 139.7109),
        "品川駅": LatLng(lat: 35.6284, lng: 139.7387),
        "上野駅": LatLng(lat: 35.7141, lng: 139.7774),
        "秋葉原駅": LatLng(lat: 35.6984, lng: 139.7731),
        "有楽町駅": LatLng(lat: 35.6748, lng: 139.7631),
        "六本木駅": LatLng(lat: 35.6632, lng: 139.7313),
        "銀座駅": LatLng(lat: 35.6717, lng: 139.7647),
        "表参道駅": LatLng(lat: 35.6652, lng: 139.7123),
        "中目黒駅": LatLng(lat: 35.6441, lng: 139.6991),
        "恵比寿駅": LatLng(lat: 35.6467, lng: 139.7100),
        "目黒駅": LatLng(lat: 35.6337, lng: 139.7158),
        "大崎駅": LatLng(lat: 35.6197, lng: 139.7283),
        "浜松町駅": LatLng(lat: 35.6555, lng: 139.7571),
        "田町駅": LatLng(lat: 35.6458, lng: 139.7476),
        "新橋駅": LatLng(lat: 35.6660, lng: 139.7583),
        "神田駅": LatLng(lat: 35.6918, lng: 139.7709),
        "御茶ノ水駅": LatLng(lat: 35.6998, lng: 139.7652),
        "飯田橋駅": LatLng(lat: 35.7022, lng: 139.7452),
        "四ツ谷駅": LatLng(lat: 35.6862, lng: 139.7302),
        "市ヶ谷駅": LatLng(lat: 35.6919, lng: 139.7359),
        "高田馬場駅": LatLng(lat: 35.7128, lng: 139.7038),
        "代々木駅": LatLng(lat: 35.6833, lng: 139.7020),
        "原宿駅": LatLng(lat: 35.6702, lng: 139.7027),
        // 川崎・横浜エリア
        "溝の口駅": LatLng(lat: 35.6006, lng: 139.6107),
        "武蔵溝ノ口駅": LatLng(lat: 35.6006, lng: 139.6107),
        "川崎駅": LatLng(lat: 35.5313, lng: 139.7020),
        "武蔵小杉駅": LatLng(lat: 35.5762, lng: 139.6596),
        "横浜駅": LatLng(lat: 35.4661, lng: 139.6226),
        "桜木町駅": LatLng(lat: 35.4510, lng: 139.6310),
        "関内駅": LatLng(lat: 35.4437, lng: 139.6368),
        "中華街駅": LatLng(lat: 35.4422, lng: 139.6454),
        // 観光地
        "東京タワー": LatLng(lat: 35.6586, lng: 139.7454),
        "東京スカイツリー": LatLng(lat: 35.7101, lng: 139.8107),
        "スカイツリー": LatLng(lat: 35.7101, lng: 139.8107),
        "浅草寺": LatLng(lat: 35.7148, lng: 139.7967),
        "浅草": LatLng(lat: 35.7148, lng: 139.7967),
        "明治神宮": LatLng(lat: 35.6764, lng: 139.6993),
        "皇居": LatLng(lat: 35.6852, lng: 139.7528),
        "上野公園": LatLng(lat: 35.7146, lng: 139.7734),
        "上野動物園": LatLng(lat: 35.7164, lng: 139.7713),
        "お台場": LatLng(lat: 35.6268, lng: 139.7744),
        "東京ディズニーランド": LatLng(lat: 35.6329, lng: 139.8804),
        "ディズニーランド": LatLng(lat: 35.6329, lng: 139.8804),
        "東京ディズニーシー": LatLng(lat: 35.6267, lng: 139.8850),
        "ディズニーシー": LatLng(lat: 35.6267, lng: 139.8850),
        // 主要商業施設・ランドマーク
        "東京ドーム": LatLng(lat: 35.7056, lng: 139.7519),
        "国立競技場": LatLng(lat: 35.6784, lng: 139.7145),
        "六本木ヒルズ": LatLng(lat: 35.6605, lng: 139.7292),
        "東京ミッドタウン": LatLng(lat: 35.6655, lng: 139.7311),
        "サンシャインシティ": LatLng(lat: 35.7292, lng: 139.7186),
        "サンシャイン60": LatLng(lat: 35.7292, lng: 139.7186),
        "横浜ランドマークタワー": LatLng(lat: 35.4555, lng: 139.6318),
        "赤レンガ倉庫": LatLng(lat: 35.4533, lng: 139.6430),
        // 主要病院
        "東京大学病院": LatLng(lat: 35.7127, lng: 139.7637),
        "慶應義塾大学病院": LatLng(lat: 35.7009, lng: 139.7177),
        "聖路加国際病院": LatLng(lat: 35.6683, lng: 139.7724),
        // 大阪主要駅
        "大阪駅": LatLng(lat: 34.7024, lng: 135.4959),
        "梅田駅": LatLng(lat: 34.7046, lng: 135.4985),
        "難波駅": LatLng(lat: 34.6628, lng: 135.5013),
        "なんば駅": LatLng(lat: 34.6628, lng: 135.5013),
        "天王寺駅": LatLng(lat: 34.6467, lng: 135.5138),
        "新大阪駅": LatLng(lat: 34.7337, lng: 135.5001),
        "京都駅": LatLng(lat: 34.9858, lng: 135.7588),
        "三宮駅": LatLng(lat: 34.6952, lng: 135.1970),
        "名古屋駅": LatLng(lat: 35.1709, lng: 136.8815),
        // 空港
        "羽田空港": LatLng(lat: 35.5494, lng: 139.7798),
        "成田空港": LatLng(lat: 35.7720, lng: 140.3929),
        "関西国際空港": LatLng(lat: 34.4320, lng: 135.2304),
        "関西空港": LatLng(lat: 34.4320, lng: 135.2304),
        "中部国際空港": LatLng(lat: 34.8584, lng: 136.8124),
        "セントレア": LatLng(lat: 34.8584, lng: 136.8124),
        "伊丹空港": LatLng(lat: 34.7855, lng: 135.4380),
        "新千歳空港": LatLng(lat: 42.7752, lng: 141.6925),
        "福岡空港": LatLng(lat: 33.5859, lng: 130.4511),
        // デフォルト
        "現在地": LatLng(lat: 35.6812, lng: 139.7671),
    ]
    // swiftlint:enable line_length

    // MARK: - ジオコーディング

    // 地名を緯度・経度に変換する（4段フォールバック）
    func geocode(_ placeName: String) async throws -> LatLng {
        let trimmed = placeName.trimmingCharacters(in: .whitespaces)

        // 「現在地」の場合はGPSから実際の位置を取得
        if trimmed == "現在地" {
            if let location = await getCurrentLocation() {
                return LatLng(lat: location.latitude, lng: location.longitude)
            }
            return Self.knownPlaces["現在地"]!
        }

        // 既知の地名はキャッシュから返す
        if let known = Self.knownPlaces[trimmed] {
            return known
        }

        // ランタイムキャッシュを確認
        if let cached = geocodeCache[trimmed] {
            return cached
        }

        // 座標形式（"35.6812,139.7671"）の場合はそのままパース
        if let coords = parseCoordinateString(trimmed) {
            return coords
        }

        // バックエンドAPI経由でジオコーディングを試行
        do {
            let location = try await APIService.shared.geocodeAddress(trimmed)
            geocodeCache[trimmed] = location
            return location
        } catch {
            // フォールバックへ
        }

        // フォールバック: Nominatim（OpenStreetMap）で検索
        if let result = await geocodeWithNominatim(trimmed) {
            geocodeCache[trimmed] = result
            return result
        }

        // フォールバック: MKLocalSearch（Apple Maps）で検索
        if let result = await geocodeWithMapKit(trimmed) {
            geocodeCache[trimmed] = result
            return result
        }

        // 部分一致で検索を試みる
        if let match = findPartialMatch(trimmed) {
            return match
        }

        throw GeocodingError.placeNotFound(trimmed)
    }

    // 緯度・経度を住所に変換する（逆ジオコーディング）
    func reverseGeocode(_ location: LatLng) async -> String {
        // バックエンドAPIを試行
        do {
            let address = try await APIService.shared.reverseGeocodeLocation(
                lat: location.lat, lng: location.lng
            )
            return address
        } catch {
            // フォールバックへ
        }

        // フォールバック: Nominatim
        if let address = await reverseGeocodeWithNominatim(lat: location.lat, lng: location.lng) {
            return address
        }

        // 全て失敗した場合は座標を返す
        return String(format: "%.4f, %.4f", location.lat, location.lng)
    }

    // 場所検索候補を取得
    func getPlaceSuggestions(input: String) async -> [PlaceSuggestion] {
        // バックエンドAPI
        do {
            return try await APIService.shared.getPlaceSuggestions(input: input)
        } catch {
            // フォールバックへ
        }

        // Nominatimフォールバック
        return await searchWithNominatim(input)
    }

    // MARK: - 内部処理

    // 座標文字列をパース
    private func parseCoordinateString(_ text: String) -> LatLng? {
        let pattern = #"^(-?\d+\.?\d*)\s*,\s*(-?\d+\.?\d*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let latRange = Range(match.range(at: 1), in: text),
              let lngRange = Range(match.range(at: 2), in: text),
              let lat = Double(text[latRange]),
              let lng = Double(text[lngRange]),
              (-90...90).contains(lat),
              (-180...180).contains(lng) else {
            return nil
        }
        return LatLng(lat: lat, lng: lng)
    }

    // 既知地名から部分一致で検索
    private func findPartialMatch(_ query: String) -> LatLng? {
        // 入力が既知の地名を含むか
        for (name, location) in Self.knownPlaces {
            if query.contains(name) || name.contains(query) {
                return location
            }
        }
        // 「駅」を付けて再検索
        if !query.hasSuffix("駅") {
            if let location = Self.knownPlaces[query + "駅"] {
                return location
            }
        }
        return nil
    }

    // GPSから現在地を取得
    private func getCurrentLocation() async -> CLLocationCoordinate2D? {
        let manager = CLLocationManager()
        guard manager.authorizationStatus == .authorizedWhenInUse ||
              manager.authorizationStatus == .authorizedAlways else {
            return nil
        }
        return manager.location?.coordinate
    }

    // MKLocalSearch（Apple Maps）でジオコーディング
    private nonisolated func geocodeWithMapKit(_ placeName: String) async -> LatLng? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = placeName
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.77),
            latitudinalMeters: 100_000,
            longitudinalMeters: 100_000
        )

        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            guard let item = response.mapItems.first else { return nil }
            let coord = item.placemark.coordinate
            return LatLng(lat: coord.latitude, lng: coord.longitude)
        } catch {
            return nil
        }
    }

    // Nominatimでジオコーディング
    private func geocodeWithNominatim(_ placeName: String) async -> LatLng? {
        guard var components = URLComponents(string: "\(nominatimBaseURL)/search") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: placeName),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "countrycodes", value: "jp"),
            URLQueryItem(name: "accept-language", value: "ja"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("AccessRoute-App/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = nominatimTimeout

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = results.first,
                  let latStr = first["lat"] as? String,
                  let lonStr = first["lon"] as? String,
                  let lat = Double(latStr),
                  let lng = Double(lonStr) else {
                return nil
            }
            return LatLng(lat: lat, lng: lng)
        } catch {
            return nil
        }
    }

    // Nominatimで逆ジオコーディング
    private func reverseGeocodeWithNominatim(lat: Double, lng: Double) async -> String? {
        guard var components = URLComponents(string: "\(nominatimBaseURL)/reverse") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lng)),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "accept-language", value: "ja"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("AccessRoute-App/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = nominatimTimeout

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let displayName = result["display_name"] as? String else {
                return nil
            }
            return displayName
        } catch {
            return nil
        }
    }

    // Nominatimで場所検索
    private func searchWithNominatim(_ query: String) async -> [PlaceSuggestion] {
        guard var components = URLComponents(string: "\(nominatimBaseURL)/search") else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "countrycodes", value: "jp"),
            URLQueryItem(name: "accept-language", value: "ja"),
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("AccessRoute-App/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = nominatimTimeout

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }
            return results.compactMap { item -> PlaceSuggestion? in
                guard let displayName = item["display_name"] as? String,
                      let placeId = item["place_id"] as? Int else {
                    return nil
                }
                return PlaceSuggestion(
                    description: displayName,
                    placeId: String(placeId)
                )
            }
        } catch {
            return []
        }
    }
}

// ジオコーディングエラー
enum GeocodingError: LocalizedError {
    case placeNotFound(String)

    var errorDescription: String? {
        switch self {
        case .placeNotFound(let name):
            return "場所が見つかりません: \(name)"
        }
    }
}
