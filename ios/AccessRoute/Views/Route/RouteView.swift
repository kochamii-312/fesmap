import SwiftUI
@preconcurrency import MapKit

// ルート検索結果画面（マップ + カード表示）
struct RouteView: View {
    @StateObject private var viewModel = RouteViewModel()
    @StateObject private var locationManager = LocationManager()
    @State private var detailRoute: RouteResult?
    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
            latitudinalMeters: 2000,
            longitudinalMeters: 2000
        )
    )
    var initialSearchText: String = ""
    var initialDestCoord: CLLocationCoordinate2D? = nil

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 地図（全画面背景）
                routeMapView

                // 下部オーバーレイ
                VStack(spacing: 0) {
                    // 入力エリア
                    routeInputSection
                    transportModeSelector

                    // 検索結果
                    if viewModel.isSearching {
                        HStack {
                            ProgressView()
                            Text("ルートを検索中...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                    } else if !viewModel.routeResults.isEmpty {
                        routeResultsCarousel
                    }

                    // エラーメッセージ
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                            .padding(.bottom, 4)
                            .background(Color(.systemBackground))
                    }
                }
            }
            .navigationTitle("ルート")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $detailRoute) { route in
                NavigationStack {
                    RouteDetailView(route: route)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("閉じる") {
                                    detailRoute = nil
                                }
                            }
                        }
                }
            }
            .onAppear {
                locationManager.startUpdating()
                if viewModel.destinationText.isEmpty && !initialSearchText.isEmpty {
                    viewModel.destinationText = initialSearchText
                    viewModel.presetDestCoord = initialDestCoord
                    Task { await viewModel.searchRouteByName() }
                }
            }
            .onDisappear {
                locationManager.stopUpdating()
            }
            .onChange(of: viewModel.selectedRoute?.routeId) { _, _ in
                fitMapToSelectedRoute()
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - 地図（ルート表示）

    private var routeMapView: some View {
        Map(position: $mapPosition) {
            UserAnnotation()
            mkRoutePolylines
            transitRoutePolylines
            fallbackPolyline
            routeMarkers
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
        }
        .ignoresSafeArea(edges: .top)
    }

    // MKRoute のポリライン（徒歩/車モード）
    @MapContentBuilder
    private var mkRoutePolylines: some MapContent {
        ForEach(Array(viewModel.mkRoutes.enumerated()), id: \.offset) { index, mkRoute in
            let isSelected = index == viewModel.selectedMKRouteIndex
            MapPolyline(mkRoute.polyline)
                .stroke(
                    isSelected ? viewModel.selectedMode.color : .gray.opacity(0.4),
                    lineWidth: isSelected ? 6 : 3
                )
        }
    }

    // 電車ルートの区間ポリライン
    @MapContentBuilder
    private var transitRoutePolylines: some MapContent {
        ForEach(viewModel.transitSegments) { segment in
            if let mkRoute = segment.mkRoute {
                // 徒歩区間（MKRouteのポリライン）
                MapPolyline(mkRoute.polyline)
                    .stroke(segment.color, style: StrokeStyle(lineWidth: 4, dash: [8, 6]))
            }
            if let coords = segment.coordinates, coords.count >= 2 {
                // 電車区間（直線）
                MapPolyline(coordinates: coords)
                    .stroke(segment.color, lineWidth: 6)
            }
        }

        // 電車ルートの駅マーカー
        ForEach(viewModel.transitSegments) { segment in
            if segment.mode == .transit, let coords = segment.coordinates {
                // 出発駅（青い丸）
                if let first = coords.first {
                    Annotation(segment.label, coordinate: first) {
                        ZStack {
                            Circle().fill(.white).frame(width: 24, height: 24)
                            Circle().fill(.blue).frame(width: 18, height: 18)
                            Image(systemName: "tram.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.white)
                        }
                    }
                }
                // 到着駅（オレンジの丸）- 駅名をラベルに表示
                if let last = coords.last, coords.count > 1 {
                    Annotation(destinationStationName(for: segment), coordinate: last) {
                        ZStack {
                            Circle().fill(.white).frame(width: 24, height: 24)
                            Circle().fill(.orange).frame(width: 18, height: 18)
                            Image(systemName: "tram.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
    }

    // フォールバック用ポリライン（モックデータ）
    @MapContentBuilder
    private var fallbackPolyline: some MapContent {
        if viewModel.mkRoutes.isEmpty && viewModel.transitSegments.isEmpty,
           let route = viewModel.selectedRoute {
            let coordinates = routeCoordinates(for: route)
            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(viewModel.selectedMode.color, lineWidth: 5)
            }
        }
    }

    // 出発地・目的地マーカー
    @MapContentBuilder
    private var routeMarkers: some MapContent {
        if let route = viewModel.selectedRoute, let firstStep = route.steps.first {
            Annotation("出発地", coordinate: CLLocationCoordinate2D(
                latitude: firstStep.startLocation.lat,
                longitude: firstStep.startLocation.lng
            )) {
                ZStack {
                    Circle().fill(.white).frame(width: 20, height: 20)
                    Circle().fill(.green).frame(width: 14, height: 14)
                }
            }
        }
        if let route = viewModel.selectedRoute, let lastStep = route.steps.last {
            Marker("目的地", coordinate: CLLocationCoordinate2D(
                latitude: lastStep.endLocation.lat,
                longitude: lastStep.endLocation.lng
            ))
            .tint(.red)
        }

        // 目的地周辺のおすすめスポット（好みベース）
        ForEach(viewModel.destinationSpots) { spot in
            Annotation(spot.name, coordinate: CLLocationCoordinate2D(
                latitude: spot.location.lat,
                longitude: spot.location.lng
            )) {
                ZStack {
                    Circle()
                        .fill(spot.category.markerColor)
                        .frame(width: 26, height: 26)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    Image(systemName: spot.category.iconName)
                        .font(.system(size: 11))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
            }
        }
    }

    // 選択中のルートにマップをフィット
    private func fitMapToSelectedRoute() {
        // MKRoute がある場合はその boundingMapRect を使う
        if viewModel.selectedMKRouteIndex < viewModel.mkRoutes.count {
            let mkRoute = viewModel.mkRoutes[viewModel.selectedMKRouteIndex]
            let rect = mkRoute.polyline.boundingMapRect
            let padded = rect.insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.3)
            withAnimation(.easeInOut(duration: 0.5)) {
                mapPosition = .rect(padded)
            }
            return
        }

        // 電車ルートの場合: 全区間を含むバウンディングボックス
        if !viewModel.transitSegments.isEmpty {
            var allCoords: [CLLocationCoordinate2D] = []
            for segment in viewModel.transitSegments {
                if let coords = segment.coordinates {
                    allCoords.append(contentsOf: coords)
                }
                if let mkRoute = segment.mkRoute {
                    let points = mkRoute.polyline.points()
                    for i in 0..<mkRoute.polyline.pointCount {
                        allCoords.append(points[i].coordinate)
                    }
                }
            }
            if !allCoords.isEmpty {
                fitMapToCoordinates(allCoords)
                return
            }
        }

        // フォールバック: ステップ座標から計算
        guard let route = viewModel.selectedRoute else { return }
        let coords = routeCoordinates(for: route)
        fitMapToCoordinates(coords)
    }

    // 座標配列にマップをフィット
    private func fitMapToCoordinates(_ coords: [CLLocationCoordinate2D]) {
        guard !coords.isEmpty else { return }

        var minLat = coords[0].latitude
        var maxLat = coords[0].latitude
        var minLng = coords[0].longitude
        var maxLng = coords[0].longitude

        for coord in coords {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLng = min(minLng, coord.longitude)
            maxLng = max(maxLng, coord.longitude)
        }

        let spanLat = max((maxLat - minLat) * 1.4, 0.005)
        let spanLng = max((maxLng - minLng) * 1.4, 0.005)

        withAnimation(.easeInOut(duration: 0.5)) {
            mapPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: (minLat + maxLat) / 2,
                    longitude: (minLng + maxLng) / 2
                ),
                span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLng)
            ))
        }
    }

    // ルートの座標配列を取得
    private func routeCoordinates(for route: RouteResult) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        for step in route.steps {
            if !step.polyline.isEmpty {
                let decoded = PolylineDecoder.decode(step.polyline)
                if !coordinates.isEmpty, let first = decoded.first,
                   let last = coordinates.last,
                   abs(last.latitude - first.latitude) < 1e-6,
                   abs(last.longitude - first.longitude) < 1e-6 {
                    coordinates.append(contentsOf: decoded.dropFirst())
                } else {
                    coordinates.append(contentsOf: decoded)
                }
            } else {
                let start = CLLocationCoordinate2D(
                    latitude: step.startLocation.lat,
                    longitude: step.startLocation.lng
                )
                let end = CLLocationCoordinate2D(
                    latitude: step.endLocation.lat,
                    longitude: step.endLocation.lng
                )
                if coordinates.isEmpty { coordinates.append(start) }
                coordinates.append(end)
            }
        }
        return coordinates
    }

    // MARK: - 入力セクション

    private var routeInputSection: some View {
        VStack(spacing: 6) {
            // 出発地
            HStack(spacing: 8) {
                Circle()
                    .fill(.green)
                    .frame(width: 10, height: 10)
                TextField("現在地", text: $viewModel.originText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .accessibilityLabel("出発地")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))

            // 目的地
            HStack(spacing: 8) {
                Image(systemName: "mappin")
                    .foregroundStyle(.red)
                    .frame(width: 10)
                TextField("目的地を入力", text: $viewModel.destinationText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await viewModel.searchRouteByName() }
                    }
                    .accessibilityLabel("目的地")

                if !viewModel.destinationText.isEmpty {
                    Button {
                        viewModel.destinationText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color(.systemBackground))
    }

    // 交通手段セレクター
    private var transportModeSelector: some View {
        HStack(spacing: 0) {
            ForEach(TransportMode.allCases) { mode in
                Button {
                    viewModel.selectedMode = mode
                    if !viewModel.destinationText.isEmpty {
                        Task { await viewModel.searchRouteByName() }
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: mode.iconName)
                            .font(.body)
                        Text(mode.label)
                            .font(.system(size: 10))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(viewModel.selectedMode == mode ? .white : .primary)
                    .background(
                        viewModel.selectedMode == mode ? mode.color : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .accessibilityLabel(mode.label)
                .accessibilityAddTraits(viewModel.selectedMode == mode ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .background(Color(.systemBackground))
    }

    // MARK: - ルート結果カルーセル

    private var routeResultsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.routeResults) { route in
                    Button {
                        viewModel.selectRoute(route)
                    } label: {
                        routeCard(route)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    // コンパクトなルートカード
    private func routeCard(_ route: RouteResult) -> some View {
        let isSelected = route.routeId == viewModel.selectedRoute?.routeId
        // 電車ルート判定: 警告に"🚃"で始まるものがあるか
        let transitWarning = route.warnings.first { $0.hasPrefix("🚃") }
        let isTransitRoute = transitWarning != nil

        return Button {
            detailRoute = route
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // スコア + 時間
                HStack {
                    // スコアバッジ
                    Text("\(route.accessibilityScore)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            AccessibilityHelpers.scoreColor(for: route.accessibilityScore),
                            in: Circle()
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(AccessibilityHelpers.durationText(minutes: route.durationMinutes))
                            .font(.subheadline)
                            .fontWeight(.bold)
                        Text(AccessibilityHelpers.distanceText(meters: route.distanceMeters))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // 電車ルートの場合: 駅名・タイムラインストリップ・「電車」ラベル表示
                if isTransitRoute, let warning = transitWarning {
                    // 駅名を抽出して表示
                    let stationName = String(warning.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    Text(stationName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    // カラータイムラインストリップ: 青(徒歩) → 緑(電車) → 青(徒歩)
                    HStack(spacing: 2) {
                        // 徒歩区間（青）
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue)
                            .frame(height: 4)
                        // 電車区間（緑）
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green)
                            .frame(height: 4)
                            .frame(maxWidth: .infinity)
                        // 徒歩区間（青）
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue)
                            .frame(height: 4)
                    }

                    // 「電車」ラベル
                    HStack(spacing: 4) {
                        Image(systemName: "tram.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text("電車")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                } else if !route.warnings.isEmpty {
                    // 通常の警告表示
                    Text(route.warnings.first ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(width: 180)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? viewModel.selectedMode.color : Color.clear, lineWidth: 2)
            )
        }
    }

    // VoiceOver用のラベル生成
    private func routeAccessibilityLabel(for route: RouteResult) -> String {
        let score = AccessibilityHelpers.scoreLabel(for: route.accessibilityScore)
        let distance = AccessibilityHelpers.distanceText(meters: route.distanceMeters)
        let duration = AccessibilityHelpers.durationText(minutes: route.durationMinutes)
        return "\(score)、距離\(distance)、所要時間\(duration)"
    }

    // 到着駅の駅名を取得（ラベルから「→到着駅名」を抽出、なければラベルをそのまま使用）
    private func destinationStationName(for segment: TransitSegment) -> String {
        // ラベルに「→」が含まれていれば到着駅名を抽出
        if let arrowRange = segment.label.range(of: "→") {
            return String(segment.label[arrowRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        // フォールバック: ラベルに「駅」が含まれていればそのまま返す
        if !segment.label.isEmpty {
            return segment.label
        }
        return "到着駅"
    }
}

// アクセシビリティスコアバッジ
struct ScoreBadgeView: View {
    let score: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: starIconName)
                .foregroundStyle(AccessibilityHelpers.scoreColor(for: score))

            Text("\(score)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(AccessibilityHelpers.scoreColor(for: score))

            Text("/ 100")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AccessibilityHelpers.scoreLabel(for: score))
    }

    private var starIconName: String {
        switch score {
        case 80...100: return "star.fill"
        case 50..<80: return "star.leadinghalf.filled"
        default: return "star"
        }
    }
}

// RouteResultをNavigationPathで使うためのHashable適合
extension RouteResult: Hashable {
    static func == (lhs: RouteResult, rhs: RouteResult) -> Bool {
        lhs.routeId == rhs.routeId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(routeId)
    }
}
