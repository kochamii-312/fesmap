import Foundation

// Directions API結果のパースとアクセシビリティスコア算出
enum DirectionsService {

    // 階段関連キーワード
    private static let stairsKeywords = [
        "階段", "stairs", "steps", "stairway", "staircase",
        "地下道", "underground passage", "歩道橋", "overpass"
    ]

    // 坂道関連キーワード
    private static let slopeKeywords = [
        "坂", "slope", "hill", "上り坂", "下り坂",
        "急な", "steep", "勾配", "incline"
    ]

    // テキストから階段があるか検出
    static func detectStairs(in text: String) -> Bool {
        let lowered = text.lowercased()
        return stairsKeywords.contains { lowered.contains($0) }
    }

    // テキストから坂道があるか検出
    static func detectSlope(in text: String) -> Bool {
        let lowered = text.lowercased()
        return slopeKeywords.contains { lowered.contains($0) }
    }

    // アクセシビリティスコアを算出（100点満点）
    static func calculateAccessibilityScore(
        steps: [RouteStep],
        transferCount: Int = 0
    ) -> Int {
        var score = 100

        for step in steps {
            if step.hasStairs { score -= 15 }
            if step.hasSlope { score -= 8 }
        }

        // 乗換回数によるペナルティ
        score -= transferCount * 5

        return max(0, min(100, score))
    }

    // 警告メッセージを生成
    static func generateWarnings(steps: [RouteStep]) -> [String] {
        var warnings: [String] = []

        let stairsSteps = steps.filter { $0.hasStairs }
        let slopeSteps = steps.filter { $0.hasSlope }

        if !stairsSteps.isEmpty {
            warnings.append("⚠️ ルート上に\(stairsSteps.count)箇所の階段があります")
        }
        if !slopeSteps.isEmpty {
            warnings.append("⚠️ ルート上に\(slopeSteps.count)箇所の坂道があります")
        }

        let totalDistance = steps.reduce(0.0) { $0 + $1.distanceMeters }
        if totalDistance > 2000 {
            warnings.append("ℹ️ 総距離が\(AccessibilityHelpers.distanceText(meters: totalDistance))です")
        }

        return warnings
    }

    // HTMLタグを除去
    static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
