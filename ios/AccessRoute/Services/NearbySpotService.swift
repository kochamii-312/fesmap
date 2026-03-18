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

        var allSpots: [SpotSummary] = []

        do {
            let googleSpots = try await APIService.shared.getNearbySpots(
                lat: lat, lng: lng, radiusMeters: radius
            )
            allSpots.append(contentsOf: googleSpots)
        } catch {}

        do {
            let yolpSpots = try await APIService.shared.getNearbySpotsByYOLP(
                lat: lat, lng: lng, radiusMeters: radius
            )
            let existingIds = Set(allSpots.map(\.spotId))
            let newSpots = yolpSpots.filter { !existingIds.contains($0.spotId) }
            allSpots.append(contentsOf: newSpots)
        } catch {}

        if allSpots.isEmpty {
            allSpots = generateMockSpots(lat: lat, lng: lng, needs: needs)
        }

        let scored = allSpots.map { spot in
            scoreSpot(spot, needs: needs)
        }

        return Array(scored.sorted { $0.relevanceScore > $1.relevanceScore }.prefix(10))
    }

    // MARK: - プロフィール関連度スコアリング

    /// プロフィールとの関連度でスコアリング（0〜100）
    /// - 移動手段との相性: 最大40点
    /// - 好み条件との一致: 最大30点
    /// - 距離の近さ: 最大15点
    /// - 同行者との相性: 最大15点
    static func scoreSpot(_ spot: SpotSummary, needs: UnifiedUserNeeds) -> ScoredSpot {
        var score = 0
        var reasons: [String] = []

        // 1. バリアフリー対応 × 移動手段（最大40点）
        let needsBarrierFree = (needs.mobilityType == .wheelchair ||
                                needs.mobilityType == .stroller ||
                                needs.companions.contains(.disability))

        // バリアフリー対応施設はどのカテゴリでもスコアアップ
        if needsBarrierFree && spot.isBarrierFree {
            score += 25
            reasons.append("バリアフリー対応")
        }

        // カテゴリ基本点（全ユーザー共通）
        switch spot.category {
        case .accessible_restroom:
            score += 15
        case .elevator:
            score += 10
        case .restroom:
            score += 10
        case .cafe:
            score += 10
        case .restaurant:
            score += 10
        case .library:
            score += 10
        case .rental_bicycle:
            score += 10
        case .nursing_room, .kids_space:
            score += 10
        case .rest_area:
            score += 10
        default:
            score += 5
        }

        // 移動手段に特に関連するカテゴリの追加ボーナス
        switch needs.mobilityType {
        case .wheelchair:
            if spot.category == .accessible_restroom { score += 10; reasons.append("車椅子対応トイレ") }
            if spot.category == .elevator { score += 10; reasons.append("エレベーター") }
        case .stroller:
            if spot.category == .nursing_room || spot.category == .kids_space {
                score += 10; reasons.append("ベビーカー向け")
            }
            if spot.category == .elevator { score += 10; reasons.append("エレベーター") }
        case .cane:
            if spot.category == .rest_area { score += 10; reasons.append("休憩スポット") }
        default:
            break
        }

        // 2. 好み条件との一致（最大30点）
        for prefer in needs.preferConditions {
            switch prefer {
            case .restroom where spot.category == .restroom || spot.category == .accessible_restroom:
                score += 30
                if !reasons.contains(where: { $0.contains("トイレ") }) {
                    reasons.append("トイレ希望に一致")
                }
            case .cafe where spot.category == .cafe:
                score += 30
                reasons.append("カフェ希望に一致")
            case .restaurant where spot.category == .restaurant:
                score += 30
                reasons.append("レストラン希望に一致")
            case .library where spot.category == .library:
                score += 30
                reasons.append("図書館希望に一致")
            case .rental_bicycle where spot.category == .rental_bicycle:
                score += 30
                reasons.append("レンタル自転車希望に一致")
            case .rest_area where spot.category == .rest_area:
                score += 25
            case .covered where spot.category == .rest_area:
                score += 15
            default:
                break
            }
        }

        // 3. 距離の近さ（最大15点）
        if spot.distanceFromRoute > 0 {
            if spot.distanceFromRoute < 100 {
                score += 15
                reasons.append("すぐ近く")
            } else if spot.distanceFromRoute < 300 {
                score += 10
            } else if spot.distanceFromRoute < 500 {
                score += 5
            }
        } else {
            score += 8 // 距離不明の場合
        }

        // 4. 同行者との相性（最大15点）
        if needs.companions.contains(.child) {
            if spot.category == .nursing_room || spot.category == .kids_space {
                score += 15
                reasons.append("子供向け")
            } else if spot.category == .cafe || spot.category == .restaurant {
                score += 5
            }
        }
        if needs.companions.contains(.elderly) {
            if spot.category == .rest_area || spot.category == .cafe {
                score += 15
                reasons.append("高齢者向け休憩")
            } else if spot.category == .accessible_restroom || spot.category == .elevator {
                score += 10
            }
        }
        if needs.companions.contains(.disability) {
            if spot.category == .accessible_restroom || spot.category == .elevator {
                score += 15
                reasons.append("バリアフリー対応")
            }
        }

        // 0-100に正規化
        let normalizedScore = min(100, max(0, score))
        let reason = reasons.isEmpty ? "周辺施設" : reasons.joined(separator: "、")

        return ScoredSpot(spot: spot, relevanceScore: normalizedScore, relevanceReason: reason)
    }

    // モックスポット生成
    static func generateMockSpots(lat: Double, lng: Double, needs: UnifiedUserNeeds) -> [SpotSummary] {
        [
            SpotSummary(spotId: "mock_1", name: "バリアフリートイレ", category: .accessible_restroom,
                       location: LatLng(lat: lat + 0.001, lng: lng + 0.001),
                       accessibilityScore: 95, distanceFromRoute: 50),
            SpotSummary(spotId: "mock_2", name: "休憩ベンチ", category: .rest_area,
                       location: LatLng(lat: lat - 0.001, lng: lng + 0.002),
                       accessibilityScore: 80, distanceFromRoute: 120),
            SpotSummary(spotId: "mock_3", name: "カフェ", category: .cafe,
                       location: LatLng(lat: lat + 0.002, lng: lng - 0.001),
                       accessibilityScore: 72, distanceFromRoute: 200),
        ]
    }
}
