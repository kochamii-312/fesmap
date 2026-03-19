import SwiftUI
@preconcurrency import MapKit

// ホーム画面
struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject private var appState: AppState // AppStateを注入
    @StateObject private var locationManager = LocationManager()
    @State private var navigateToRoute = false
    @State private var routeDestCoord: CLLocationCoordinate2D?
    @State private var hasMovedToUserLocation = false
    @State private var showSpotFilter = false
    // 初期位置：ユーザーの現在地に自動追従
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        )
    ))

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                mapView
                overlayView
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $navigateToRoute) {
                RouteView(
                    initialSearchText: viewModel.searchText,
                    initialDestCoord: routeDestCoord
                )
            }
            .onChange(of: navigateToRoute) { _, isNavigating in
                if !isNavigating {
                    routeDestCoord = nil
                }
            }
            .onChange(of: viewModel.shouldNavigateToRoute) { _, shouldNavigate in
                if shouldNavigate {
                    navigateToRoute = true
                    viewModel.shouldNavigateToRoute = false
                }
            }
            .task {
                locationManager.startUpdating()
            }
            .onChange(of: locationManager.currentLocation?.latitude) { _, _ in
                if !hasMovedToUserLocation, locationManager.currentLocation != nil {
                    hasMovedToUserLocation = true
                    withAnimation(.easeInOut(duration: 0.5)) {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: locationManager.locationOrDefault,
                            latitudinalMeters: 800,
                            longitudinalMeters: 800
                        ))
                    }
                }
            }
            .task {
                // mapActiveFilters が未設定ならプロフィール設定で初期化
                if UserDefaults.standard.stringArray(forKey: "mapActiveFilters") == nil {
                    let profileConditions = UserDefaults.standard.stringArray(
                        forKey: StorageKeys.preferConditions
                    ) ?? []
                    UserDefaults.standard.set(profileConditions, forKey: "mapActiveFilters")
                }
                // 位置情報が利用可能になるまで待機してからスポット検索を1回実行
                try? await Task.sleep(for: .seconds(2))
                let loc = locationManager.locationOrDefault
                await viewModel.searchNearbySpots(lat: loc.latitude, lng: loc.longitude)
                await viewModel.updateCurrentAddress(lat: loc.latitude, lng: loc.longitude)
            }
            .onDisappear {
                locationManager.stopUpdating()
            }
            // AIチャットからのスポット表示リクエストを監視
            .onReceive(appState.$spotsToShowOnMap) { spots in
                guard !spots.isEmpty else { return }
                viewModel.displaySpotsFromChat(spots)
                
                // スポット群を囲む領域にカメラを移動
                let coordinates = spots.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                let region = MKCoordinateRegion.from(coordinates: coordinates)
                withAnimation {
                    cameraPosition = .region(region)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // 地図表示
    private var mapView: some View {
        Map(position: $cameraPosition, interactionModes: .all) {
            // 現在地（MapKit標準の青い丸）
            UserAnnotation()
            
            // AIチャットからの推薦スポット
            chatSpotAnnotations

            recommendedSpotAnnotations
            nearbySpotMarkers
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
        }
        .ignoresSafeArea(edges: .top)
        .accessibilityLabel("地図")
    }

    // AIチャットからの推薦スポットマーカー（タップでルート表示）
    @MapContentBuilder
    private var chatSpotAnnotations: some MapContent {
        ForEach(viewModel.chatRecommendedSpots) { spot in
            Annotation(spot.name, coordinate: CLLocationCoordinate2D(
                latitude: spot.location.lat,
                longitude: spot.location.lng
            )) {
                ZStack {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 36, height: 36)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
                .overlay(alignment: .bottomTrailing) {
                    // ルート案内アイコンバッジ
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.blue, in: Circle())
                        .offset(x: 4, y: 4)
                }
                .onTapGesture {
                    viewModel.searchText = spot.name
                    routeDestCoord = CLLocationCoordinate2D(
                        latitude: spot.location.lat,
                        longitude: spot.location.lng
                    )
                    navigateToRoute = true
                }
                .accessibilityLabel("\(spot.name)へのルートを表示")
                .accessibilityHint("タップするとルート検索画面に移動します")
            }
        }
    }
    
    // おすすめスポットマーカー（カテゴリ別色分け）
    @MapContentBuilder
    private var recommendedSpotAnnotations: some MapContent {
        ForEach(viewModel.recommendedNearbySpots) { spot in
            Annotation(spot.name, coordinate: CLLocationCoordinate2D(
                latitude: spot.location.lat,
                longitude: spot.location.lng
            )) {
                ZStack {
                    Circle()
                        .fill(spot.category.markerColor)
                        .frame(width: 30, height: 30)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    Image(systemName: spot.category.iconName)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
            }
        }
    }

    // 周辺スポットマーカー（カテゴリ別色分け）
    @MapContentBuilder
    private var nearbySpotMarkers: some MapContent {
        ForEach(viewModel.nearbySpots) { spot in
            Annotation(spot.name, coordinate: CLLocationCoordinate2D(
                latitude: spot.location.lat,
                longitude: spot.location.lng
            )) {
                ZStack {
                    Circle()
                        .fill(spot.category.markerColor)
                        .frame(width: 26, height: 26)
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    Image(systemName: spot.category.iconName)
                        .font(.system(size: 11))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
            }
        }
    }

    // オーバーレイUI
    private var overlayView: some View {
        VStack(spacing: 0) {
            // 検索バー
            SearchBarView(text: $viewModel.searchText) {
                viewModel.submitSearch()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .onChange(of: viewModel.searchText) { _, newValue in
                viewModel.fetchSuggestions(for: newValue)
            }

            // 検索候補リスト
            if viewModel.showSuggestions {
                suggestionsListView
            }

            // 現在地ボタン + 住所表示
            HStack {
                // 現在地住所
                if !viewModel.currentAddress.isEmpty {
                    Text(viewModel.currentAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.leading, 16)
                }

                Spacer()

                Button {
                    moveToCurrentLocation()
                } label: {
                    Image(systemName: locationManager.isLocationAvailable ? "location.fill" : "location")
                        .font(.body)
                        .foregroundStyle(locationManager.isLocationAvailable ? .blue : .secondary)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                }
                .ensureMinimumTapTarget()
                .accessibilityLabel("現在地に移動")
                .accessibilityHint("地図を現在地に移動します")
                .padding(.trailing, 16)
            }
            .padding(.top, 8)

            Spacer()

            // 右下フロートボタン（おすすめリスト切替）
            HStack {
                Spacer()
                Button {
                    showSpotFilter.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(.blue, in: Circle())
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $showSpotFilter) {
            SpotFilterSheet(viewModel: viewModel, locationManager: locationManager)
                .presentationDetents([.medium])
        }
    }

    // 下部パネル：おすすめ + 周辺スポットをコンパクトに
    private var bottomPanel: some View {
        VStack(spacing: 0) {
            // おすすめスポット（1行、小さいカード）
            if !viewModel.recommendedNearbySpots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text("おすすめ")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                            .padding(.leading, 4)

                        ForEach(viewModel.recommendedNearbySpots) { spot in
                            Button {
                                moveToSpot(spot)
                            } label: {
                                CompactSpotChip(spot: spot)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 6)
            }

            Divider()

            // 周辺スポット（1行、小さいカード）
            if !viewModel.nearbySpots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text("周辺")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)

                        ForEach(viewModel.nearbySpots) { spot in
                            NavigationLink {
                                SpotDetailView(spotId: spot.spotId)
                            } label: {
                                CompactSpotChip(spot: spot)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 6)
            }

            // プロファイルサマリー（コンパクト）
            NavigationLink {
                ProfileView()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.profileMobilityType.iconName)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.blue, in: Circle())
                    Text(viewModel.profileMobilityType.label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(AccessibilityHelpers.distanceText(meters: viewModel.profileMaxDistance))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(Color(.systemBackground))
    }

    // 検索候補リスト
    private var suggestionsListView: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.suggestions) { suggestion in
                Button {
                    viewModel.selectSuggestion(suggestion)
                } label: {
                    HStack {
                        Image(systemName: "mappin.circle")
                            .foregroundStyle(.secondary)
                        Text(suggestion.description)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                Divider()
                    .padding(.leading, 44)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 4)
    }

    // クイックアクション（トイレ/EV/休憩所）
    private var quickActionsView: some View {
        HStack(spacing: 8) {
            quickActionButton(icon: "toilet", label: "トイレ", keyword: "最寄りトイレ")
            quickActionButton(icon: "arrow.up.square", label: "EV", keyword: "エレベーター")
            quickActionButton(icon: "cup.and.saucer", label: "休憩所", keyword: "休憩所")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func quickActionButton(icon: String, label: String, keyword: String) -> some View {
        Button {
            viewModel.quickSearch(keyword)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
        }
        .accessibilityLabel("\(label)を検索")
    }

    // コンパクトスポットチップ（小さい表示）

    // 現在地にカメラを移動
    private func moveToCurrentLocation() {
        if let location = locationManager.currentLocation {
            withAnimation(.easeInOut(duration: 0.3)) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: location,
                    latitudinalMeters: 500,
                    longitudinalMeters: 500
                ))
            }
        } else {
            // 位置情報未取得の場合は許可をリクエスト
            locationManager.requestPermission()
        }
    }

    // 指定したスポットにカメラを移動
    private func moveToSpot(_ spot: SpotSummary) {
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: spot.location.lat,
                    longitude: spot.location.lng
                ),
                latitudinalMeters: 500,
                longitudinalMeters: 500
            ))
        }
    }

}

// 検索バー
struct SearchBarView: View {
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("目的地を検索", text: $text)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .onSubmit {
                    onSubmit()
                }
                .accessibilityLabel("目的地検索フィールド")

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .ensureMinimumTapTarget()
                .accessibilityLabel("検索テキストをクリア")
            }

        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// コンパクトスポットチップ（横スクロール用の小さい表示）
struct CompactSpotChip: View {
    let spot: SpotSummary

    var body: some View {
        HStack(spacing: 6) {
            // スコア（色付き）
            Text("\(spot.accessibilityScore)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(AccessibilityHelpers.scoreColor(for: spot.accessibilityScore), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(spot.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(spot.category.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("\(spot.name)、スコア\(spot.accessibilityScore)点")
    }
}

// MARK: - おすすめフィルターシート

struct SpotFilterSheet: View {
    @ObservedObject var viewModel: HomeViewModel
    let locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    // マップ表示のオン/オフ（プロフィール設定とは別管理）
    private static let mapFilterKey = "mapActiveFilters"

    @State private var activeFilters: Set<String> = []
    @State private var refreshTask: Task<Void, Never>?

    // プロフィールで選択されたおすすめリスト項目のみ表示
    private var profilePreferConditions: [PreferCondition] {
        let saved = UserDefaults.standard.stringArray(forKey: StorageKeys.preferConditions) ?? []
        return saved.compactMap { PreferCondition(rawValue: $0) }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if profilePreferConditions.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "gearshape")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("設定タブの「おすすめリスト」から\n表示したい項目を選んでください")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                } else {
                    Text("タップで表示/非表示を切り替え")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 12) {
                        ForEach(profilePreferConditions) { condition in
                            let isOn = activeFilters.contains(condition.rawValue)

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if isOn {
                                        activeFilters.remove(condition.rawValue)
                                    } else {
                                        activeFilters.insert(condition.rawValue)
                                    }
                                }
                                // 即座に保存して再検索
                                saveAndRefresh()
                            } label: {
                                VStack(spacing: 6) {
                                    Text(condition.emoji)
                                        .font(.title2)
                                    Text(condition.label)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(isOn ? .black : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    isOn ? Color.blue.opacity(0.1) : Color(.systemGray6),
                                    in: RoundedRectangle(cornerRadius: 14)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(isOn ? Color.blue : Color.clear, lineWidth: 2)
                                )
                                .opacity(isOn ? 1.0 : 0.6)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top)
            .navigationTitle("おすすめリスト")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // マップフィルターを読み込み、プロフィールにないものは除外
                let profileSet = Set(profilePreferConditions.map(\.rawValue))
                if let saved = UserDefaults.standard.stringArray(forKey: Self.mapFilterKey) {
                    // プロフィールに存在するもののみ残す
                    activeFilters = Set(saved).intersection(profileSet)
                } else {
                    // 初回はプロフィール設定のものを全てオン
                    activeFilters = profileSet
                }
                UserDefaults.standard.set(Array(activeFilters), forKey: Self.mapFilterKey)
            }
        }
    }

    private func saveAndRefresh() {
        // マップ表示フィルターのみ保存（プロフィール設定は変えない）
        UserDefaults.standard.set(Array(activeFilters), forKey: Self.mapFilterKey)

        // 連打対策: 前の検索タスクをキャンセルして300msデバウンス
        refreshTask?.cancel()
        let loc = locationManager.locationOrDefault
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await viewModel.searchNearbySpots(lat: loc.latitude, lng: loc.longitude)
        }
    }
}

// MARK: - MapKit Helper Extension

extension MKCoordinateRegion {
    /// 複数の座標を囲む最適な領域を計算する
    static func from(coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            // デフォルト領域（東京駅周辺）
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
                latitudinalMeters: 1000,
                longitudinalMeters: 1000
            )
        }

        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.4, // 少し余白を持たせる
            longitudeDelta: (maxLon - minLon) * 1.4
        )

        return MKCoordinateRegion(center: center, span: span)
    }
}
