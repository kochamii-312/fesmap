import Foundation

// 乗換詳細情報
struct TransitDetail: Codable, Identifiable {
    var id: String { "\(lineName)-\(departureStop)" }
    let lineName: String
    let vehicleType: String
    let departureStop: String
    let arrivalStop: String
    let numStops: Int
    let departureTime: String?
    let arrivalTime: String?
    let lineColor: String?
}

// 区間（レグ）
struct WaypointLeg: Codable, Identifiable {
    var id: Int { legIndex }
    let legIndex: Int
    let mode: String
    let origin: LatLng
    let destination: LatLng
    let distanceMeters: Double
    let durationSeconds: Double
    let steps: [RouteStep]
    let transitDetail: TransitDetail?
}

// マルチモーダルルート
struct MultiModalRoute: Codable, Identifiable {
    var id: String { routeId }
    let routeId: String
    let totalDistanceMeters: Double
    let totalDurationSeconds: Double
    let accessibilityScore: Int
    let legs: [WaypointLeg]
    let warnings: [String]
    let fare: String?
}
