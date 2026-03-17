import SwiftUI

// スポット一覧画面（座標検索・展開式カード）
struct SpotView: View {
    @StateObject private var viewModel = SpotViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 座標入力フォーム
                coordinateForm

                // 検索結果
                resultContent
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("スポット")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 座標入力フォーム

    private var coordinateForm: some View {
        VStack(spacing: 12) {
            Text("座標で検索")
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("緯度")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("35.6812", text: $viewModel.latText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("緯度")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("経度")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("139.7671", text: $viewModel.lngText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("経度")
                }
            }

            Button {
                Task {
                    await viewModel.searchByCoordinates()
                }
            } label: {
                if viewModel.isSearching {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("周辺スポットを検索")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: AccessibilityHelpers.minimumTapTarget)
            .background(viewModel.isSearching ? Color.blue.opacity(0.5) : Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .disabled(viewModel.isSearching)
            .accessibilityLabel("スポットを検索")

            if let error = viewModel.coordError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - 検索結果

    @ViewBuilder
    private var resultContent: some View {
        if viewModel.isSearching {
            Spacer()
            ProgressView("スポットを検索中...")
                .accessibilityLabel("スポット検索中")
            Spacer()
        } else if viewModel.hasSearched && viewModel.spots.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("周辺にスポットが見つかりませんでした")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        } else if !viewModel.spots.isEmpty {
            ScrollView {
                LazyVStack(spacing: 10) {
                    Text("\(viewModel.spots.count)件のスポットが見つかりました")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                    ForEach(viewModel.spots) { spot in
                        SpotCard(
                            spot: spot,
                            isExpanded: viewModel.expandedSpotId == spot.spotId,
                            detail: viewModel.spotDetails[spot.spotId],
                            isLoadingDetail: viewModel.loadingDetailId == spot.spotId
                        ) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                viewModel.toggleExpand(spotId: spot.spotId)
                            }
                        }
                    }
                }
                .padding(12)
            }
        } else {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("座標を入力してスポットを検索")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - スポットカード

struct SpotCard: View {
    let spot: SpotSummary
    let isExpanded: Bool
    let detail: SpotDetail?
    let isLoadingDetail: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // カードヘッダー
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // スコアバッジ（円形）
                    Text("\(spot.accessibilityScore)")
                        .font(.callout)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            AccessibilityHelpers.scoreColor(for: spot.accessibilityScore),
                            in: Circle()
                        )

                    // スポット情報
                    VStack(alignment: .leading, spacing: 4) {
                        Text(spot.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Text(spot.category.label)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1), in: Capsule())
                                .foregroundStyle(.blue)

                            Text(AccessibilityHelpers.distanceText(meters: spot.distanceFromRoute))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // 展開アイコン
                    Image(systemName: isExpanded ? "minus" : "plus")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(spot.name)、\(spot.category.label)、スコア\(spot.accessibilityScore)点")
            .accessibilityHint("タップして詳細を表示")

            // 展開コンテンツ
            if isExpanded {
                Divider()

                if isLoadingDetail {
                    ProgressView()
                        .padding(20)
                } else if let detail {
                    SpotExpandedContent(detail: detail)
                }
            }
        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
    }
}

// MARK: - 展開コンテンツ

struct SpotExpandedContent: View {
    let detail: SpotDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 住所
            detailRow(icon: "mappin", label: "住所", value: detail.address)

            // 電話番号（リンク付き）
            if let phone = detail.phoneNumber {
                if let url = URL(string: "tel:\(phone)") {
                    Link(destination: url) {
                        detailRowContent(icon: "phone", label: "電話番号", value: phone, isLink: true)
                    }
                    .accessibilityLabel("電話: \(phone)")
                }
            }

            // 営業時間
            if let hours = detail.openingHours {
                detailRow(icon: "clock", label: "営業時間", value: hours)
            }

            // 説明
            if !detail.description.isEmpty {
                detailRow(icon: "doc.text", label: "説明", value: detail.description)
            }

            // バリアフリー設備バッジ
            VStack(alignment: .leading, spacing: 8) {
                Text("バリアフリー設備")
                    .font(.caption)
                    .fontWeight(.semibold)

                // swiftlint:disable:next line_length
                let facilities: [(String, Bool)] = [
                    ("エレベーター", detail.accessibility.hasElevator),
                    ("多目的トイレ", detail.accessibility.hasAccessibleRestroom),
                    ("車椅子対応", detail.accessibility.wheelchairAccessible)
                ]

                FlowLayout(spacing: 8) {
                    ForEach(facilities, id: \.0) { label, available in
                        FacilityBadge(label: label, available: available)
                    }
                }
            }
        }
        .padding(14)
    }

    // 詳細行
    private func detailRow(icon: String, label: String, value: String) -> some View {
        detailRowContent(icon: icon, label: label, value: value, isLink: false)
    }

    private func detailRowContent(
        icon: String,
        label: String,
        value: String,
        isLink: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(isLink ? .blue : .primary)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - 設備バッジ（○/×表示）

struct FacilityBadge: View {
    let label: String
    let available: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(available ? "\u{25CB}" : "\u{00D7}")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(available ? .green : .gray)

            Text(label)
                .font(.caption)
                .foregroundStyle(available ? .primary : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            available ? Color.green.opacity(0.1) : Color(.systemGray6),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(available ? "対応" : "非対応")")
    }
}

