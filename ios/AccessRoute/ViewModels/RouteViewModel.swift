import Foundation
import MapKit
import SwiftUI

// ルート検索画面のViewModel
@MainActor
final class RouteViewModel: ObservableObject {
    @Published var originText = ""
    @Published var destinationText = ""
    @Published var selectedMode: TransportMode = .walking
    @Published var routeResults: [RouteResult] = []
    @Published var selectedRoute: RouteResult?
    @Published var isSearching = false
    @Published var errorMessage: String?

    // MKDirections で取得した MKRoute（ポリライン描画用）
    @Published var mkRoutes: [MKRoute] = []
    @Published var selectedMKRouteIndex: Int = 0

    // 電車ルート用（複数区間のポリライン）
    @Published var transitSegments: [TransitSegment] = []

    // 目的地周辺のおすすめスポット（好みに基づく）
    @Published var destinationSpots: [SpotSummary] = []

    // 事前に確定している目的地座標（チャットスポットから遷移した場合など）
    var presetDestCoord: CLLocationCoordinate2D?

    // 最後に検索した目的地座標
    private var lastDestCoord: CLLocationCoordinate2D?

    // 前回の検索タスク（キャンセル用）
    private var searchTask: Task<Void, Never>?

    // ルート検索
    func searchRouteByName() async {
        // 前回の検索をキャンセル
        searchTask?.cancel()
        let task = Task {
            let origin = originText.trimmingCharacters(in: .whitespacesAndNewlines)
            let destination = destinationText.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !destination.isEmpty else {
                errorMessage = "目的地を入力してください"
                return
            }

            isSearching = true
            errorMessage = nil
            mkRoutes = []
            routeResults = []
            transitSegments = []

            let originName = origin.isEmpty ? "現在地" : origin
            var searchedDestCL: CLLocationCoordinate2D?

            do {
                let originCoord = try await GeocodingService.shared.geocode(originName)
                // キャンセルされていたら早期終了
                guard !Task.isCancelled else {
                    isSearching = false
                    return
                }

                // 事前に座標が設定されていればジオコーディングをスキップ
                let destCoord: LatLng
                if let preset = presetDestCoord {
                    destCoord = LatLng(lat: preset.latitude, lng: preset.longitude)
                    presetDestCoord = nil
                } else {
                    destCoord = try await GeocodingService.shared.geocode(destination)
                }
                guard !Task.isCancelled else {
                    isSearching = false
                    return
                }

                let originCL = CLLocationCoordinate2D(latitude: originCoord.lat, longitude: originCoord.lng)
                let destCL = CLLocationCoordinate2D(latitude: destCoord.lat, longitude: destCoord.lng)
                searchedDestCL = destCL

                if selectedMode == .transit {
                    await searchTransitRoute(origin: originCL, destination: destCL)
                } else {
                    try await searchMKDirectionsRoute(origin: originCL, destination: destCL)
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = "ルート検索に失敗しました: \(error.localizedDescription)"
                    routeResults = Self.mockRouteResults()
                    if let first = routeResults.first {
                        selectedRoute = first
                    }
                }
            }

            // 目的地周辺のおすすめスポットを検索
            if let destCL = searchedDestCL, !Task.isCancelled {
                lastDestCoord = destCL
                Task {
                    destinationSpots = await MapSpotSearchService.searchSpotsNearDestination(
                        destination: destCL
                    )
                }
            }

            isSearching = false
        }
        searchTask = task
        await task.value
    }

    // MARK: - MKDirections ルート検索（徒歩/車/自転車）

    private func searchMKDirectionsRoute(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D
    ) async throws {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = selectedMode.mkTransportType
        request.requestsAlternateRoutes = true

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()

        mkRoutes = response.routes
        routeResults = response.routes.enumerated().map { index, mkRoute in
            convertMKRouteToResult(mkRoute, index: index)
        }

        if let first = routeResults.first {
            selectedRoute = first
            selectedMKRouteIndex = 0
        }
    }

    // MARK: - 電車ルート検索（ローカル路線DB / Dijkstra）

    private func searchTransitRoute(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D
    ) async {
        // ローカル路線DBで検索（Google Directions API は日本の transit で ZERO_RESULTS を返すため不使用）
        let result: TransitRouteService.TransitRouteResult
        do {
            result = try await TransitRouteService.searchTransitRoute(
                origin: origin, destination: destination
            )
        } catch {
            // ローカル検索失敗 → モックデータにフォールバック
            routeResults = Self.mockTransitRouteResults()
            selectedRoute = routeResults.first
            return
        }

        // 区間ごとのポリラインを構築（路線ごとに色分け）
        let segments = buildTransitSegments(from: result, origin: origin, destination: destination)
        transitSegments = segments

        // RouteResult に変換
        let routeResult = buildRouteResult(
            from: result, origin: origin, destination: destination, routeId: "transit_0"
        )

        routeResults = [routeResult]
        selectedRoute = routeResult
    }

    // MARK: - ローカル路線ルートのセグメント構築

    /// TransitRouteResult から表示用 TransitSegment 配列を構築
    /// 路線ごとに色分けし、徒歩区間は青い破線で表示
    private func buildTransitSegments(
        from result: TransitRouteService.TransitRouteResult,
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D
    ) -> [TransitSegment] {
        var segments: [TransitSegment] = []

        // 1. 出発地→出発駅（徒歩・青い破線）
        if let walkTo = result.walkToStation {
            segments.append(TransitSegment(
                mkRoute: walkTo,
                mode: .walking,
                label: "\(result.originStation.name)まで徒歩",
                color: .blue
            ))
        }

        // 2. 電車区間を路線ごとに色分けしてセグメント化
        let lineSegments = splitPolylineByTransitSteps(result: result)
        segments.append(contentsOf: lineSegments)

        // 3. 到着駅→目的地（徒歩・青い破線）
        if let walkFrom = result.walkFromStation {
            segments.append(TransitSegment(
                mkRoute: walkFrom,
                mode: .walking,
                label: "\(result.destStation.name)から徒歩",
                color: .blue
            ))
        }

        return segments
    }

    /// transitSteps から路線区間を解析し、路線ごとに色分けした TransitSegment を生成
    private func splitPolylineByTransitSteps(
        result: TransitRouteService.TransitRouteResult
    ) -> [TransitSegment] {
        // transitSteps を解析して路線名ごとにグループ化
        // 乗車ステップのフォーマット: "〇〇から△△線で…に乗車"
        // 乗車区間ステップのフォーマット: "A → B → C（△△線・N駅）"
        var lineSegments: [TransitSegment] = []

        // ポリライン座標を路線区間ごとに分割
        let coords = result.polylineCoordinates
        guard coords.count >= 2 else {
            // 座標が不十分な場合は全体を1セグメントとして表示
            lineSegments.append(TransitSegment(
                coordinates: coords,
                mode: .transit,
                label: "\(result.originStation.name) → \(result.destStation.name)",
                color: .green
            ))
            return lineSegments
        }

        // transitSteps から路線情報を抽出してセグメントを構築
        // ride ステップ（instruction に路線名を含む）を探す
        var rideSteps: [(label: String, lineName: String, startCoord: CLLocationCoordinate2D, endCoord: CLLocationCoordinate2D)] = []
        for step in result.transitSteps {
            // ride ステップ: "A → B（路線名・N駅）"
            if step.stepId.contains("ride") {
                let lineName = extractLineName(from: step.instruction)
                rideSteps.append((
                    label: step.instruction,
                    lineName: lineName,
                    startCoord: CLLocationCoordinate2D(
                        latitude: step.startLocation.lat,
                        longitude: step.startLocation.lng
                    ),
                    endCoord: CLLocationCoordinate2D(
                        latitude: step.endLocation.lat,
                        longitude: step.endLocation.lng
                    )
                ))
            }
        }

        if rideSteps.isEmpty {
            // ride ステップがない場合は全体を1セグメント
            lineSegments.append(TransitSegment(
                coordinates: coords,
                mode: .transit,
                label: "\(result.originStation.name) → \(result.destStation.name)",
                color: .green
            ))
            return lineSegments
        }

        if rideSteps.count == 1 {
            // 単一路線の場合
            let line = TokyoTransitData.lines.first { $0.name == rideSteps[0].lineName }
            let color = lineColorToSwiftUI(line?.color)
            lineSegments.append(TransitSegment(
                coordinates: coords,
                mode: .transit,
                label: rideSteps[0].label,
                color: color
            ))
        } else {
            // 複数路線（乗り換えあり）：座標を区間ごとに分割
            for (rideIdx, ride) in rideSteps.enumerated() {
                let line = TokyoTransitData.lines.first { $0.name == ride.lineName }
                let color = lineColorToSwiftUI(line?.color)

                // この区間に該当する座標を抽出
                let segCoords = extractSegmentCoordinates(
                    from: coords,
                    start: ride.startCoord,
                    end: ride.endCoord,
                    isFirst: rideIdx == 0,
                    isLast: rideIdx == rideSteps.count - 1
                )

                lineSegments.append(TransitSegment(
                    coordinates: segCoords,
                    mode: .transit,
                    label: ride.label,
                    color: color
                ))
            }
        }

        return lineSegments
    }

    /// 路線名を instruction 文字列から抽出（例: "A → B（東急田園都市線・3駅）" → "東急田園都市線"）
    private func extractLineName(from instruction: String) -> String {
        // 「（路線名・N駅）」パターンを検索
        if let parenStart = instruction.lastIndex(of: "（"),
           let dotPos = instruction[parenStart...].firstIndex(of: "・") {
            let lineStart = instruction.index(after: parenStart)
            return String(instruction[lineStart..<dotPos])
        }
        // 「から〇〇線に乗車」パターン
        if let karaIdx = instruction.range(of: "から"),
           let niIdx = instruction.range(of: "に乗車") {
            return String(instruction[karaIdx.upperBound..<niIdx.lowerBound])
        }
        return ""
    }

    /// ポリライン座標から、start/end に近い範囲のサブ配列を抽出
    private func extractSegmentCoordinates(
        from allCoords: [CLLocationCoordinate2D],
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        isFirst: Bool,
        isLast: Bool
    ) -> [CLLocationCoordinate2D] {
        // 各座標から start/end に最も近いインデックスを検索
        let startIdx = isFirst ? 0 : nearestCoordIndex(in: allCoords, to: start)
        let endIdx = isLast ? allCoords.count - 1 : nearestCoordIndex(in: allCoords, to: end)

        guard startIdx <= endIdx, startIdx < allCoords.count else {
            return [start, end]
        }

        return Array(allCoords[startIdx...endIdx])
    }

    /// 座標配列の中で target に最も近いインデックスを返す
    private func nearestCoordIndex(
        in coords: [CLLocationCoordinate2D],
        to target: CLLocationCoordinate2D
    ) -> Int {
        var bestIdx = 0
        var bestDist = Double.infinity
        for (i, c) in coords.enumerated() {
            let d = TransitRouteService.haversineDistance(from: c, to: target)
            if d < bestDist {
                bestDist = d
                bestIdx = i
            }
        }
        return bestIdx
    }

    /// 路線の hex カラーを SwiftUI Color に変換
    private func lineColorToSwiftUI(_ hex: String?) -> Color {
        guard let hex = hex, hex.hasPrefix("#"), hex.count == 7 else {
            return .green
        }
        let r = Double(Int(hex.dropFirst(1).prefix(2), radix: 16) ?? 0) / 255
        let g = Double(Int(hex.dropFirst(3).prefix(2), radix: 16) ?? 0) / 255
        let b = Double(Int(hex.dropFirst(5).prefix(2), radix: 16) ?? 0) / 255
        return Color(red: r, green: g, blue: b)
    }

    // MARK: - ローカル路線ルートの RouteResult 構築

    /// TransitRouteResult から RouteResult を構築
    private func buildRouteResult(
        from result: TransitRouteService.TransitRouteResult,
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        routeId: String
    ) -> RouteResult {
        var allSteps: [RouteStep] = []

        // 徒歩区間1のステップ
        if let walkTo = result.walkToStation {
            allSteps.append(RouteStep(
                stepId: "walk_to_station",
                instruction: "\(result.originStation.name)まで徒歩 (\(formatDistance(walkTo.distance)))",
                distanceMeters: walkTo.distance,
                durationSeconds: walkTo.expectedTravelTime,
                startLocation: LatLng(lat: origin.latitude, lng: origin.longitude),
                endLocation: LatLng(
                    lat: result.originStation.coordinate.latitude,
                    lng: result.originStation.coordinate.longitude
                ),
                polyline: "",
                hasStairs: false,
                hasSlope: false,
                slopeGrade: nil,
                surfaceType: .paved
            ))
        }

        // 電車区間のステップ
        allSteps.append(contentsOf: result.transitSteps)

        // 徒歩区間2のステップ
        if let walkFrom = result.walkFromStation {
            allSteps.append(RouteStep(
                stepId: "walk_from_station",
                instruction: "\(result.destStation.name)から目的地まで徒歩 (\(formatDistance(walkFrom.distance)))",
                distanceMeters: walkFrom.distance,
                durationSeconds: walkFrom.expectedTravelTime,
                startLocation: LatLng(
                    lat: result.destStation.coordinate.latitude,
                    lng: result.destStation.coordinate.longitude
                ),
                endLocation: LatLng(lat: destination.latitude, lng: destination.longitude),
                polyline: "",
                hasStairs: false,
                hasSlope: false,
                slopeGrade: nil,
                surfaceType: .paved
            ))
        }

        let score = DirectionsService.calculateAccessibilityScore(
            steps: allSteps, transferCount: result.transferCount
        )
        var warnings = DirectionsService.generateWarnings(steps: allSteps)
        warnings.insert("🚃 \(result.originStation.name) → \(result.destStation.name)", at: 0)

        // ユーザーの移動タイプに応じた警告を追加
        if let rawMobility = UserDefaults.standard.string(forKey: "profile_mobilityType"),
           let mobility = MobilityType(rawValue: rawMobility),
           mobility == .wheelchair || mobility == .stroller {
            warnings.append("⚠️ 駅構内に階段があります。エレベーターをご利用ください")
        }
        warnings.append("ℹ️ 所要時間は目安です")

        return RouteResult(
            routeId: routeId,
            accessibilityScore: score,
            distanceMeters: result.totalDistanceMeters,
            durationMinutes: result.totalDurationMinutes,
            steps: allSteps,
            warnings: warnings,
            nearbySpots: []
        )
    }

    // MARK: - ヘルパー

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1fkm", meters / 1000)
        }
        return "\(Int(meters))m"
    }

    private func convertMKRouteToResult(_ mkRoute: MKRoute, index: Int) -> RouteResult {
        let steps = mkRoute.steps.filter { !$0.instructions.isEmpty }.enumerated().map { stepIdx, mkStep in
            let hasStairs = DirectionsService.detectStairs(in: mkStep.instructions)
            let hasSlope = DirectionsService.detectSlope(in: mkStep.instructions)

            return RouteStep(
                stepId: "mkstep_\(index)_\(stepIdx)",
                instruction: mkStep.instructions,
                distanceMeters: mkStep.distance,
                durationSeconds: mkStep.distance / 1.2,
                startLocation: LatLng(
                    lat: mkStep.polyline.coordinate.latitude,
                    lng: mkStep.polyline.coordinate.longitude
                ),
                endLocation: LatLng(
                    lat: mkStep.polyline.coordinate.latitude,
                    lng: mkStep.polyline.coordinate.longitude
                ),
                polyline: "",
                hasStairs: hasStairs,
                hasSlope: hasSlope,
                slopeGrade: nil,
                surfaceType: .paved
            )
        }

        let score = DirectionsService.calculateAccessibilityScore(steps: steps)
        let warnings = DirectionsService.generateWarnings(steps: steps)

        return RouteResult(
            routeId: "mkroute_\(index)",
            accessibilityScore: score,
            distanceMeters: mkRoute.distance,
            durationMinutes: mkRoute.expectedTravelTime / 60,
            steps: steps,
            warnings: warnings,
            nearbySpots: []
        )
    }


    func selectRoute(_ route: RouteResult) {
        selectedRoute = route
        if let index = routeResults.firstIndex(where: { $0.routeId == route.routeId }) {
            selectedMKRouteIndex = index
        }
    }

    // 電車ルート用モックデータ（溝の口→渋谷）
    static func mockTransitRouteResults() -> [RouteResult] {
        let mizonokuchiLat = 35.6006
        let mizonokuchiLng = 139.6107
        let shibuyaLat = 35.6580
        let shibuyaLng = 139.7016

        let steps = [
            RouteStep(
                stepId: "mock_walk_to",
                instruction: "溝の口駅まで徒歩 5分",
                distanceMeters: 400,
                durationSeconds: 300,
                startLocation: LatLng(lat: mizonokuchiLat - 0.002, lng: mizonokuchiLng - 0.001),
                endLocation: LatLng(lat: mizonokuchiLat, lng: mizonokuchiLng),
                polyline: "",
                hasStairs: false,
                hasSlope: false,
                slopeGrade: nil,
                surfaceType: .paved
            ),
            RouteStep(
                stepId: "mock_board",
                instruction: "東急田園都市線 渋谷方面に乗車",
                distanceMeters: 0,
                durationSeconds: 60,
                startLocation: LatLng(lat: mizonokuchiLat, lng: mizonokuchiLng),
                endLocation: LatLng(lat: mizonokuchiLat, lng: mizonokuchiLng),
                polyline: "",
                hasStairs: true,
                hasSlope: false,
                slopeGrade: nil,
                surfaceType: .paved
            ),
            RouteStep(
                stepId: "mock_ride",
                instruction: "溝の口 → 渋谷（東急田園都市線）",
                distanceMeters: 12000,
                durationSeconds: 1080,
                startLocation: LatLng(lat: mizonokuchiLat, lng: mizonokuchiLng),
                endLocation: LatLng(lat: shibuyaLat, lng: shibuyaLng),
                polyline: "",
                hasStairs: false,
                hasSlope: false,
                slopeGrade: nil,
                surfaceType: .paved
            ),
            RouteStep(
                stepId: "mock_alight",
                instruction: "渋谷駅で下車",
                distanceMeters: 0,
                durationSeconds: 60,
                startLocation: LatLng(lat: shibuyaLat, lng: shibuyaLng),
                endLocation: LatLng(lat: shibuyaLat, lng: shibuyaLng),
                polyline: "",
                hasStairs: true,
                hasSlope: false,
                slopeGrade: nil,
                surfaceType: .paved
            ),
            RouteStep(
                stepId: "mock_walk_from",
                instruction: "目的地まで徒歩 3分",
                distanceMeters: 250,
                durationSeconds: 180,
                startLocation: LatLng(lat: shibuyaLat, lng: shibuyaLng),
                endLocation: LatLng(lat: shibuyaLat + 0.001, lng: shibuyaLng + 0.002),
                polyline: "",
                hasStairs: false,
                hasSlope: false,
                slopeGrade: nil,
                surfaceType: .paved
            )
        ]

        var warnings: [String] = [
            "🚃 溝の口駅 → 渋谷駅",
            "ℹ️ 所要時間は目安です"
        ]

        // ユーザーの移動タイプに応じた警告
        if let rawMobility = UserDefaults.standard.string(forKey: "profile_mobilityType"),
           let mobility = MobilityType(rawValue: rawMobility),
           mobility == .wheelchair || mobility == .stroller {
            warnings.insert("⚠️ 駅構内に階段があります。エレベーターをご利用ください", at: 1)
        }

        return [
            RouteResult(
                routeId: "transit_mock_0",
                accessibilityScore: 75,
                distanceMeters: 12650,
                durationMinutes: 28,
                steps: steps,
                warnings: warnings,
                nearbySpots: []
            )
        ]
    }

    // モックデータ
    static func mockRouteResults() -> [RouteResult] {
        [
            RouteResult(
                routeId: "route_1",
                accessibilityScore: 92,
                distanceMeters: 850,
                durationMinutes: 12,
                steps: [
                    RouteStep(
                        stepId: "step_1_1",
                        instruction: "北口を出て右に進む",
                        distanceMeters: 200,
                        durationSeconds: 180,
                        startLocation: LatLng(lat: 35.6812, lng: 139.7671),
                        endLocation: LatLng(lat: 35.6820, lng: 139.7675),
                        polyline: "o~wxEkgatY{@Sg@Sg@SSS",
                        hasStairs: false,
                        hasSlope: false,
                        slopeGrade: nil,
                        surfaceType: .paved
                    )
                ],
                warnings: [],
                nearbySpots: []
            )
        ]
    }
}

// 電車ルートの区間情報
struct TransitSegment: Identifiable {
    let id = UUID()
    var mkRoute: MKRoute?           // 徒歩区間の場合
    var coordinates: [CLLocationCoordinate2D]? // 電車区間の場合
    let mode: TransportMode
    let label: String
    let color: Color
}

// TransportMode → MKDirectionsTransportType 変換
extension TransportMode {
    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .walking: return .walking
        case .transit: return .transit
        case .driving: return .automobile
        case .bicycling: return .walking
        }
    }
}
