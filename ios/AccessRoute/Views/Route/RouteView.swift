import SwiftUI

// ルート検索結果画面
struct RouteView: View {
    @StateObject private var viewModel = RouteViewModel()
    @StateObject private var locationManager = LocationManager()
    var initialSearchText: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 検索フィールド
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("目的地を入力", text: $viewModel.destinationText)
                        .textFieldStyle(.plain)
                        .submitLabel(.search)
                        .onSubmit {
                            performSearch()
                        }
                        .accessibilityLabel("目的地入力フィールド")

                    if !viewModel.destinationText.isEmpty {
                        Button {
                            viewModel.destinationText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .ensureMinimumTapTarget()
                        .accessibilityLabel("テキストをクリア")
                    }
                }
                .padding(12)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 8)

                // 優先度選択
                Picker("ルート優先度", selection: $viewModel.selectedPriority) {
                    ForEach(RoutePriority.allCases) { priority in
                        Text(priority.label).tag(priority)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .accessibilityLabel("ルート優先度の選択")

                if viewModel.isSearching {
                    Spacer()
                    ProgressView("ルートを検索中...")
                        .accessibilityLabel("ルート検索中")
                    Spacer()
                } else if viewModel.routeResults.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("目的地を入力してルートを検索")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    // ルート一覧
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.routeResults) { route in
                                NavigationLink(value: route) {
                                    RouteCardView(route: route)
                                }
                                .accessibilityLabel(routeAccessibilityLabel(for: route))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }

                // エラーメッセージ
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("ルート")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: RouteResult.self) { route in
                RouteDetailView(route: route)
            }
            .onAppear {
                if viewModel.destinationText.isEmpty && !initialSearchText.isEmpty {
                    viewModel.destinationText = initialSearchText
                    performSearch()
                }
            }
        }
        .onTapGesture {
            hideKeyboard()
        }
    }

    // 検索実行
    private func performSearch() {
        // 位置情報の取得を開始
        locationManager.startUpdating()
        Task {
            // 現在地を出発地として使用
            let origin = locationManager.locationOrDefault
            await viewModel.searchRoute(
                origin: LatLng(lat: origin.latitude, lng: origin.longitude),
                destination: LatLng(lat: 35.6845, lng: 139.7690),
                userProfileId: "mock_user"
            )
        }
    }

    // VoiceOver用のラベル生成
    private func routeAccessibilityLabel(for route: RouteResult) -> String {
        let score = AccessibilityHelpers.scoreLabel(for: route.accessibilityScore)
        let distance = AccessibilityHelpers.distanceText(meters: route.distanceMeters)
        let duration = AccessibilityHelpers.durationText(minutes: route.durationMinutes)
        let warnings = route.warnings.isEmpty ? "" : "。注意: \(route.warnings.joined(separator: "、"))"
        return "\(score)、距離\(distance)、所要時間\(duration)\(warnings)"
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// ルートカード（一覧表示用）
struct RouteCardView: View {
    let route: RouteResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // スコアと距離・時間
            HStack {
                // アクセシビリティスコア
                ScoreBadgeView(score: route.accessibilityScore)

                Spacer()

                // 距離
                HStack(spacing: 4) {
                    Image(systemName: "figure.walk")
                        .font(.caption)
                    Text(AccessibilityHelpers.distanceText(meters: route.distanceMeters))
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)

                // 所要時間
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text(AccessibilityHelpers.durationText(minutes: route.durationMinutes))
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }

            // 警告表示
            if !route.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(route.warnings, id: \.self) { warning in
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            // ステップ数と沿道スポット
            HStack {
                Text("\(route.steps.count)ステップ")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !route.nearbySpots.isEmpty {
                    Text("沿道スポット \(route.nearbySpots.count)件")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1), in: Capsule())
                        .foregroundStyle(.blue)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

// アクセシビリティスコアバッジ
struct ScoreBadgeView: View {
    let score: Int

    var body: some View {
        HStack(spacing: 6) {
            // 星アイコン（スコアに応じて色変更）
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
        .accessibilityValue("スコア\(score)点")
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
