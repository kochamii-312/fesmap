import Foundation

// スコア付きスポット
struct ScoredSpot: Identifiable {
    var id: String { spot.spotId }
    let spot: SpotSummary
    let relevanceScore: Int
    let relevanceReason: String
}

// パーソナライズされたスポット推薦サービス
enum NearbySpotService {

    // パーソナライズされたスポットを取得（上位10件）
    static func fetchPersonalizedSpots(
        lat: Double,
        lng: Double,
        radius: Int = 500
    ) async -> [ScoredSpot] {
        let needs = UserNeedsService.loadUnifiedNeeds()

        // 複数ソースからスポットを取得
        var allSpots: [SpotSummary] = []

        // Google Places API
        do {
            let googleSpots = try await APIService.shared.getNearbySpots(
                lat: lat, lng: lng, radiusMeters: radius
            )
            allSpots.append(contentsOf: googleSpots)
        } catch {
            // Google Places失敗
        }

        // YOLP
        do {
            let yolpSpots = try await APIService.shared.getNearbySpotsByYOLP(
                lat: lat, lng: lng, radiusMeters: radius
            )
            // 重複除去してマージ
            let existingIds = Set(allSpots.map(\.spotId))
            let newSpots = yolpSpots.filter { !existingIds.contains($0.spotId) }
            allSpots.append(contentsOf: newSpots)
        } catch {
            // YOLP失敗
        }

        // 両方失敗した場合はモックデータ
        if allSpots.isEmpty {
            allSpots = generateMockSpots(lat: lat, lng: lng, needs: needs)
        }

        // スコアリング
        let scored = allSpots.map { spot in
            scoreSpot(spot, needs: needs)
        }

        // スコア順で上位10件を返す
        return Array(scored.sorted { $0.relevanceScore > $1.relevanceScore }.prefix(10))
    }

    // スポットのスコアリング
    static func scoreSpot(_ spot: SpotSummary, needs: UnifiedUserNeeds) -> ScoredSpot {
        var score = 0
        var reasons: [String] = []

        // ベーススコア（アクセシビリティスコアの30%）
        score += Int(Double(spot.accessibilityScore) * 0.3)

        // 移動手段に応じたボーナス
        switch needs.mobilityType {
        case .wheelchair:
            if spot.category == .elevator {
                score += 30
                reasons.append("車椅子向けエレベーター")
            }
            if spot.category == .restroom {
                score += 25
                reasons.append("多目的トイレ")
            }
        case .stroller:
            if spot.category == .nursing_room || spot.category == .kids_space {
                score += 25
                reasons.append("ベビーカー向け施設")
            }
        case .cane:
            if spot.category == .rest_area {
                score += 25
                reasons.append("休憩スポット")
            }
        default:
            break
        }

        // 同行者ボーナス
        if needs.companions.contains(.child) {
            if spot.category == .nursing_room || spot.category == .kids_space {
                score += 15
                reasons.append("子供向け")
            }
        }
        if needs.companions.contains(.elderly) {
            if spot.category == .rest_area {
                score += 15
                reasons.append("高齢者向け休憩")
            }
        }

        // 好み条件ボーナス
        for prefer in needs.preferConditions {
            switch prefer {
            case .restroom where spot.category == .restroom:
                score += 20
                reasons.append("トイレ希望")
            case .rest_area where spot.category == .rest_area:
                score += 20
                reasons.append("休憩所希望")
            case .covered where spot.category == .rest_area:
                score += 10
            case .cafe where spot.category == .cafe:
                score += 20
                reasons.append("カフェ希望")
            default:
                break
            }
        }

        // 0-100に正規化
        let normalizedScore = min(100, max(0, score))
        let reason = reasons.isEmpty ? "アクセシビリティスコア" : reasons.joined(separator: "、")

        return ScoredSpot(spot: spot, relevanceScore: normalizedScore, relevanceReason: reason)
    }

    // モックスポット生成
    static func generateMockSpots(lat: Double, lng: Double, needs: UnifiedUserNeeds) -> [SpotSummary] {
        var spots: [SpotSummary] = [
            SpotSummary(spotId: "mock_1", name: "バリアフリートイレ", category: .restroom,
                       location: LatLng(lat: lat + 0.001, lng: lng + 0.001),
                       accessibilityScore: 95, distanceFromRoute: 50),
            SpotSummary(spotId: "mock_2", name: "休憩ベンチ", category: .rest_area,
                       location: LatLng(lat: lat - 0.001, lng: lng + 0.002),
                       accessibilityScore: 80, distanceFromRoute: 120),
            SpotSummary(spotId: "mock_3", name: "カフェ", category: .cafe,
                       location: LatLng(lat: lat + 0.002, lng: lng - 0.001),
                       accessibilityScore: 72, distanceFromRoute: 200),
            SpotSummary(spotId: "mock_4", name: "エレベーター", category: .elevator,
                       location: LatLng(lat: lat - 0.0005, lng: lng + 0.0005),
                       accessibilityScore: 88, distanceFromRoute: 80),
        ]

        // 移動手段に応じた追加スポット
        if needs.mobilityType == .wheelchair {
            spots.append(SpotSummary(
                spotId: "mock_wc_1", name: "車椅子対応施設", category: .elevator,
                location: LatLng(lat: lat + 0.0015, lng: lng),
                accessibilityScore: 96, distanceFromRoute: 30
            ))
        }
        if needs.mobilityType == .stroller {
            spots.append(SpotSummary(
                spotId: "mock_st_1", name: "授乳室", category: .nursing_room,
                location: LatLng(lat: lat, lng: lng + 0.0015),
                accessibilityScore: 94, distanceFromRoute: 60
            ))
        }

        return spots
    }
}
