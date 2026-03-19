import Foundation
@preconcurrency import MapKit

// 電車ルート検索サービス
// TokyoTransitData を使ったグラフベースのルート探索
enum TransitRouteService {

    // 電車ルートの検索結果
    struct TransitRouteResult {
        let originStation: StationInfo
        let destStation: StationInfo
        let walkToStation: MKRoute?     // 出発地→出発駅の徒歩ルート
        let walkFromStation: MKRoute?   // 到着駅→目的地の徒歩ルート
        let transitSteps: [RouteStep]   // 電車区間のステップ
        let totalDurationMinutes: Double
        let totalDistanceMeters: Double
        let polylineCoordinates: [CLLocationCoordinate2D] // 電車区間のポリライン座標
        let transferCount: Int          // 乗り換え回数
    }

    struct StationInfo {
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    // MARK: - BFS用の内部型

    /// BFS探索ノード: 駅ID + 現在乗車中の路線ID
    private struct GraphNode: Hashable {
        let stationId: String
        let lineId: String // 現在乗車中の路線（"" = 初期状態）
    }

    /// BFS経路の1ステップ
    private struct PathSegment {
        let stationId: String
        let lineId: String
        let isTransfer: Bool
    }

    // MARK: - 検索パラメータ

    /// 駅検索の最大距離（メートル）
    private static let maxStationSearchRadius: Double = 2000

    /// 乗り換えペナルティ（分）
    private static let transferPenaltyMinutes: Double = 3.0

    /// 駅ごとの乗り換え時間を返す（分）
    private static func transferTime(at stationId: String, from lineId1: String, to lineId2: String) -> Double {
        // 大規模駅（乗り換えに時間がかかる）
        let complexStations: [String: Double] = [
            "shinjuku": 5.0,      // 新宿は広大で乗り換えが複雑
            "tokyo": 5.0,         // 東京駅も同様
            "ikebukuro": 4.0,     // 池袋
            "shibuya": 4.0,       // 渋谷（ただし直通運転は0）
            "otemachi": 4.0,      // 大手町（複数路線が離れている）
            "yokohama": 4.0,      // 横浜
        ]

        // 同一ホーム乗り換え（簡単）
        let easyTransfers: Set<String> = [
            "kudanshita",   // 九段下（半蔵門線↔都営新宿線）
            "iidabashi",    // 飯田橋
            "kasuga",       // 春日
        ]

        if easyTransfers.contains(stationId) {
            return 2.0
        }

        if let complex = complexStations[stationId] {
            return complex
        }

        return transferPenaltyMinutes // デフォルト
    }

    // MARK: - 公開API

    /// 電車ルートを検索
    static func searchTransitRoute(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D
    ) async throws -> TransitRouteResult {
        // 1. 出発地と目的地の最寄駅を検索
        let originCandidates = TokyoTransitData.nearestStations(
            to: origin, maxDistance: maxStationSearchRadius, limit: 3
        )
        let destCandidates = TokyoTransitData.nearestStations(
            to: destination, maxDistance: maxStationSearchRadius, limit: 3
        )

        guard !originCandidates.isEmpty else {
            throw TransitError.noStationFound(detail: "出発地付近に駅が見つかりません")
        }
        guard !destCandidates.isEmpty else {
            throw TransitError.noStationFound(detail: "目的地付近に駅が見つかりません")
        }

        // 2. 全候補ペアに対しBFSでルートを探索し、最短を選択
        var bestResult: (
            path: [PathSegment],
            totalMinutes: Double,
            originStation: TransitStation,
            destStation: TransitStation
        )?

        for oStation in originCandidates {
            for dStation in destCandidates {
                // 同じ駅ペアはスキップ
                if oStation.id == dStation.id { continue }

                if let path = findShortestPath(from: oStation.id, to: dStation.id) {
                    let totalMinutes = calculatePathDuration(path)
                    // 徒歩時間を加算（80m/分 = 1.33m/秒）
                    let walkToMeters = haversineDistance(
                        from: origin, to: oStation.coordinate
                    )
                    let walkFromMeters = haversineDistance(
                        from: dStation.coordinate, to: destination
                    )
                    let walkToMin = walkToMeters / 80.0 // 分
                    let walkFromMin = walkFromMeters / 80.0 // 分
                    let grandTotal = walkToMin + totalMinutes + walkFromMin

                    if bestResult == nil || grandTotal < (bestResult!.totalMinutes) {
                        bestResult = (path, grandTotal, oStation, dStation)
                    }
                }
            }
        }

        guard let best = bestResult else {
            throw TransitError.noRouteFound
        }

        let oStation = best.originStation
        let dStation = best.destStation
        let path = best.path

        // 3. 徒歩ルートを並行取得
        async let walkToResult = getWalkingRoute(
            from: origin, to: oStation.coordinate
        )
        async let walkFromResult = getWalkingRoute(
            from: dStation.coordinate, to: destination
        )

        let walkToStation: MKRoute?
        do {
            walkToStation = try await walkToResult
        } catch {
            walkToStation = nil
        }

        let walkFromStation: MKRoute?
        do {
            walkFromStation = try await walkFromResult
        } catch {
            walkFromStation = nil
        }

        // 4. 電車区間のステップを構築
        let transitSteps = buildTransitSteps(from: path)

        // 5. ポリライン座標を構築（駅間を道路に沿って補間）
        let polylineCoords = await buildDetailedPolyline(from: path)

        // 6. 乗り換え回数
        let transferCount = path.filter { $0.isTransfer }.count

        // 7. 合計時間・距離を計算
        let walkToDuration = (walkToStation?.expectedTravelTime ?? 300) / 60
        let walkFromDuration = (walkFromStation?.expectedTravelTime ?? 300) / 60
        let trainDurationMin = calculatePathDuration(path)

        let totalDuration = walkToDuration + trainDurationMin + walkFromDuration

        var trainDistance: Double = 0
        for i in 0 ..< (polylineCoords.count - 1) {
            trainDistance += haversineDistance(
                from: polylineCoords[i], to: polylineCoords[i + 1]
            )
        }
        let totalDistance = (walkToStation?.distance ?? 300)
            + trainDistance + (walkFromStation?.distance ?? 300)

        return TransitRouteResult(
            originStation: StationInfo(
                name: oStation.name, coordinate: oStation.coordinate
            ),
            destStation: StationInfo(
                name: dStation.name, coordinate: dStation.coordinate
            ),
            walkToStation: walkToStation,
            walkFromStation: walkFromStation,
            transitSteps: transitSteps,
            totalDurationMinutes: totalDuration,
            totalDistanceMeters: totalDistance,
            polylineCoordinates: polylineCoords,
            transferCount: transferCount
        )
    }

    // MARK: - BFS経路探索

    /// BFSで出発駅から到着駅までの最短経路を探索
    /// 同一路線上の隣接駅間を1エッジとし、乗り換え（同じ駅の別路線）もエッジとする
    private static func findShortestPath(
        from originId: String,
        to destId: String
    ) -> [PathSegment]? {
        // 隣接グラフを構築
        // キー: GraphNode、値: [(隣接GraphNode, 所要時間(分), 乗り換えか)]
        typealias Edge = (node: GraphNode, minutes: Double, isTransfer: Bool)
        var adjacency: [GraphNode: [Edge]] = [:]

        for line in TokyoTransitData.lines {
            let ids = line.stationIds
            for i in 0 ..< ids.count {
                let node = GraphNode(stationId: ids[i], lineId: line.id)
                if adjacency[node] == nil { adjacency[node] = [] }

                // 隣接駅（前後）
                if i > 0 {
                    let prev = GraphNode(stationId: ids[i - 1], lineId: line.id)
                    adjacency[node]?.append((prev, line.avgIntervalMinutes, false))
                }
                if i < ids.count - 1 {
                    let next = GraphNode(stationId: ids[i + 1], lineId: line.id)
                    adjacency[node]?.append((next, line.avgIntervalMinutes, false))
                }

                // ループ路線の場合、最初と最後を接続
                if line.isLoop {
                    if i == 0 {
                        let last = GraphNode(
                            stationId: ids[ids.count - 1], lineId: line.id
                        )
                        adjacency[node]?.append((last, line.avgIntervalMinutes, false))
                    }
                    if i == ids.count - 1 {
                        let first = GraphNode(stationId: ids[0], lineId: line.id)
                        adjacency[node]?.append((first, line.avgIntervalMinutes, false))
                    }
                }

                // 同じ駅の別路線への乗り換えエッジ（直通運転の場合はペナルティなし）
                let stationLines = TokyoTransitData.lines(forStation: ids[i])
                for otherLine in stationLines where otherLine.id != line.id {
                    let transferNode = GraphNode(
                        stationId: ids[i], lineId: otherLine.id
                    )
                    let isThroughSvc = TokyoTransitData.isThroughService(
                        lineId1: line.id, lineId2: otherLine.id, atStation: ids[i]
                    )
                    let penalty = isThroughSvc
                        ? TokyoTransitData.throughServicePenalty(lineId1: line.id, lineId2: otherLine.id, atStation: ids[i])
                        : transferTime(at: ids[i], from: line.id, to: otherLine.id)
                    adjacency[node]?.append(
                        (transferNode, penalty, !isThroughSvc)
                    )
                }
            }
        }

        // ダイクストラ法で最短時間経路を探索
        struct State: Comparable {
            let node: GraphNode
            let cost: Double
            static func < (lhs: State, rhs: State) -> Bool {
                lhs.cost < rhs.cost
            }
        }

        // 始点: originIdが属する全路線のノードを初期状態に
        var dist: [GraphNode: Double] = [:]
        var prev: [GraphNode: (GraphNode, Bool)] = [:] // 親ノード + 乗り換えフラグ
        var queue: [State] = []

        let originLines = TokyoTransitData.lines(forStation: originId)
        for line in originLines {
            let startNode = GraphNode(stationId: originId, lineId: line.id)
            dist[startNode] = 0
            queue.append(State(node: startNode, cost: 0))
        }

        // 目的駅ノード候補
        let destLines = TokyoTransitData.lines(forStation: destId)
        let destNodes = Set(destLines.map {
            GraphNode(stationId: destId, lineId: $0.id)
        })

        while !queue.isEmpty {
            // Find minimum cost element instead of sorting entire array
            guard let minIndex = queue.indices.min(by: { queue[$0].cost < queue[$1].cost }) else { break }
            let current = queue.remove(at: minIndex)

            // 既により良い経路が見つかっている場合はスキップ
            if let known = dist[current.node], current.cost > known {
                continue
            }

            // 目的地到達
            if destNodes.contains(current.node) {
                // 経路を復元
                return reconstructPath(
                    endNode: current.node, prev: prev, originId: originId
                )
            }

            // 隣接ノードを探索
            guard let edges = adjacency[current.node] else { continue }
            for edge in edges {
                let newCost = current.cost + edge.minutes
                let knownCost = dist[edge.node] ?? Double.infinity
                if newCost < knownCost {
                    dist[edge.node] = newCost
                    prev[edge.node] = (current.node, edge.isTransfer)
                    queue.append(State(node: edge.node, cost: newCost))
                }
            }
        }

        return nil // 到達不能
    }

    /// ダイクストラの結果から経路を復元
    private static func reconstructPath(
        endNode: GraphNode,
        prev: [GraphNode: (GraphNode, Bool)],
        originId: String
    ) -> [PathSegment] {
        var path: [PathSegment] = []
        var current = endNode

        // 終点を追加
        path.append(PathSegment(
            stationId: current.stationId,
            lineId: current.lineId,
            isTransfer: false
        ))

        while let (parent, isTransfer) = prev[current] {
            // 乗り換えの場合は同じ駅なのでスキップ（フラグで記録）
            if isTransfer {
                // 乗り換えマーカーを追加
                path.append(PathSegment(
                    stationId: parent.stationId,
                    lineId: parent.lineId,
                    isTransfer: true
                ))
            } else {
                path.append(PathSegment(
                    stationId: parent.stationId,
                    lineId: parent.lineId,
                    isTransfer: false
                ))
            }
            current = parent
        }

        path.reverse()
        return path
    }

    /// 経路の所要時間を計算（分）
    private static func calculatePathDuration(_ path: [PathSegment]) -> Double {
        var total: Double = 0
        for i in 0 ..< (path.count - 1) {
            if path[i + 1].isTransfer {
                total += transferTime(at: path[i].stationId, from: path[i].lineId, to: path[i + 1].lineId)
            } else if path[i].stationId == path[i + 1].stationId {
                // 同じ駅での路線変更（直通運転）：ペナルティなし
                total += 0
            } else {
                // 同一路線上の移動
                if let line = TokyoTransitData.lines.first(where: {
                    $0.id == path[i].lineId
                }) {
                    total += line.avgIntervalMinutes
                } else {
                    total += 2.0 // デフォルト
                }
            }
        }
        return total
    }

    // MARK: - ステップ構築

    /// BFS経路からRouteStepリストを構築
    private static func buildTransitSteps(from path: [PathSegment]) -> [RouteStep] {
        guard path.count >= 2 else { return [] }

        var steps: [RouteStep] = []

        // 経路を路線区間ごとにグループ化
        var segments: [(lineId: String, stationIds: [String], throughServiceLineIds: [String])] = []
        var currentLineId = path[0].lineId
        var currentStationIds: [String] = [path[0].stationId]
        var currentThroughServiceLineIds: [String] = [path[0].lineId]

        for i in 1 ..< path.count {
            if path[i].isTransfer {
                // 乗り換え：乗り換え駅を現在の区間の最後に追加して確定
                currentStationIds.append(path[i].stationId)
                segments.append((currentLineId, currentStationIds, currentThroughServiceLineIds))
                // 乗り換え先の路線IDは次のエントリから取得
                let nextLineId = (i + 1 < path.count) ? path[i + 1].lineId : path[i].lineId
                currentLineId = nextLineId
                currentStationIds = [path[i].stationId]
                currentThroughServiceLineIds = [nextLineId]
            } else if path[i].lineId != currentLineId {
                // 路線変更だが直通運転の場合は区間を分けない
                let lastStationId = currentStationIds.last ?? ""
                if TokyoTransitData.isThroughService(
                    lineId1: currentLineId, lineId2: path[i].lineId, atStation: lastStationId
                ) {
                    // 直通運転：区間を継続し路線IDだけ更新（駅は同一なので追加不要）
                    currentLineId = path[i].lineId
                    if !currentThroughServiceLineIds.contains(path[i].lineId) {
                        currentThroughServiceLineIds.append(path[i].lineId)
                    }
                } else {
                    // 通常の路線変更
                    segments.append((currentLineId, currentStationIds, currentThroughServiceLineIds))
                    currentLineId = path[i].lineId
                    currentStationIds = [path[i].stationId]
                    currentThroughServiceLineIds = [path[i].lineId]
                }
            } else {
                // 乗り換え直後の重複駅を防止
                if path[i].stationId != currentStationIds.last {
                    currentStationIds.append(path[i].stationId)
                }
            }
        }
        segments.append((currentLineId, currentStationIds, currentThroughServiceLineIds))

        // 各区間のステップを生成
        for (segIndex, segment) in segments.enumerated() {
            guard segment.stationIds.count >= 2 else { continue }

            let line = TokyoTransitData.lines.first { $0.id == segment.lineId }
            let lineName: String
            if segment.throughServiceLineIds.count > 1 {
                // 直通運転：複数路線名を結合して表示（例: "東急田園都市線(半蔵門線直通)"）
                let firstLine = TokyoTransitData.lines.first { $0.id == segment.throughServiceLineIds[0] }
                let secondLine = TokyoTransitData.lines.first { $0.id == segment.throughServiceLineIds[1] }
                let firstName = firstLine?.name ?? "電車"
                let secondName = secondLine?.name ?? "電車"
                lineName = "\(firstName)(\(secondName)直通)"
            } else {
                lineName = line?.name ?? "電車"
            }

            // 方面（進行方向の終点駅名）を取得
            let lastStationId = segment.stationIds.last!
            let directionStationName: String
            let lastLineId = segment.throughServiceLineIds.last ?? segment.lineId
            if let activeLine = TokyoTransitData.lines.first(where: { $0.id == lastLineId }),
               let lastIdx = activeLine.stationIds.firstIndex(of: lastStationId) {
                // 区間内の別の駅から進行方向を判定
                var refIdx: Int?
                for stId in segment.stationIds.dropLast().reversed() {
                    if let idx = activeLine.stationIds.firstIndex(of: stId) {
                        refIdx = idx
                        break
                    }
                }
                let goingForward = refIdx.map { lastIdx > $0 } ?? (lastIdx > 0)
                let terminalId = goingForward ? activeLine.stationIds.last! : activeLine.stationIds.first!
                directionStationName = TokyoTransitData.station(byId: terminalId)?.name ?? ""
            } else {
                directionStationName = TokyoTransitData.station(byId: lastStationId)?.name ?? ""
            }
            let directionLabel = "\(lineName)で\(directionStationName)方面"

            let firstStation = TokyoTransitData.station(byId: segment.stationIds[0])
            let lastStation = TokyoTransitData.station(byId: lastStationId)

            // 乗車ステップ
            if let first = firstStation {
                steps.append(RouteStep(
                    stepId: "transit_board_\(segIndex)",
                    instruction: "\(first.name)から\(directionLabel)に乗車",
                    distanceMeters: 0,
                    durationSeconds: 60,
                    startLocation: LatLng(
                        lat: first.coordinate.latitude,
                        lng: first.coordinate.longitude
                    ),
                    endLocation: LatLng(
                        lat: first.coordinate.latitude,
                        lng: first.coordinate.longitude
                    ),
                    polyline: "",
                    hasStairs: false,
                    hasSlope: false,
                    slopeGrade: nil,
                    surfaceType: .paved
                ))
            }

            // 各駅間の乗車ステップ
            let stopsCount = segment.stationIds.count - 1
            // 直通運転で路線が変わる場合、各区間の正しいavgIntervalMinutesを使用
            var durationMin: Double = 0
            for i in 0 ..< stopsCount {
                let fromId = segment.stationIds[i]
                let toId = segment.stationIds[i + 1]
                var intervalMin: Double = 2.0
                for lineId in segment.throughServiceLineIds {
                    if let l = TokyoTransitData.lines.first(where: { $0.id == lineId }),
                       l.stationIds.contains(fromId), l.stationIds.contains(toId) {
                        intervalMin = l.avgIntervalMinutes
                        break
                    }
                }
                durationMin += intervalMin
            }

            // 区間の総距離を計算
            var segmentDistance: Double = 0
            for i in 0 ..< stopsCount {
                if let fromSt = TokyoTransitData.station(byId: segment.stationIds[i]),
                   let toSt = TokyoTransitData.station(byId: segment.stationIds[i + 1])
                {
                    segmentDistance += haversineDistance(
                        from: fromSt.coordinate, to: toSt.coordinate
                    )
                }
            }

            // 通過駅名リスト
            let stationNames = segment.stationIds.compactMap {
                TokyoTransitData.station(byId: $0)?.name
            }
            let routeDescription = stationNames.joined(separator: " → ")

            if let first = firstStation, let last = lastStation {
                steps.append(RouteStep(
                    stepId: "transit_ride_\(segIndex)",
                    instruction: "\(routeDescription)（\(lineName)・\(stopsCount)駅）",
                    distanceMeters: segmentDistance,
                    durationSeconds: durationMin * 60,
                    startLocation: LatLng(
                        lat: first.coordinate.latitude,
                        lng: first.coordinate.longitude
                    ),
                    endLocation: LatLng(
                        lat: last.coordinate.latitude,
                        lng: last.coordinate.longitude
                    ),
                    polyline: "",
                    hasStairs: false,
                    hasSlope: false,
                    slopeGrade: nil,
                    surfaceType: .paved
                ))
            }

            // 乗り換えステップ（最後の区間以外）
            if segIndex < segments.count - 1, let last = lastStation {
                let nextSegment = segments[segIndex + 1]
                let nextLine = TokyoTransitData.lines.first {
                    $0.id == nextSegment.lineId
                }
                let nextLineName = nextLine?.name ?? "電車"

                let transferStationId = segment.stationIds.last ?? ""
                let transferDuration = transferTime(at: transferStationId, from: segment.lineId, to: nextSegment.lineId)
                steps.append(RouteStep(
                    stepId: "transit_transfer_\(segIndex)",
                    instruction: "\(last.name)で\(nextLineName)に乗り換え",
                    distanceMeters: 0,
                    durationSeconds: transferDuration * 60,
                    startLocation: LatLng(
                        lat: last.coordinate.latitude,
                        lng: last.coordinate.longitude
                    ),
                    endLocation: LatLng(
                        lat: last.coordinate.latitude,
                        lng: last.coordinate.longitude
                    ),
                    polyline: "",
                    hasStairs: true,
                    hasSlope: false,
                    slopeGrade: nil,
                    surfaceType: .paved
                ))
            }
        }

        // 下車ステップ
        if let lastStationId = path.last?.stationId,
           let lastStation = TokyoTransitData.station(byId: lastStationId)
        {
            steps.append(RouteStep(
                stepId: "transit_alight",
                instruction: "\(lastStation.name)で下車",
                distanceMeters: 0,
                durationSeconds: 60,
                startLocation: LatLng(
                    lat: lastStation.coordinate.latitude,
                    lng: lastStation.coordinate.longitude
                ),
                endLocation: LatLng(
                    lat: lastStation.coordinate.latitude,
                    lng: lastStation.coordinate.longitude
                ),
                polyline: "",
                hasStairs: segments.count > 1,
                hasSlope: false,
                slopeGrade: nil,
                surfaceType: .paved
            ))
        }

        return steps
    }

    /// 経路からポリライン座標を構築
    private static func buildPolylineCoordinates(
        from path: [PathSegment]
    ) -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        var lastId: String?

        for segment in path {
            if segment.stationId == lastId { continue }
            if let station = TokyoTransitData.station(byId: segment.stationId) {
                coords.append(station.coordinate)
                lastId = segment.stationId
            }
        }
        return coords
    }

    /// 駅間を道路ポリラインで補間して滑らかなルートを構築
    /// MKDirectionsの同時リクエスト数を制限してメモリ超過を防止
    private static let maxConcurrentPolylineRequests = 3

    private static func buildDetailedPolyline(
        from path: [PathSegment]
    ) async -> [CLLocationCoordinate2D] {
        // まず駅座標リストを取得
        let stationCoords = buildPolylineCoordinates(from: path)
        guard stationCoords.count >= 2 else { return stationCoords }

        let segmentCount = stationCoords.count - 1

        // 極端に長いルートのみ直線にフォールバック
        if segmentCount > 25 {
            return stationCoords
        }

        // バッチ単位で並列取得（同時リクエスト数を制限）
        var segmentPolylines: [Int: [CLLocationCoordinate2D]] = [:]

        for batchStart in stride(from: 0, to: segmentCount, by: maxConcurrentPolylineRequests) {
            let batchEnd = min(batchStart + maxConcurrentPolylineRequests, segmentCount)

            let batchResults: [Int: [CLLocationCoordinate2D]] = await withTaskGroup(
                of: (Int, [CLLocationCoordinate2D]?).self
            ) { group in
                for i in batchStart ..< batchEnd {
                    let from = stationCoords[i]
                    let to = stationCoords[i + 1]
                    group.addTask {
                        let coords = await getRoutPolyline(from: from, to: to)
                        return (i, coords)
                    }
                }

                var results: [Int: [CLLocationCoordinate2D]] = [:]
                for await (index, coords) in group {
                    if let coords {
                        results[index] = coords
                    }
                }
                return results
            }

            segmentPolylines.merge(batchResults) { _, new in new }
        }

        // 順序通りにポリラインを結合
        var detailedCoords: [CLLocationCoordinate2D] = []
        for i in 0 ..< segmentCount {
            if let segmentCoords = segmentPolylines[i] {
                if detailedCoords.isEmpty {
                    detailedCoords.append(contentsOf: segmentCoords)
                } else {
                    detailedCoords.append(contentsOf: segmentCoords.dropFirst())
                }
            } else {
                // フォールバック: 直線で接続
                if detailedCoords.isEmpty {
                    detailedCoords.append(stationCoords[i])
                }
                detailedCoords.append(stationCoords[i + 1])
            }
        }

        return detailedCoords
    }

    /// 2点間の道路に沿ったポリラインを取得（電車の線路近似）
    private static func getRoutPolyline(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async -> [CLLocationCoordinate2D]? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile // 道路に沿ったルート

        let directions = MKDirections(request: request)

        do {
            // MKDirections.Responseはnon-Sendableのためコールバック版を使用
            let coords: [CLLocationCoordinate2D] = try await withCheckedThrowingContinuation { continuation in
                directions.calculate { response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let route = response?.routes.first else {
                        continuation.resume(returning: [])
                        return
                    }
                    let points = route.polyline.points()
                    var result: [CLLocationCoordinate2D] = []
                    for j in 0..<route.polyline.pointCount {
                        result.append(points[j].coordinate)
                    }
                    continuation.resume(returning: result)
                }
            }
            return coords.isEmpty ? nil : coords
        } catch {
            return nil
        }
    }

    // MARK: - 徒歩ルート取得

    /// 2点間の徒歩ルートを取得
    private static func getWalkingRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            placemark: MKPlacemark(coordinate: from)
        )
        request.destination = MKMapItem(
            placemark: MKPlacemark(coordinate: to)
        )
        request.transportType = .walking

        let directions = MKDirections(request: request)
        // MKRoute はnon-SendableのためUncheckedSendableBoxで包んで渡す
        let box: UncheckedSendableBox<MKRoute> = try await withCheckedThrowingContinuation { continuation in
            directions.calculate { response, error in
                if let error = error {
                    continuation.resume(throwing: TransitError.walkingRouteUnavailable(
                        detail: "徒歩ルートの取得に失敗しました: \(error.localizedDescription)"
                    ))
                    return
                }
                guard let route = response?.routes.first else {
                    continuation.resume(throwing: TransitError.noRouteFound)
                    return
                }
                continuation.resume(returning: UncheckedSendableBox(value: route))
            }
        }
        return box.value
    }

    // MARK: - 距離計算

    /// Haversine距離計算（メートル）
    static func haversineDistance(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> Double {
        let earthRadius = 6371000.0
        let dLat = (to.latitude - from.latitude) * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
            cos(from.latitude * .pi / 180) * cos(to.latitude * .pi / 180) *
            sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }
}

// 電車ルート検索エラー
enum TransitError: LocalizedError {
    case noRouteFound
    case noStationFound(detail: String)
    case walkingRouteUnavailable(detail: String)

    var errorDescription: String? {
        switch self {
        case .noRouteFound:
            return "ルートが見つかりません"
        case .noStationFound(let detail):
            return "最寄り駅が見つかりません: \(detail)"
        case .walkingRouteUnavailable(let detail):
            return "徒歩ルートを取得できません: \(detail)"
        }
    }
}
