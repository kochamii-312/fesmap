import SwiftUI
import MapKit

// ホーム画面
struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var locationManager = LocationManager()
    @State private var navigateToRoute = false
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // 地図表示エリア
                Map(position: $cameraPosition) {
                    // 現在地マーカー
                    if let location = locationManager.currentLocation {
                        Annotation("現在地", coordinate: location) {
                            ZStack {
                                Circle()
                                    .fill(.blue.opacity(0.2))
                                    .frame(width: 32, height: 32)
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 14, height: 14)
                                Circle()
                                    .stroke(.white, lineWidth: 2)
                                    .frame(width: 14, height: 14)
                            }
                            .accessibilityLabel("現在地")
                        }
                    }

                    // おすすめスポットマーカー（星アイコン）
                    ForEach(viewModel.recommendedSpots) { spot in
                        Annotation(spot.name, coordinate: CLLocationCoordinate2D(
                            latitude: spot.location.lat,
                            longitude: spot.location.lng
                        )) {
                            ZStack {
                                Circle()
                                    .fill(AccessibilityHelpers.scoreColor(for: spot.accessibilityScore))
                                    .frame(width: 30, height: 30)
                                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                                Image(systemName: spot.category.iconName)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            }
                        }
                    }

                    // 周辺スポットマーカー
                    ForEach(viewModel.nearbySpots) { spot in
                        Marker(
                            spot.name,
                            coordinate: CLLocationCoordinate2D(
                                latitude: spot.location.lat,
                                longitude: spot.location.lng
                            )
                        )
                        .tint(AccessibilityHelpers.scoreColor(for: spot.accessibilityScore))
                    }
                }
                .ignoresSafeArea(edges: .top)
                .accessibilityLabel("地図")

                VStack(spacing: 0) {
                    // 検索バー
                    SearchBarView(text: $viewModel.searchText) {
                        viewModel.submitSearch()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // 現在地ボタン
                    HStack {
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
                        .padding(.top, 8)
                    }

                    Spacer()

                    // あなたへのおすすめ
                    if !viewModel.recommendedNearbySpots.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "hand.thumbsup.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                Text("あなたへのおすすめ")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("現在地の近くにある、あなたへのおすすめスポット")

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 10) {
                                    ForEach(viewModel.recommendedNearbySpots) { spot in
                                        Button {
                                            moveToSpot(spot)
                                        } label: {
                                            RecommendedSpotCard(spot: spot)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(spot.name)、\(spot.category.label)、スコア\(spot.accessibilityScore)点、おすすめ")
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                    }

                    // 周辺スポット（横スクロール）
                    if !viewModel.nearbySpots.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("周辺のスポット")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 10) {
                                    ForEach(viewModel.nearbySpots) { spot in
                                        NavigationLink {
                                            SpotDetailView(spotId: spot.spotId)
                                        } label: {
                                            HomeSpotCard(spot: spot)
                                        }
                                        .accessibilityLabel("\(spot.name)、\(spot.category.label)、スコア\(spot.accessibilityScore)点")
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                    }

                    // プロファイルサマリー
                    NavigationLink {
                        ProfileView()
                    } label: {
                        ProfileSummaryCard(viewModel: viewModel)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
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
                // 位置情報の取得を開始
                locationManager.startUpdating()
            }
            .onChange(of: locationManager.currentLocation?.latitude) { _, _ in
                // 現在地が更新されたら周辺スポットを検索
                let loc = locationManager.locationOrDefault
                Task {
                    await viewModel.searchNearbySpots(lat: loc.latitude, lng: loc.longitude)
                }
            }
            .onAppear {
                // 初回は現在地またはデフォルト位置で検索
                let loc = locationManager.locationOrDefault
                Task {
                    await viewModel.searchNearbySpots(lat: loc.latitude, lng: loc.longitude)
                }
            }
            .onDisappear {
                locationManager.stopUpdating()
            }
        }
        .onTapGesture {
            hideKeyboard()
        }
    }

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

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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

// ホーム画面用スポットカード
struct HomeSpotCard: View {
    let spot: SpotSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: spot.category.iconName)
                    .font(.caption)
                    .foregroundStyle(AccessibilityHelpers.scoreColor(for: spot.accessibilityScore))

                Text("\(spot.accessibilityScore)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(AccessibilityHelpers.scoreColor(for: spot.accessibilityScore))
            }

            Text(spot.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text("\(Int(spot.distanceFromRoute))m")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 130)
        .padding(10)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }

}

// おすすめスポットカード（星バッジ付き）
struct RecommendedSpotCard: View {
    let spot: SpotSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // カテゴリアイコン
                Image(systemName: spot.category.iconName)
                    .font(.caption)
                    .foregroundStyle(AccessibilityHelpers.scoreColor(for: spot.accessibilityScore))

                Spacer()

                // おすすめバッジ
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                    Text("\(spot.accessibilityScore)")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .foregroundStyle(.orange)
            }

            Text(spot.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(spot.category.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 140)
        .padding(10)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.orange.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }
}

// プロファイルサマリーカード
struct ProfileSummaryCard: View {
    let viewModel: HomeViewModel

    var body: some View {
        HStack(spacing: 12) {
            // 移動手段アイコン
            Image(systemName: viewModel.profileMobilityType.iconName)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.blue, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.profileMobilityType.label)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    // 最大距離
                    Text(AccessibilityHelpers.distanceText(meters: viewModel.profileMaxDistance))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // 同行者
                    if !viewModel.profileCompanions.isEmpty {
                        Text(viewModel.profileCompanions.map(\.label).joined(separator: "・"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("プロファイル: \(viewModel.profileMobilityType.label)、最大距離\(AccessibilityHelpers.distanceText(meters: viewModel.profileMaxDistance))")
        .accessibilityAddTraits(.isButton)
    }
}
