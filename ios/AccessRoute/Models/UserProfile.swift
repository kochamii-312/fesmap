import Foundation

// 移動手段の種類
enum MobilityType: String, Codable, CaseIterable, Identifiable {
    case wheelchair
    case stroller
    case cane
    case walk
    case other

    var id: String { rawValue }

    // 表示用ラベル
    var label: String {
        switch self {
        case .wheelchair: return "車椅子"
        case .stroller: return "ベビーカー"
        case .cane: return "杖"
        case .walk: return "徒歩"
        case .other: return "その他"
        }
    }

    // アイコン名（SF Symbols）
    var iconName: String {
        switch self {
        case .wheelchair: return "figure.roll"
        case .stroller: return "stroller"
        case .cane: return "figure.walk.motion"
        case .walk: return "figure.walk"
        case .other: return "questionmark.circle"
        }
    }

    // 絵文字アイコン
    var emoji: String {
        switch self {
        case .wheelchair: return "♿️"
        case .stroller: return "👶"
        case .cane: return "🦯"
        case .walk: return "🚶"
        case .other: return "❓"
        }
    }

    // テーマカラー名
    var colorHex: String {
        switch self {
        case .wheelchair: return "#007AFF"
        case .stroller: return "#5856D6"
        case .cane: return "#FF9500"
        case .walk: return "#34C759"
        case .other: return "#8E8E93"
        }
    }

    // 説明テキスト（選択肢の補足情報）
    var descriptionText: String {
        switch self {
        case .wheelchair: return "電動・手動どちらも対応"
        case .stroller: return "ベビーカーでの移動に最適化"
        case .cane: return "杖や歩行補助具を使用"
        case .walk: return "特別な補助具なしで歩行"
        case .other: return "上記以外の移動方法"
        }
    }
}

// 同行者の種類
enum Companion: String, Codable, CaseIterable, Identifiable {
    case child
    case elderly
    case disability

    var id: String { rawValue }

    var label: String {
        switch self {
        case .child: return "子ども"
        case .elderly: return "高齢者"
        case .disability: return "障がい者"
        }
    }

    var iconName: String {
        switch self {
        case .child: return "figure.and.child.holdinghands"
        case .elderly: return "figure.walk.diamond"
        case .disability: return "accessibility"
        }
    }

    // 説明テキスト
    var descriptionText: String {
        switch self {
        case .child: return "未就学児〜小学生のお子様"
        case .elderly: return "歩行ペースへの配慮が必要"
        case .disability: return "身体・視覚・聴覚等の障がい"
        }
    }
}

// 回避条件
enum AvoidCondition: String, Codable, CaseIterable, Identifiable {
    case stairs
    case slope
    case crowd
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stairs: return "階段"
        case .slope: return "急な坂道"
        case .crowd: return "混雑"
        case .dark: return "暗い道"
        }
    }

    var iconName: String {
        switch self {
        case .stairs: return "stairs"
        case .slope: return "arrow.up.right"
        case .crowd: return "person.3.fill"
        case .dark: return "moon.fill"
        }
    }

    // 絵文字アイコン
    var emoji: String {
        switch self {
        case .stairs: return "🪜"
        case .slope: return "⛰️"
        case .crowd: return "👥"
        case .dark: return "🌙"
        }
    }

    // 説明テキスト
    var descriptionText: String {
        switch self {
        case .stairs: return "段差・階段のあるルートを除外"
        case .slope: return "勾配のきつい坂道を除外"
        case .crowd: return "人混みの多いエリアを回避"
        case .dark: return "照明が不十分な道を回避"
        }
    }
}

// 希望条件
enum PreferCondition: String, Codable, CaseIterable, Identifiable {
    case restroom
    case rest_area // swiftlint:disable:this identifier_name
    case covered
    case cafe
    case restaurant
    case library
    case rental_bicycle // swiftlint:disable:this identifier_name
    case karaoke
    case gym
    case elevator

    var id: String { rawValue }

    var label: String {
        switch self {
        case .restroom: return "トイレ"
        case .rest_area: return "休憩所"
        case .covered: return "屋根あり"
        case .cafe: return "カフェ"
        case .restaurant: return "レストラン"
        case .library: return "図書館"
        case .rental_bicycle: return "レンタル自転車"
        case .karaoke: return "カラオケ"
        case .gym: return "体育館"
        case .elevator: return "エレベーター"
        }
    }

    var iconName: String {
        switch self {
        case .restroom: return "toilet"
        case .rest_area: return "bench.and.tree"
        case .covered: return "umbrella.fill"
        case .cafe: return "cup.and.saucer.fill"
        case .restaurant: return "fork.knife"
        case .library: return "book.fill"
        case .rental_bicycle: return "bicycle"
        case .karaoke: return "music.mic"
        case .gym: return "figure.run"
        case .elevator: return "arrow.up.arrow.down"
        }
    }

    // 絵文字アイコン
    var emoji: String {
        switch self {
        case .restroom: return "🚻"
        case .rest_area: return "🪑"
        case .covered: return "☂️"
        case .cafe: return "☕"
        case .restaurant: return "🍽️"
        case .library: return "📚"
        case .rental_bicycle: return "🚲"
        case .karaoke: return "🎤"
        case .gym: return "🏋️"
        case .elevator: return "🛗"
        }
    }

    // 説明テキスト
    var descriptionText: String {
        switch self {
        case .restroom: return "バリアフリートイレがあるルート優先"
        case .rest_area: return "ベンチ等の休憩場所を経由"
        case .covered: return "雨天時も安心な屋根付きルート"
        case .cafe: return "カフェで休憩できるルート"
        case .restaurant: return "周辺のレストランを表示"
        case .library: return "周辺の図書館を表示"
        case .rental_bicycle: return "レンタル自転車ポートを表示"
        case .karaoke: return "周辺のカラオケを表示"
        case .gym: return "周辺の体育館・ジムを表示"
        case .elevator: return "周辺のエレベーターを表示"
        }
    }
}

// ユーザープロファイル
struct UserProfile: Codable, Identifiable {
    var id: String { userId }
    let userId: String
    var mobilityType: MobilityType
    var companions: [Companion]
    var maxDistanceMeters: Double
    var avoidConditions: [AvoidCondition]
    var preferConditions: [PreferCondition]
    let createdAt: Date?
    let updatedAt: Date?
}

// API送信用（createdAt/updatedAtを含まない）
struct UserProfileInput: Codable {
    let mobilityType: MobilityType
    let companions: [Companion]
    let maxDistanceMeters: Double
    let avoidConditions: [AvoidCondition]
    let preferConditions: [PreferCondition]
}
