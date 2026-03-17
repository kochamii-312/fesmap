import SwiftUI

// スポット詳細画面
struct SpotDetailView: View {
    let spotId: String
    @StateObject private var viewModel = SpotViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("読み込み中...")
                    .accessibilityLabel("スポット情報を読み込み中")
            } else if let spot = viewModel.spotDetail {
                spotContent(spot)
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("スポット詳細")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadSpotDetail(spotId: spotId)
        }
    }

    // スポット詳細コンテンツ
    @ViewBuilder
    private func spotContent(_ spot: SpotDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 写真ギャラリー
                photoGallery(spot)

                // 基本情報
                basicInfoSection(spot)

                // アクセシビリティスコア
                scoreSection(spot)

                // バリアフリー設備バッジ（○/×表示）
                facilityBadgeSection(spot)

                // バリアフリー詳細情報
                accessibilitySection(spot)

                // 営業情報
                businessInfoSection(spot)
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - 写真ギャラリー

    @ViewBuilder
    private func photoGallery(_ spot: SpotDetail) -> some View {
        if spot.photoUrls.isEmpty {
            // プレースホルダー画像
            ZStack {
                Rectangle()
                    .fill(Color(.systemGray5))
                VStack(spacing: 8) {
                    Image(systemName: spot.category.iconName)
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("写真なし")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 200)
            .accessibilityLabel("\(spot.name)の写真（プレースホルダー）")
        } else {
            // 写真がある場合（横スクロール・キャッシュ対応）
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(spot.photoUrls, id: \.self) { urlString in
                        CachedAsyncImage(url: URL(string: urlString)) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: UIScreen.main.bounds.width, height: 200)
                                .clipped()
                        } placeholder: {
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(width: UIScreen.main.bounds.width, height: 200)
                                .overlay {
                                    ProgressView()
                                }
                        }
                    }
                }
            }
            .frame(height: 200)
            .accessibilityLabel("\(spot.name)の写真ギャラリー、\(spot.photoUrls.count)枚")
        }
    }

    // MARK: - 基本情報

    private func basicInfoSection(_ spot: SpotDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // カテゴリ
            Text(spot.category.label)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1), in: Capsule())
                .foregroundStyle(.blue)

            // スポット名
            Text(spot.name)
                .font(.title2)
                .fontWeight(.bold)

            // 説明文
            if !spot.description.isEmpty {
                Text(spot.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            // 住所
            HStack(spacing: 6) {
                Image(systemName: "mappin")
                    .foregroundStyle(.red)
                Text(spot.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spot.category.label)、\(spot.name)、\(spot.address)")
    }

    // MARK: - スコアセクション

    private func scoreSection(_ spot: SpotDetail) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("バリアフリースコア")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    // スコア表示
                    Text("\(spot.accessibilityScore)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(AccessibilityHelpers.scoreColor(for: spot.accessibilityScore))

                    Text("/ 100")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // 星表示
                    HStack(spacing: 2) {
                        ForEach(0..<5) { index in
                            Image(systemName: starName(for: index, score: spot.accessibilityScore))
                                .foregroundStyle(AccessibilityHelpers.scoreColor(for: spot.accessibilityScore))
                        }
                    }
                    .font(.title3)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(AccessibilityHelpers.scoreLabel(for: spot.accessibilityScore))、スコア\(spot.accessibilityScore)点"
        )
    }

    // MARK: - 設備バッジセクション（○/×表示）

    private func facilityBadgeSection(_ spot: SpotDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("バリアフリー設備")
                .font(.headline)
                .padding(.horizontal)

            let facilities: [(String, Bool)] = [
                ("エレベーター", spot.accessibility.hasElevator),
                ("多目的トイレ", spot.accessibility.hasAccessibleRestroom),
                ("車椅子対応", spot.accessibility.wheelchairAccessible)
            ]

            FlowLayout(spacing: 8) {
                ForEach(facilities, id: \.0) { label, available in
                    FacilityBadge(label: label, available: available)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - バリアフリー詳細情報

    private func accessibilitySection(_ spot: SpotDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("バリアフリー詳細")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                AccessibilityFeatureItem(
                    icon: "figure.roll",
                    label: "車椅子対応",
                    isAvailable: spot.accessibility.wheelchairAccessible
                )
                AccessibilityFeatureItem(
                    icon: "arrow.up.arrow.down",
                    label: "エレベーター",
                    isAvailable: spot.accessibility.hasElevator
                )
                AccessibilityFeatureItem(
                    icon: "toilet",
                    label: "多目的トイレ",
                    isAvailable: spot.accessibility.hasAccessibleRestroom
                )
                AccessibilityFeatureItem(
                    icon: "figure.and.child.holdinghands",
                    label: "おむつ替え台",
                    isAvailable: spot.accessibility.hasBabyChangingStation
                )
                AccessibilityFeatureItem(
                    icon: "heart",
                    label: "授乳室",
                    isAvailable: spot.accessibility.hasNursingRoom
                )
                AccessibilityFeatureItem(
                    icon: floorTypeIcon(spot.accessibility.floorType),
                    label: floorTypeLabel(spot.accessibility.floorType),
                    isAvailable: spot.accessibility.floorType == .flat
                )
            }
            .padding(.horizontal)

            // 補足ノート
            if !spot.accessibility.notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(spot.accessibility.notes, id: \.self) { note in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .padding(.top, 2)
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - 営業情報

    @ViewBuilder
    private func businessInfoSection(_ spot: SpotDetail) -> some View {
        let hasInfo = spot.openingHours != nil || spot.phoneNumber != nil || spot.website != nil
        if hasInfo {
            VStack(alignment: .leading, spacing: 12) {
                Text("営業情報")
                    .font(.headline)
                    .padding(.horizontal)

                VStack(spacing: 0) {
                    if let hours = spot.openingHours {
                        BusinessInfoRow(icon: "clock", label: "営業時間", value: hours)
                    }
                    if let phone = spot.phoneNumber {
                        // 電話番号リンク
                        if let url = URL(string: "tel:\(phone)") {
                            Link(destination: url) {
                                BusinessInfoRow(icon: "phone", label: "電話番号", value: phone, isLink: true)
                            }
                            .accessibilityLabel("電話: \(phone)")
                        } else {
                            BusinessInfoRow(icon: "phone", label: "電話番号", value: phone)
                        }
                    }
                    if let website = spot.website {
                        BusinessInfoRow(icon: "globe", label: "ウェブサイト", value: website)
                    }
                }
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }

    // MARK: - ヘルパー

    private func starName(for index: Int, score: Int) -> String {
        let starValue = Double(score) / 20.0
        let starIndex = Double(index)
        if starValue >= starIndex + 1 {
            return "star.fill"
        } else if starValue >= starIndex + 0.5 {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }

    private func floorTypeIcon(_ type: FloorType) -> String {
        switch type {
        case .flat: return "road.lanes"
        case .steps: return "stairs"
        case .slope: return "arrow.up.right"
        case .mixed: return "arrow.triangle.branch"
        }
    }

    private func floorTypeLabel(_ type: FloorType) -> String {
        switch type {
        case .flat: return "フラットな床"
        case .steps: return "段差あり"
        case .slope: return "傾斜あり"
        case .mixed: return "段差・傾斜混在"
        }
    }
}

// バリアフリー機能アイテム
struct AccessibilityFeatureItem: View {
    let icon: String
    let label: String
    let isAvailable: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isAvailable ? .green : .gray)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.primary)
                Text(isAvailable ? "対応" : "非対応")
                    .font(.caption2)
                    .foregroundStyle(isAvailable ? .green : .secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isAvailable ? Color.green.opacity(0.08) : Color(.systemGray6))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(isAvailable ? "対応" : "非対応")")
    }
}

// 営業情報行
struct BusinessInfoRow: View {
    let icon: String
    let label: String
    let value: String
    var isLink: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(isLink ? .blue : .primary)
            }

            Spacer()
        }
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
