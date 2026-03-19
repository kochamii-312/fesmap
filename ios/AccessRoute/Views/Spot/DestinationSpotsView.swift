import SwiftUI
@preconcurrency import MapKit

// 目的地周辺のおすすめスポット一覧画面
struct DestinationSpotsView: View {
    @StateObject private var viewModel = DestinationSpotsViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 目的地入力
                searchBar

                if viewModel.isSearching {
                    Spacer()
                    ProgressView("周辺を検索中...")
                    Spacer()
                } else if viewModel.spots.isEmpty && viewModel.hasSearched {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("スポットが見つかりませんでした")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else if viewModel.spots.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("目的地を入力して\n周辺のおすすめを検索")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    // 結果件数
                    HStack {
                        Text("\(viewModel.searchLabel) \(viewModel.spots.count)件のおすすめ")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.black)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // スポット一覧
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.spots) { spot in
                                SpotListCard(
                                    spot: spot,
                                    googleDetail: viewModel.detailCache[spot.spotId]
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("スポット")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // 起動時に現在地周辺を自動検索
                if !viewModel.hasSearched {
                    await viewModel.searchNearCurrentLocation()
                }
            }
        }
    }

    // 検索バー
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin")
                .foregroundStyle(.red)
            TextField("目的地を入力", text: $viewModel.destinationText)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .onSubmit {
                    Task { await viewModel.search() }
                }

            if !viewModel.destinationText.isEmpty {
                Button {
                    viewModel.destinationText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task { await viewModel.search() }
            } label: {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            .disabled(viewModel.destinationText.isEmpty)
        }
        .padding(12)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

// スポットカード（詳細情報付き）
struct SpotListCard: View {
    let spot: SpotSummary
    var googleDetail: GooglePlacesService.SpotDetailInfo?
    @State private var isExpanded = false
    @State private var detail: SpotListDetail?
    @State private var showMap = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ヘッダー
            Button {
                isExpanded.toggle()
                if isExpanded && detail == nil {
                    // MKLocalSearch のみ使用（高速・フリーズなし）
                    let coord = CLLocationCoordinate2D(
                        latitude: spot.location.lat, longitude: spot.location.lng
                    )
                    let request = MKLocalSearch.Request()
                    request.naturalLanguageQuery = spot.name
                    request.region = MKCoordinateRegion(
                        center: coord,
                        latitudinalMeters: 300, longitudinalMeters: 300
                    )
                    Task {
                        let search = MKLocalSearch(request: request)
                        let result: (address: String?, phone: String?) = await withCheckedContinuation { continuation in
                            search.start { response, _ in
                                if let item = response?.mapItems.first {
                                    continuation.resume(returning: (item.placemark.title, item.phoneNumber))
                                } else {
                                    continuation.resume(returning: (nil, nil))
                                }
                            }
                        }
                        detail = SpotListDetail(
                            address: result.address,
                            phone: result.phone,
                            hours: nil
                        )
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    // カテゴリアイコン
                    ZStack {
                        Circle()
                            .fill(spot.category.markerColor)
                            .frame(width: 40, height: 40)
                        Image(systemName: spot.category.iconName)
                            .font(.body)
                            .foregroundStyle(.white)
                    }

                    // 名前・カテゴリ
                    VStack(alignment: .leading, spacing: 2) {
                        Text(spot.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.black)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Text(spot.category.label)
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(spot.category.markerColor, in: Capsule())

                            if spot.distanceFromRoute > 0 {
                                Text("\(Int(spot.distanceFromRoute))m")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    // スコア
                    Text("\(spot.accessibilityScore)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            AccessibilityHelpers.scoreColor(for: spot.accessibilityScore),
                            in: Circle()
                        )

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)

            // 展開時の詳細情報
            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 10) {
                    // Google Places の詳細がある場合
                    if let gd = googleDetail {
                        // ジャンル
                        if let cuisine = gd.cuisineType {
                            detailRow(icon: "fork.knife", label: "ジャンル", value: cuisine)
                        }

                        // 評価・価格帯・営業状況
                        HStack(spacing: 12) {
                            if let rating = gd.rating {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                    Text(String(format: "%.1f", rating))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.black)
                                }
                            }
                            if let priceText = GooglePlacesService.priceLevelText(gd.priceLevel) {
                                Text(priceText)
                                    .font(.caption)
                                    .foregroundStyle(.black)
                            }
                            if let openNow = gd.openNow {
                                Text(openNow ? "営業中" : "営業時間外")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(openNow ? .green : .red)
                            }
                        }

                        // バリアフリー
                        if let wheelchair = gd.isWheelchairAccessible {
                            HStack(spacing: 6) {
                                Image(systemName: wheelchair ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(wheelchair ? .green : .red)
                                Text(wheelchair ? "車椅子対応入口あり" : "車椅子対応入口なし")
                                    .font(.subheadline)
                                    .foregroundStyle(.black)
                            }
                        } else if spot.isBarrierFree {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("バリアフリー対応（推定）")
                                    .font(.subheadline)
                                    .foregroundStyle(.black)
                            }
                        }

                        // 住所
                        if let address = gd.address {
                            detailRow(icon: "mappin", label: "住所", value: address)
                        }

                        // 電話番号
                        if let phone = gd.phone {
                            HStack(spacing: 8) {
                                Image(systemName: "phone.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .frame(width: 20)
                                Link(phone, destination: URL(string: "tel:\(phone)")!)
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                            }
                        }

                        // 営業時間（全曜日）
                        if !gd.openingHours.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                detailRow(icon: "clock", label: "営業時間", value: "")
                                ForEach(gd.openingHours, id: \.self) { hours in
                                    Text(hours)
                                        .font(.caption)
                                        .foregroundStyle(.black)
                                        .padding(.leading, 28)
                                }
                            }
                        }

                        // レビュー
                        if let review = gd.review {
                            VStack(alignment: .leading, spacing: 2) {
                                detailRow(icon: "quote.bubble", label: "レビュー", value: "")
                                Text(review + "...")
                                    .font(.caption)
                                    .foregroundStyle(.black)
                                    .padding(.leading, 28)
                                    .lineLimit(3)
                            }
                        }
                    } else {
                        // Google 詳細がまだない場合（基本情報のみ）
                        detailRow(icon: "tag", label: "カテゴリ", value: spot.category.label)

                        if let address = detail?.address {
                            detailRow(icon: "mappin", label: "住所", value: address)
                        }
                        if let phone = detail?.phone {
                            HStack(spacing: 8) {
                                Image(systemName: "phone.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .frame(width: 20)
                                Link(phone, destination: URL(string: "tel:\(phone)")!)
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                            }
                        }
                        if spot.isBarrierFree {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("バリアフリー対応（推定）")
                                    .font(.subheadline)
                                    .foregroundStyle(.black)
                            }
                        }

                        // 取得中の表示
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("詳細情報を取得中...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // マップで開くボタン
                    Button {
                        showMap = true
                    } label: {
                        HStack {
                            Image(systemName: "map.fill")
                            Text("マップで開く")
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(12)
            }
        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        .sheet(isPresented: $showMap) {
            SpotMapSheet(spot: spot)
        }
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.black)
            }
        }
    }

    // loadDetail は不要（タップ時に Task.detached で直接呼び出し）

}

// アプリ内マップ表示シート
struct SpotMapSheet: View {
    let spot: SpotSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Map {
                // 現在地
                UserAnnotation()

                // スポットマーカー
                Annotation(spot.name, coordinate: CLLocationCoordinate2D(
                    latitude: spot.location.lat,
                    longitude: spot.location.lng
                )) {
                    VStack(spacing: 2) {
                        ZStack {
                            Circle()
                                .fill(spot.category.markerColor)
                                .frame(width: 36, height: 36)
                                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                            Image(systemName: spot.category.iconName)
                                .font(.body)
                                .foregroundStyle(.white)
                        }
                        Text(spot.name)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white, in: RoundedRectangle(cornerRadius: 4))
                            .shadow(color: .black.opacity(0.1), radius: 2)
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .navigationTitle(spot.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        openInAppleMaps()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            Text("ナビを開始")
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private func openInAppleMaps() {
        let coordinate = CLLocationCoordinate2D(
            latitude: spot.location.lat, longitude: spot.location.lng
        )
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = spot.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
}

// スポット詳細データ
struct SpotListDetail {
    let address: String?
    let phone: String?
    let hours: String?
}

// ViewModel
@MainActor
final class DestinationSpotsViewModel: ObservableObject {
    @Published var destinationText = ""
    @Published var spots: [SpotSummary] = []
    @Published var isSearching = false
    @Published var hasSearched = false
    @Published var searchLabel = "" // 「現在地周辺」or「○○周辺」

    // Google Places 詳細のキャッシュ（spotId → 詳細）
    @Published var detailCache: [String: GooglePlacesService.SpotDetailInfo] = [:]

    private let locationManager = CLLocationManager()
    private var fetchTask: Task<Void, Never>?

    // 起動時に現在地周辺を検索
    func searchNearCurrentLocation() async {
        isSearching = true
        hasSearched = true
        detailCache = [:]
        searchLabel = "現在地周辺"

        let coordinate: CLLocationCoordinate2D
        if let loc = locationManager.location?.coordinate {
            coordinate = loc
        } else {
            // GPS未取得時はデフォルト位置
            coordinate = LocationManager.defaultLocation
        }

        spots = await MapSpotSearchService.searchPreferredSpots(
            near: coordinate,
            radius: 800
        )

        isSearching = false
        fetchDetailsInBackground()
    }

    func search() async {
        let destination = destinationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else {
            // 空欄の場合は現在地周辺を検索
            await searchNearCurrentLocation()
            return
        }

        isSearching = true
        hasSearched = true
        detailCache = [:]
        searchLabel = "\(destination)周辺"

        do {
            let coord = try await GeocodingService.shared.geocode(destination)
            let coordinate = CLLocationCoordinate2D(latitude: coord.lat, longitude: coord.lng)

            spots = await MapSpotSearchService.searchPreferredSpots(
                near: coordinate,
                radius: 800
            )
        } catch {
            spots = []
        }

        isSearching = false
        fetchDetailsInBackground()
    }

    // バックグラウンドで上位スポットの詳細を事前取得（最大5件に制限）
    private func fetchDetailsInBackground() {
        fetchTask?.cancel()
        let spotsToFetch = Array(spots.prefix(5))
        fetchTask = Task.detached {
            for spot in spotsToFetch {
                guard !Task.isCancelled else { break }
                let coord = CLLocationCoordinate2D(
                    latitude: spot.location.lat, longitude: spot.location.lng
                )
                if let detail = await GooglePlacesService.fetchDetail(
                    name: spot.name, coordinate: coord
                ) {
                    await MainActor.run {
                        self.detailCache[spot.spotId] = detail
                    }
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }
}
