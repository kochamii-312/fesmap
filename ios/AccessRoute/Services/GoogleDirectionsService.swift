import Foundation
import CoreLocation

// Google Directions API を直接呼び出して電車ルートを取得するサービス
enum GoogleDirectionsService {

    private static let baseURL = "https://maps.googleapis.com/maps/api/directions/json"

    // Google Directions API のレスポンス構造
    struct DirectionsResponse: Codable {
        let routes: [GRoute]
        let status: String
    }

    struct GRoute: Codable {
        let legs: [GLeg]
        let overview_polyline: GPolyline // swiftlint:disable:this identifier_name
    }

    struct GLeg: Codable {
        let steps: [GStep]
        let distance: GValue
        let duration: GValue
        let start_address: String? // swiftlint:disable:this identifier_name
        let end_address: String? // swiftlint:disable:this identifier_name
    }

    struct GStep: Codable {
        let html_instructions: String // swiftlint:disable:this identifier_name
        let distance: GValue
        let duration: GValue
        let travel_mode: String // swiftlint:disable:this identifier_name
        let polyline: GPolyline
        let transit_details: GTransitDetails? // swiftlint:disable:this identifier_name
        let steps: [GStep]? // サブステップ（徒歩区間内の詳細）
    }

    struct GValue: Codable {
        let text: String
        let value: Int
    }

    struct GPolyline: Codable {
        let points: String
    }

    struct GTransitDetails: Codable {
        let line: GTransitLine
        let departure_stop: GStop // swiftlint:disable:this identifier_name
        let arrival_stop: GStop // swiftlint:disable:this identifier_name
        let num_stops: Int // swiftlint:disable:this identifier_name
        let departure_time: GTime? // swiftlint:disable:this identifier_name
        let arrival_time: GTime? // swiftlint:disable:this identifier_name
    }

    struct GTransitLine: Codable {
        let name: String
        let short_name: String? // swiftlint:disable:this identifier_name
        let color: String?
        let vehicle: GVehicle?
    }

    struct GVehicle: Codable {
        let name: String
        let type: String
    }

    struct GStop: Codable {
        let name: String
        let location: GLocation
    }

    struct GLocation: Codable {
        let lat: Double
        let lng: Double
    }

    struct GTime: Codable {
        let text: String
        let value: Int
    }

    // MARK: - 検索結果

    struct TransitRouteInfo {
        let steps: [RouteStep]
        let polylineCoordinates: [CLLocationCoordinate2D]
        let totalDistanceMeters: Double
        let totalDurationMinutes: Double
        let warnings: [String]
        let accessibilityScore: Int
        let segments: [TransitDisplaySegment]
    }

    struct TransitDisplaySegment {
        let coordinates: [CLLocationCoordinate2D]
        let isWalking: Bool
        let lineName: String?
        let lineColor: String?
    }

    // MARK: - API 呼び出し

    // 電車ルートを検索（複数ルート対応）
    // Google transit は alternatives が効きにくいため、異なる出発時刻で複数検索
    static func searchTransit(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D
    ) async throws -> [TransitRouteInfo] {
        let apiKey = AppConfig.googleMapsAPIKey
        guard !apiKey.isEmpty else {
            throw GoogleDirectionsError.noAPIKey
        }

        // 異なる条件で複数回検索して多様なルートを取得
        let now = Int(Date().timeIntervalSince1970)

        // 検索バリエーション: (出発時刻オフセット, routing_preference)
        let searchVariations: [(Int, String?)] = [
            (0, nil),                    // デフォルト
            (0, "fewer_transfers"),       // 乗換少なめ
            (0, "less_walking"),          // 歩き少なめ
            (600, nil),                  // 10分後
            (1200, nil),                 // 20分後
            (1200, "fewer_transfers"),    // 20分後・乗換少なめ
        ]

        var allInfos: [TransitRouteInfo] = []
        var seenLineKeys = Set<String>() // 重複排除用

        for (varIdx, variation) in searchVariations.enumerated() {
            guard var components = URLComponents(string: baseURL) else { continue }

            var queryItems = [
                URLQueryItem(name: "origin", value: "\(origin.latitude),\(origin.longitude)"),
                URLQueryItem(name: "destination", value: "\(destination.latitude),\(destination.longitude)"),
                URLQueryItem(name: "mode", value: "transit"),
                URLQueryItem(name: "alternatives", value: "true"),
                URLQueryItem(name: "departure_time", value: String(now + variation.0)),
                URLQueryItem(name: "language", value: "ja"),
                URLQueryItem(name: "region", value: "jp"),
                URLQueryItem(name: "key", value: apiKey),
            ]

            if let pref = variation.1 {
                queryItems.append(URLQueryItem(name: "transit_routing_preference", value: pref))
            }

            components.queryItems = queryItems
            guard let url = components.url else { continue }

            var request = URLRequest(url: url)
            request.timeoutInterval = 15

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else { continue }

                let directionsResponse = try JSONDecoder().decode(DirectionsResponse.self, from: data)

                guard directionsResponse.status == "OK" else { continue }

                for (routeIdx, route) in directionsResponse.routes.enumerated() {
                    let info = parseRoute(route, index: varIdx * 10 + routeIdx)

                    // 路線の組み合わせで重複排除
                    let lineKey = info.warnings.first { $0.hasPrefix("🚃") } ?? "unknown_\(allInfos.count)"
                    if !seenLineKeys.contains(lineKey) {
                        seenLineKeys.insert(lineKey)
                        allInfos.append(info)
                    }
                }
            } catch {
                continue
            }
        }

        guard !allInfos.isEmpty else {
            throw GoogleDirectionsError.noRouteFound("ZERO_RESULTS")
        }

        // アクセシビリティスコア順でソート
        return allInfos.sorted { $0.accessibilityScore > $1.accessibilityScore }
    }

    // MARK: - レスポンス解析

    private static func parseRoute(_ route: GRoute, index: Int = 0) -> TransitRouteInfo {
        var allSteps: [RouteStep] = []
        var allCoordinates: [CLLocationCoordinate2D] = []
        var warnings: [String] = []
        var segments: [TransitDisplaySegment] = []
        var totalDistance: Double = 0
        var totalDuration: Double = 0
        var transferCount = 0
        var transitLineNames: [String] = []

        for leg in route.legs {
            totalDistance += Double(leg.distance.value)
            totalDuration += Double(leg.duration.value)

            for (stepIdx, step) in leg.steps.enumerated() {
                let stepCoords = PolylineDecoder.decode(step.polyline.points)
                allCoordinates.append(contentsOf: stepCoords)

                if step.travel_mode == "TRANSIT", let transit = step.transit_details {
                    // 電車ステップ
                    let lineName = transit.line.name
                    if !transitLineNames.contains(lineName) {
                        transitLineNames.append(lineName)
                    } else {
                        transferCount += 1
                    }

                    // 乗車ステップ
                    allSteps.append(RouteStep(
                        stepId: "g_board_\(index)_\(stepIdx)",
                        instruction: "\(transit.departure_stop.name)から\(lineName)に乗車",
                        distanceMeters: 0,
                        durationSeconds: 60,
                        startLocation: LatLng(
                            lat: transit.departure_stop.location.lat,
                            lng: transit.departure_stop.location.lng
                        ),
                        endLocation: LatLng(
                            lat: transit.departure_stop.location.lat,
                            lng: transit.departure_stop.location.lng
                        ),
                        polyline: step.polyline.points,
                        hasStairs: false,
                        hasSlope: false,
                        slopeGrade: nil,
                        surfaceType: .paved
                    ))

                    // 乗車区間ステップ
                    let departureTime = transit.departure_time?.text ?? ""
                    let arrivalTime = transit.arrival_time?.text ?? ""
                    var instruction = "\(transit.departure_stop.name) → \(transit.arrival_stop.name)（\(lineName)）"
                    if !departureTime.isEmpty && !arrivalTime.isEmpty {
                        instruction += " \(departureTime)→\(arrivalTime)"
                    }

                    allSteps.append(RouteStep(
                        stepId: "g_ride_\(index)_\(stepIdx)",
                        instruction: instruction,
                        distanceMeters: Double(step.distance.value),
                        durationSeconds: Double(step.duration.value),
                        startLocation: LatLng(
                            lat: transit.departure_stop.location.lat,
                            lng: transit.departure_stop.location.lng
                        ),
                        endLocation: LatLng(
                            lat: transit.arrival_stop.location.lat,
                            lng: transit.arrival_stop.location.lng
                        ),
                        polyline: step.polyline.points,
                        hasStairs: false,
                        hasSlope: false,
                        slopeGrade: nil,
                        surfaceType: .paved
                    ))

                    // 下車ステップ
                    allSteps.append(RouteStep(
                        stepId: "g_alight_\(index)_\(stepIdx)",
                        instruction: "\(transit.arrival_stop.name)で下車",
                        distanceMeters: 0,
                        durationSeconds: 60,
                        startLocation: LatLng(
                            lat: transit.arrival_stop.location.lat,
                            lng: transit.arrival_stop.location.lng
                        ),
                        endLocation: LatLng(
                            lat: transit.arrival_stop.location.lat,
                            lng: transit.arrival_stop.location.lng
                        ),
                        polyline: "",
                        hasStairs: transferCount > 0,
                        hasSlope: false,
                        slopeGrade: nil,
                        surfaceType: .paved
                    ))

                    // 表示用セグメント（電車）
                    segments.append(TransitDisplaySegment(
                        coordinates: stepCoords,
                        isWalking: false,
                        lineName: lineName,
                        lineColor: transit.line.color
                    ))

                } else {
                    // 徒歩ステップ
                    let instruction = stripHTML(step.html_instructions)
                    let hasStairs = DirectionsService.detectStairs(in: instruction)
                    let hasSlope = DirectionsService.detectSlope(in: instruction)

                    allSteps.append(RouteStep(
                        stepId: "g_walk_\(index)_\(stepIdx)",
                        instruction: instruction.isEmpty ? "徒歩" : instruction,
                        distanceMeters: Double(step.distance.value),
                        durationSeconds: Double(step.duration.value),
                        startLocation: LatLng(
                            lat: stepCoords.first?.latitude ?? 0,
                            lng: stepCoords.first?.longitude ?? 0
                        ),
                        endLocation: LatLng(
                            lat: stepCoords.last?.latitude ?? 0,
                            lng: stepCoords.last?.longitude ?? 0
                        ),
                        polyline: step.polyline.points,
                        hasStairs: hasStairs,
                        hasSlope: hasSlope,
                        slopeGrade: nil,
                        surfaceType: .paved
                    ))

                    // 表示用セグメント（徒歩）
                    if !stepCoords.isEmpty {
                        segments.append(TransitDisplaySegment(
                            coordinates: stepCoords,
                            isWalking: true,
                            lineName: nil,
                            lineColor: nil
                        ))
                    }
                }
            }
        }

        // 警告生成
        if !transitLineNames.isEmpty {
            warnings.append("🚃 \(transitLineNames.joined(separator: " → "))")
        }
        if transferCount > 0 {
            warnings.append("🔄 乗り換え\(transferCount)回")
        }
        let stairsSteps = allSteps.filter(\.hasStairs)
        if !stairsSteps.isEmpty {
            warnings.append("⚠️ ルート上に階段があります")
        }
        warnings.append("ℹ️ 所要時間は目安です")

        // アクセシビリティスコア
        let score = DirectionsService.calculateAccessibilityScore(
            steps: allSteps, transferCount: transferCount
        )

        return TransitRouteInfo(
            steps: allSteps,
            polylineCoordinates: allCoordinates,
            totalDistanceMeters: totalDistance,
            totalDurationMinutes: totalDuration / 60,
            warnings: warnings,
            accessibilityScore: score,
            segments: segments
        )
    }

    // HTMLタグを除去
    private static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

// Google Directions エラー
enum GoogleDirectionsError: LocalizedError {
    case noAPIKey
    case invalidURL
    case apiError(String)
    case noRouteFound(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Google Maps APIキーが設定されていません"
        case .invalidURL:
            return "無効なURLです"
        case .apiError(let message):
            return "APIエラー: \(message)"
        case .noRouteFound(let status):
            return "ルートが見つかりません (\(status))"
        }
    }
}
