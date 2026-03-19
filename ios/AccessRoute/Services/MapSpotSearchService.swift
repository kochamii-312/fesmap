import Foundation
import MapKit

// MapKit のローカル検索でリアルなスポットを検索するサービス
enum MapSpotSearchService {

    // ユーザーの好みに基づいてスポットを検索
    static func searchPreferredSpots(
        near coordinate: CLLocationCoordinate2D,
        radius: Double = 500
    ) async -> [SpotSummary] {
        // プロフィール設定を基準に、マップフィルターで絞り込む
        var needs = UserNeedsService.loadUnifiedNeeds()
        if let mapFilters = UserDefaults.standard.stringArray(forKey: "mapActiveFilters") {
            // マップフィルターが設定済み（空配列含む）の場合はフィルターを適用
            let profileSet = Set(needs.preferConditions.map(\.rawValue))
            let activeSet = Set(mapFilters).intersection(profileSet)
            // activeSet が空 → 全フィルターOFF → スポット非表示
            needs.preferConditions = activeSet.compactMap { PreferCondition(rawValue: $0) }
        }

        var allSpots: [SpotSummary] = []

        // 好みに応じた検索キーワードを決定
        var queries = buildSearchQueries(from: needs)

        // 好みがなくてもデフォルトでバリアフリー関連を検索
        if queries.isEmpty {
            queries = [("トイレ", SpotCategory.restroom)]
        }

        // Apple Maps（MKLocalSearch）をバッチ3件ずつ並列検索
        for batch in queries.chunked(into: 3) {
            await withTaskGroup(of: [SpotSummary].self) { group in
                for (query, category) in batch {
                    group.addTask {
                        await searchMapKit(
                            query: query,
                            category: category,
                            near: coordinate,
                            radius: radius
                        )
                    }
                }
                for await spots in group {
                    allSpots.append(contentsOf: spots)
                }
            }
        }

        // Yahoo! YOLP をバッチ3件ずつ並列検索
        for batch in queries.chunked(into: 3) {
            await withTaskGroup(of: [SpotSummary].self) { group in
                for (query, category) in batch {
                    group.addTask {
                        await searchYOLP(
                            query: query,
                            category: category,
                            near: coordinate,
                            radius: radius
                        )
                    }
                }
                for await spots in group {
                    allSpots.append(contentsOf: spots)
                }
            }
        }

        // 重複除去（グリッドキーによる O(n) 判定）
        var seen = Set<String>()
        allSpots = allSpots.filter { spot in
            // ~50m精度のグリッドキー + 名前先頭3文字で重複判定
            let latKey = Int(spot.location.lat * 200)
            let lngKey = Int(spot.location.lng * 200)
            let nameKey = String(spot.name.prefix(3))
            let key = "\(nameKey)_\(latKey)_\(lngKey)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }

        // スコアリング
        let scored = allSpots.map { spot in
            NearbySpotService.scoreSpot(spot, needs: needs)
        }

        // スコア順でソート
        return scored
            .sorted { $0.relevanceScore > $1.relevanceScore }
            .prefix(15)
            .map(\.spot)
    }

    // 目的地周辺のスポットを検索
    static func searchSpotsNearDestination(
        destination: CLLocationCoordinate2D,
        radius: Double = 800
    ) async -> [SpotSummary] {
        await searchPreferredSpots(near: destination, radius: radius)
    }

    // MARK: - 内部処理

    // ユーザーの好みから検索クエリを構築
    private static func buildSearchQueries(
        from needs: UnifiedUserNeeds
    ) -> [(String, SpotCategory)] {
        var queries: [(String, SpotCategory)] = []

        // プロフィールの優先条件に基づいて検索
        for prefer in needs.preferConditions {
            switch prefer {
            case .cafe:
                queries.append(("カフェ", .cafe))
            case .restroom:
                queries.append(("トイレ", .restroom))
                queries.append(("多目的トイレ", .accessible_restroom))
                queries.append(("多機能トイレ", .accessible_restroom))
                queries.append(("バリアフリートイレ", .accessible_restroom))
            case .restaurant:
                queries.append(("レストラン", .restaurant))
            case .library:
                queries.append(("図書館", .library))
            case .rental_bicycle:
                queries.append(("レンタサイクル", .rental_bicycle))
                queries.append(("シェアサイクル", .rental_bicycle))
            case .karaoke:
                queries.append(("カラオケ", .karaoke))
            case .gym:
                queries.append(("体育館", .gym))
                queries.append(("スポーツジム", .gym))
            case .elevator:
                queries.append(("エレベーター", .elevator))
            case .rest_area:
                queries.append(("休憩所", .rest_area))
            case .covered:
                queries.append(("屋根付き", .rest_area))
            case .nursing_room:
                queries.append(("授乳室", .nursing_room))
            case .parking_spot:
                queries.append(("駐車場", .parking))
            case .convenience_store:
                queries.append(("コンビニ", .convenience_store))
            case .ramen:
                queries.append(("ラーメン", .ramen))
            case .cinema:
                queries.append(("映画館", .cinema))
            case .bookstore:
                queries.append(("本屋", .bookstore))
                queries.append(("書店", .bookstore))
            case .onsen:
                queries.append(("温泉", .onsen))
                queries.append(("銭湯", .onsen))
            case .game_center:
                queries.append(("ゲームセンター", .game_center))
            case .hospital:
                queries.append(("病院", .hospital))
                queries.append(("クリニック", .hospital))
            case .atm:
                queries.append(("ATM", .atm))
            case .post_office:
                queries.append(("郵便局", .post_office))
            case .museum:
                queries.append(("美術館", .museum))
                queries.append(("博物館", .museum))
            case .park:
                queries.append(("公園", .park))
            case .hotel:
                queries.append(("ホテル", .hotel))
            case .trash_bin:
                queries.append(("公共ゴミ箱", .trash_bin))
                queries.append(("ごみ箱", .trash_bin))
            }
        }

        // 移動手段に応じた追加検索
        switch needs.mobilityType {
        case .wheelchair:
            queries.append(("エレベーター", .elevator))
            if !queries.contains(where: { $0.1 == .restroom }) {
                queries.append(("多目的トイレ", .restroom))
            }
        case .stroller:
            queries.append(("授乳室", .nursing_room))
        case .cane:
            if !queries.contains(where: { $0.1 == .rest_area }) {
                queries.append(("休憩所", .rest_area))
            }
        default:
            break
        }

        return queries
    }

    // MKLocalSearch でスポットを検索
    private static func searchMapKit(
        query: String,
        category: SpotCategory,
        near coordinate: CLLocationCoordinate2D,
        radius: Double
    ) async -> [SpotSummary] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
        request.resultTypes = .pointOfInterest

        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            return response.mapItems.prefix(5).compactMap { item -> SpotSummary? in
                guard let name = item.name else { return nil }
                let itemCoord = item.placemark.coordinate
                let distance = TransitRouteService.haversineDistance(
                    from: coordinate, to: itemCoord
                )

                // 半径内のスポットのみ
                guard distance <= radius else { return nil }

                let isBarrierFree = estimateBarrierFree(for: item, category: category)
                return SpotSummary(
                    spotId: "mk_\(UUID().uuidString.prefix(8))",
                    name: name,
                    category: category,
                    location: LatLng(lat: itemCoord.latitude, lng: itemCoord.longitude),
                    accessibilityScore: estimateAccessibilityScore(for: item, category: category),
                    distanceFromRoute: distance,
                    isBarrierFree: isBarrierFree
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - Yahoo! YOLP 検索

    // YOLP レスポンス
    private struct YOLPResponse: Codable {
        let Feature: [YOLPFeature]?
    }

    private struct YOLPFeature: Codable {
        let Name: String?
        let Geometry: YOLPGeometry?
        let Property: YOLPProperty?
    }

    private struct YOLPGeometry: Codable {
        let Coordinates: String? // "経度,緯度"
    }

    private struct YOLPProperty: Codable {
        let Address: String?
        let Tel1: String?
        let Genre: [YOLPGenre]?
        let Gid: String?
    }

    private struct YOLPGenre: Codable {
        let Name: String?
    }

    // YOLP でスポットを検索
    private static func searchYOLP(
        query: String,
        category: SpotCategory,
        near coordinate: CLLocationCoordinate2D,
        radius: Double
    ) async -> [SpotSummary] {
        let appId = AppConfig.yolpAppId
        guard !appId.isEmpty else { return [] }

        guard var components = URLComponents(
            string: "https://map.yahooapis.jp/search/local/V1/localSearch"
        ) else { return [] }

        let distKm = min(radius / 1000.0, 50.0)

        components.queryItems = [
            URLQueryItem(name: "appid", value: appId),
            URLQueryItem(name: "lat", value: String(coordinate.latitude)),
            URLQueryItem(name: "lon", value: String(coordinate.longitude)),
            URLQueryItem(name: "dist", value: String(distKm)),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "results", value: "5"),
            URLQueryItem(name: "sort", value: "dist"),
            URLQueryItem(name: "output", value: "json"),
        ]

        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [] }

            let yolpResponse = try JSONDecoder().decode(YOLPResponse.self, from: data)

            return yolpResponse.Feature?.compactMap { feature -> SpotSummary? in
                guard let name = feature.Name,
                      let coordString = feature.Geometry?.Coordinates else { return nil }

                let parts = coordString.split(separator: ",").compactMap { Double($0) }
                guard parts.count == 2 else { return nil }
                let lng = parts[0]
                let lat = parts[1]

                let distance = TransitRouteService.haversineDistance(
                    from: coordinate,
                    to: CLLocationCoordinate2D(latitude: lat, longitude: lng)
                )
                guard distance <= radius else { return nil }

                return SpotSummary(
                    spotId: "yolp_\(feature.Property?.Gid ?? UUID().uuidString.prefix(8).description)",
                    name: name,
                    category: category,
                    location: LatLng(lat: lat, lng: lng),
                    accessibilityScore: 70,
                    distanceFromRoute: distance
                )
            } ?? []
        } catch {
            return []
        }
    }

    // バリアフリー対応を推定
    static func estimateBarrierFree(for item: MKMapItem, category: SpotCategory) -> Bool {
        let name = item.name ?? ""

        // 公共施設はバリアフリー対応が多い
        if category == .library || category == .accessible_restroom || category == .elevator {
            return true
        }

        // 大規模チェーン店はバリアフリー対応が多い
        let barrierFreeChains = [
            "スターバックス", "Starbucks", "ドトール", "タリーズ", "Tully",
            "マクドナルド", "McDonald", "ガスト", "サイゼリヤ", "デニーズ",
            "ジョナサン", "バーミヤン", "ロイヤルホスト", "ココス",
            "モスバーガー", "ケンタッキー", "KFC", "吉野家", "すき家",
            "松屋", "コメダ", "珈琲", "DOUTOR", "Pronto", "PRONTO"
        ]
        if barrierFreeChains.contains(where: { name.contains($0) }) {
            return true
        }

        // 駅ビル・商業施設内はバリアフリー対応が多い
        let facilityKeywords = ["駅", "モール", "ビル", "プラザ", "アトレ", "ルミネ", "マルイ"]
        if facilityKeywords.contains(where: { name.contains($0) }) {
            return true
        }

        return false
    }

    // プロフィール関連度スコアを算出
    private static func estimateAccessibilityScore(
        for item: MKMapItem, category: SpotCategory
    ) -> Int {
        let isBarrierFree = estimateBarrierFree(for: item, category: category)
        let tempSpot = SpotSummary(
            spotId: "temp",
            name: item.name ?? "",
            category: category,
            location: LatLng(lat: 0, lng: 0),
            accessibilityScore: 70,
            distanceFromRoute: 0,
            isBarrierFree: isBarrierFree
        )
        let needs = UserNeedsService.loadUnifiedNeeds()
        let scored = NearbySpotService.scoreSpot(tempSpot, needs: needs)
        return scored.relevanceScore
    }
}

// MARK: - Array バッチ分割ヘルパー

private extension Array {
    /// 配列を指定サイズのバッチに分割する
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
