import Foundation
import MapKit

// MapKit のローカル検索でリアルなスポットを検索するサービス
enum MapSpotSearchService {

    // ユーザーの好みに基づいてスポットを検索
    static func searchPreferredSpots(
        near coordinate: CLLocationCoordinate2D,
        radius: Double = 500
    ) async -> [SpotSummary] {
        let needs = UserNeedsService.loadUnifiedNeeds()
        var allSpots: [SpotSummary] = []

        // 好みに応じた検索キーワードを決定
        var queries = buildSearchQueries(from: needs)

        // 好みがなくてもデフォルトでバリアフリー関連を検索
        if queries.isEmpty {
            queries = [("トイレ", SpotCategory.restroom)]
        }

        // Apple Maps + YOLP で並列検索
        await withTaskGroup(of: [SpotSummary].self) { group in
            // Apple Maps（MKLocalSearch）
            for (query, category) in queries {
                group.addTask {
                    await searchMapKit(
                        query: query,
                        category: category,
                        near: coordinate,
                        radius: radius
                    )
                }
            }

            // Yahoo! YOLP（日本のローカルビジネスに強い）
            for (query, category) in queries {
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

        // 重複除去（名前の類似度 + 近接距離で判定）
        var uniqueSpots: [SpotSummary] = []
        for spot in allSpots {
            let isDuplicate = uniqueSpots.contains { existing in
                // 50m以内で名前が部分一致するものは重複
                let dist = TransitRouteService.haversineDistance(
                    from: CLLocationCoordinate2D(latitude: spot.location.lat, longitude: spot.location.lng),
                    to: CLLocationCoordinate2D(latitude: existing.location.lat, longitude: existing.location.lng)
                )
                if dist > 50 { return false }
                // 名前の先頭3文字が一致、または一方が他方を含む
                let a = spot.name.prefix(3)
                let b = existing.name.prefix(3)
                return a == b || spot.name.contains(existing.name) || existing.name.contains(spot.name)
            }
            if !isDuplicate {
                uniqueSpots.append(spot)
            }
        }
        allSpots = uniqueSpots

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

        // カフェとトイレは常に検索（実在する施設を表示）
        queries.append(("カフェ", .cafe))
        queries.append(("トイレ", .restroom))

        for prefer in needs.preferConditions {
            switch prefer {
            case .cafe:
                break // 上で追加済み
            case .restroom:
                queries.append(("多目的トイレ", .restroom))
                queries.append(("バリアフリートイレ", .restroom))
            case .rest_area:
                queries.append(("休憩所", .rest_area))
                queries.append(("ベンチ", .rest_area))
            case .covered:
                queries.append(("屋根付き", .rest_area))
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

                return SpotSummary(
                    spotId: "mk_\(UUID().uuidString.prefix(8))",
                    name: name,
                    category: category,
                    location: LatLng(lat: itemCoord.latitude, lng: itemCoord.longitude),
                    accessibilityScore: estimateAccessibilityScore(for: item, category: category),
                    distanceFromRoute: distance
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
        request.timeoutInterval = 10

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

    // MapItem からアクセシビリティスコアを推定
    private static func estimateAccessibilityScore(
        for item: MKMapItem, category: SpotCategory
    ) -> Int {
        var score = 70 // ベーススコア

        // カテゴリに応じたボーナス
        switch category {
        case .elevator: score += 20
        case .restroom: score += 15
        case .rest_area: score += 10
        case .cafe: score += 10
        case .nursing_room: score += 15
        default: break
        }

        // 大規模施設は通常バリアフリー対応
        if item.pointOfInterestCategory == .restaurant ||
           item.pointOfInterestCategory == .cafe {
            score += 5
        }

        return min(100, score)
    }
}
