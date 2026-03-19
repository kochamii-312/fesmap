import Foundation
import SwiftUI

// スポットカテゴリ
enum SpotCategory: String, Codable, CaseIterable, Identifiable {
    case restroom
    case rest_area // swiftlint:disable:this identifier_name
    case restaurant
    case cafe
    case park
    case kids_space // swiftlint:disable:this identifier_name
    case nursing_room // swiftlint:disable:this identifier_name
    case accessible_restroom // swiftlint:disable:this identifier_name
    case library
    case rental_bicycle // swiftlint:disable:this identifier_name
    case karaoke
    case gym
    case elevator
    case parking
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
    case hotel
    case trash_bin // swiftlint:disable:this identifier_name
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .restroom: return "トイレ"
        case .accessible_restroom: return "多目的トイレ"
        case .rest_area: return "休憩所"
        case .restaurant: return "レストラン"
        case .cafe: return "カフェ"
        case .park: return "公園"
        case .kids_space: return "キッズスペース"
        case .nursing_room: return "授乳室"
        case .library: return "図書館"
        case .rental_bicycle: return "レンタル自転車"
        case .karaoke: return "カラオケ"
        case .gym: return "体育館"
        case .elevator: return "エレベーター"
        case .parking: return "駐車場"
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
        case .hotel: return "ホテル"
        case .trash_bin: return "ゴミ箱"
        case .other: return "その他"
        }
    }

    // SF Symbolsアイコン名
    var iconName: String {
        switch self {
        case .restroom: return "toilet"
        case .accessible_restroom: return "figure.roll"
        case .rest_area: return "chair.lounge"
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .park: return "leaf"
        case .kids_space: return "figure.and.child.holdinghands"
        case .nursing_room: return "heart"
        case .library: return "book.fill"
        case .rental_bicycle: return "bicycle"
        case .karaoke: return "music.mic"
        case .gym: return "figure.run"
        case .elevator: return "arrow.up.arrow.down"
        case .parking: return "p.square"
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
        case .hotel: return "bed.double"
        case .trash_bin: return "trash"
        case .other: return "mappin"
        }
    }

    // カテゴリ別マーカーカラー
    var markerColor: Color {
        switch self {
        case .cafe: return .brown
        case .restroom: return Color(red: 0.4, green: 0.6, blue: 1.0) // 薄い青
        case .accessible_restroom: return Color(red: 0.0, green: 0.2, blue: 0.7) // 濃い青
        case .rest_area: return .green
        case .restaurant: return .orange
        case .library: return Color(red: 0.3, green: 0.5, blue: 0.3) // 深緑
        case .rental_bicycle: return .cyan
        case .karaoke: return .indigo
        case .gym: return .teal
        case .elevator: return .purple
        case .nursing_room: return .pink
        case .kids_space: return .pink
        case .park: return .green
        case .parking: return .gray
        case .convenience_store: return .mint
        case .ramen: return .red
        case .cinema: return Color(red: 0.5, green: 0.0, blue: 0.5)
        case .bookstore: return Color(red: 0.4, green: 0.3, blue: 0.2)
        case .onsen: return Color(red: 0.9, green: 0.4, blue: 0.3)
        case .game_center: return .yellow
        case .hospital: return .red
        case .atm: return Color(red: 0.2, green: 0.5, blue: 0.2)
        case .post_office: return .red
        case .museum: return Color(red: 0.4, green: 0.4, blue: 0.6)
        case .hotel: return Color(red: 0.3, green: 0.3, blue: 0.7)
        case .trash_bin: return Color(red: 0.4, green: 0.4, blue: 0.4) // グレー
        case .other: return .secondary
        }
    }
}

// フロアタイプ
enum FloorType: String, Codable {
    case flat
    case steps
    case slope
    case mixed
}

// アクセシビリティ情報
struct AccessibilityInfo: Codable {
    let wheelchairAccessible: Bool
    let hasElevator: Bool
    let hasAccessibleRestroom: Bool
    let hasBabyChangingStation: Bool
    let hasNursingRoom: Bool
    let floorType: FloorType
    let notes: [String]
}

// スポット概要（一覧表示用）
struct SpotSummary: Codable, Identifiable {
    var id: String { spotId }
    let spotId: String
    let name: String
    let category: SpotCategory
    let location: LatLng
    var accessibilityScore: Int
    let distanceFromRoute: Double
    var isBarrierFree: Bool = false // バリアフリー対応推定

    // Codable でデフォルト値対応
    enum CodingKeys: String, CodingKey {
        case spotId, name, category, location, accessibilityScore, distanceFromRoute, isBarrierFree
    }

    init(spotId: String, name: String, category: SpotCategory, location: LatLng,
         accessibilityScore: Int, distanceFromRoute: Double, isBarrierFree: Bool = false) {
        self.spotId = spotId
        self.name = name
        self.category = category
        self.location = location
        self.accessibilityScore = accessibilityScore
        self.distanceFromRoute = distanceFromRoute
        self.isBarrierFree = isBarrierFree
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spotId = try container.decode(String.self, forKey: .spotId)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(SpotCategory.self, forKey: .category)
        location = try container.decode(LatLng.self, forKey: .location)
        accessibilityScore = try container.decode(Int.self, forKey: .accessibilityScore)
        distanceFromRoute = try container.decode(Double.self, forKey: .distanceFromRoute)
        isBarrierFree = (try? container.decode(Bool.self, forKey: .isBarrierFree)) ?? false
    }
}

// スポット詳細
struct SpotDetail: Codable, Identifiable {
    var id: String { spotId }
    let spotId: String
    let name: String
    let description: String
    let category: SpotCategory
    let location: LatLng
    let address: String
    let accessibilityScore: Int
    let accessibility: AccessibilityInfo
    let photoUrls: [String]
    let openingHours: String?
    let phoneNumber: String?
    let website: String?
}
