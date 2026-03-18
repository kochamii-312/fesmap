import SwiftUI
import MapKit

// ホーム画面
struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var locationManager = LocationManager()
    @State private var navigateToRoute = false
    @State private var hasMovedToUserLocation = false
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
                RouteView(initialSearchText: viewModel.searchText)
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
                let loc = locationManager.locationOrDefault
                // 初回のGPS取得時に現在地にズーム
                if !hasMovedToUserLocation, locationManager.currentLocation != nil {
                    hasMovedToUserLocation = true
                    withAnimation(.easeInOut(duration: 0.5)) {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: loc,
                            latitudinalMeters: 800,
                            longitudinalMeters: 800
                        ))
                    }
                }
                Task {
                    await viewModel.searchNearbySpots(lat: loc.latitude, lng: loc.longitude)
                    await viewModel.updateCurrentAddress(lat: loc.latitude, lng: loc.longitude)
                }
            }
            .onAppear {
                // GPS取得後に onChange で検索されるので、ここではデフォルト位置は使わない
                // GPSが既に取得済みならそれを使用
                if let loc = locationManager.currentLocation {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: loc,
                        latitudinalMeters: 800,
                        longitudinalMeters: 800
                    ))
                    Task {
                        await viewModel.searchNearbySpots(lat: loc.latitude, lng: loc.longitude)
                        await viewModel.updateCurrentAddress(lat: loc.latitude, lng: loc.longitude)
                    }
                }
            }
            .onDisappear {
                locationManager.stopUpdating()
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // 地図表示
    private var mapView: some View {
        Map(position: $cameraPosition, interactionModes: .all) {
            // 現在地（MapKit標準の青い丸）
            UserAnnotation()
            recommendedSpotAnnotations
            nearbySpotMarkers
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .ignoresSafeArea(edges: .top)
        .accessibilityLabel("地図")
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

            // クイックアクション
            quickActionsView

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

            // 下部パネル（コンパクト）
            bottomPanel
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

            // 検索ボタン
            if !text.isEmpty {
                Button {
                    onSubmit()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .ensureMinimumTapTarget()
                .accessibilityLabel("ルート検索を実行")
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
