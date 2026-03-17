import SwiftUI

// 交通手段
enum TransportMode: String, Codable, CaseIterable, Identifiable {
    case walking
    case transit
    case driving
    case bicycling

    var id: String { rawValue }

    // 表示名
    var label: String {
        switch self {
        case .walking: return "徒歩"
        case .transit: return "電車"
        case .driving: return "車"
        case .bicycling: return "自転車"
        }
    }

    // SF Symbolsアイコン名
    var iconName: String {
        switch self {
        case .walking: return "figure.walk"
        case .transit: return "tram.fill"
        case .driving: return "car.fill"
        case .bicycling: return "bicycle"
        }
    }

    // テーマカラー
    var color: Color {
        switch self {
        case .walking: return .blue
        case .transit: return .green
        case .driving: return .orange
        case .bicycling: return .purple
        }
    }
}
