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
    case nursing_room // swiftlint:disable:this identifier_name
    case parking_spot // swiftlint:disable:this identifier_name
    case convenience_store // swiftlint:disable:this identifier_name
    case ramen
    case cinema
    case bookstore
    case onsen
    case game_center // swiftlint:disable:this identifier_name
    case hospital
    case atm
    case post_office // swiftlint:disable:this identifier_name
    case museum
    case park
    case hotel
    case trash_bin // swiftlint:disable:this identifier_name

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
        case .nursing_room: return "授乳室"
        case .parking_spot: return "駐車場"
        case .convenience_store: return "コンビニ"
        case .ramen: return "ラーメン"
        case .cinema: return "映画館"
        case .bookstore: return "本屋"
        case .onsen: return "温泉・銭湯"
        case .game_center: return "ゲームセンター"
        case .hospital: return "病院"
        case .atm: return "ATM"
        case .post_office: return "郵便局"
        case .museum: return "美術館"
        case .park: return "公園"
        case .hotel: return "ホテル"
        case .trash_bin: return "ゴミ箱"
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
        case .nursing_room: return "heart"
        case .parking_spot: return "p.square"
        case .convenience_store: return "storefront"
        case .ramen: return "takeoutbag.and.cup.and.straw"
        case .cinema: return "film"
        case .bookstore: return "text.book.closed"
        case .onsen: return "drop.fill"
        case .game_center: return "gamecontroller"
        case .hospital: return "cross.case"
        case .atm: return "banknote"
        case .post_office: return "envelope"
        case .museum: return "building.columns"
        case .park: return "leaf"
        case .hotel: return "bed.double"
        case .trash_bin: return "trash"
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
        case .nursing_room: return "🍼"
        case .parking_spot: return "🅿️"
        case .convenience_store: return "🏪"
        case .ramen: return "🍜"
        case .cinema: return "🎬"
        case .bookstore: return "📖"
        case .onsen: return "♨️"
        case .game_center: return "🕹️"
        case .hospital: return "🏥"
        case .atm: return "🏧"
        case .post_office: return "📮"
        case .museum: return "🖼️"
        case .park: return "🌳"
        case .hotel: return "🏨"
        case .trash_bin: return "🗑️"
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
        case .nursing_room: return "周辺の授乳室を表示"
        case .parking_spot: return "周辺の駐車場を表示"
        case .convenience_store: return "周辺のコンビニを表示"
        case .ramen: return "周辺のラーメンを表示"
        case .cinema: return "周辺の映画館を表示"
        case .bookstore: return "周辺の本屋を表示"
        case .onsen: return "周辺の温泉・銭湯を表示"
        case .game_center: return "周辺のゲームセンターを表示"
        case .hospital: return "周辺の病院を表示"
        case .atm: return "周辺のATMを表示"
        case .post_office: return "周辺の郵便局を表示"
        case .museum: return "周辺の美術館を表示"
        case .park: return "周辺の公園を表示"
        case .hotel: return "周辺のホテルを表示"
        case .trash_bin: return "周辺の公共ゴミ箱を表示"
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
