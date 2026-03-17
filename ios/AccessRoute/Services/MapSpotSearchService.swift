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

        // 各キーワードで並列検索
        await withTaskGroup(of: [SpotSummary].self) { group in
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
            for await spots in group {
                allSpots.append(contentsOf: spots)
            }
        }

        // 重複除去（名前で）
        var seen = Set<String>()
        allSpots = allSpots.filter { spot in
            let key = "\(spot.name)_\(spot.location.lat)"
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

        for prefer in needs.preferConditions {
            switch prefer {
            case .cafe:
                queries.append(("カフェ", .cafe))
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
