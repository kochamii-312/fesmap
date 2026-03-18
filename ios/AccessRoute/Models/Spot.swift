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
    case elevator
    case parking
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .restroom: return "トイレ"
        case .rest_area: return "休憩所"
        case .restaurant: return "レストラン"
        case .cafe: return "カフェ"
        case .park: return "公園"
        case .kids_space: return "キッズスペース"
        case .nursing_room: return "授乳室"
        case .elevator: return "エレベーター"
        case .parking: return "駐車場"
        case .other: return "その他"
        }
    }

    // SF Symbolsアイコン名
    var iconName: String {
        switch self {
        case .restroom: return "toilet"
        case .rest_area: return "bench.and.tree"
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .park: return "leaf"
        case .kids_space: return "figure.and.child.holdinghands"
        case .nursing_room: return "heart"
        case .elevator: return "arrow.up.arrow.down"
        case .parking: return "p.square"
        case .other: return "mappin"
        }
    }

    // カテゴリ別マーカーカラー
    var markerColor: Color {
        switch self {
        case .cafe: return .brown
        case .restroom: return .blue
        case .rest_area: return .green
        case .restaurant: return .orange
        case .elevator: return .purple
        case .nursing_room: return .pink
        case .kids_space: return .pink
        case .park: return .green
        case .parking: return .gray
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
    let accessibilityScore: Int
    let distanceFromRoute: Double
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
