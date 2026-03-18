import SwiftUI

// プロファイル編集画面（Expo Go版デザイン準拠）
struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showSaveAlert = false

    // Expo版で使用する移動手段（otherを除外）
    private var displayMobilityTypes: [MobilityType] {
        MobilityType.allCases.filter { $0 != .other }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 背景色（明るいグレー・ライトモード固定）
                Color(red: 0.96, green: 0.96, blue: 0.98)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // 1. プロファイル完了度カード
                        completionCard

                        // 2. 移動手段セクション
                        mobilitySection

                        // 3. 回避したい条件セクション
                        avoidSection

                        // 4. 優先したい条件セクション
                        preferSection

                        // 5. 最大移動距離カード
                        distanceCard

                        // 保存ボタンの下に余白を確保
                        Spacer().frame(height: 80)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }

                // 6. 固定保存ボタン
                saveButton
            }
            .navigationTitle("プロファイル")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadProfile()
            }
            .alert("保存完了", isPresented: $showSaveAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("設定を保存しました")
            }
            .alert("エラー", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - 1. プロファイル完了度カード

    private var completionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("プロファイル完了度")
                    .font(.subheadline)
                    .foregroundStyle(.black)

                Spacer()

                Text("\(viewModel.completionPercentage)%")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Color(hex: 0x007AFF))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("プロファイル完了度 \(viewModel.completionPercentage)パーセント")

            // プログレスバー
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray4))
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: 0x007AFF))
                        .frame(
                            width: geometry.size.width * CGFloat(viewModel.completionPercentage) / 100,
                            height: 12
                        )
                        .animation(.easeInOut(duration: 0.5), value: viewModel.completionPercentage)
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)
        }
        .padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - 2. 移動手段セクション

    private var mobilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("移動手段")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(displayMobilityTypes.enumerated()), id: \.element.id) { index, type in
                    let isSelected = viewModel.mobilityType == type

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.mobilityType = type
                        }
                    } label: {
                        HStack(spacing: 14) {
                            // 絵文字アイコンボックス
                            Text(type.emoji)
                                .font(.system(size: 22))
                                .frame(width: 44, height: 44)
                                .background(
                                    Color(hex: mobilityColorValue(for: type)).opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                                .accessibilityHidden(true)

                            // ラベルと説明
                            VStack(alignment: .leading, spacing: 2) {
                                Text(type.label)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.black)

                                Text(type.descriptionText)
                                    .font(.caption)
                                    .foregroundStyle(.black)
                            }

                            Spacer()

                            // ラジオボタン
                            radioButton(isSelected: isSelected)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            isSelected
                                ? Color(hex: 0xF0F7FF)
                                : Color.white
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(type.label) — \(type.descriptionText)")
                    .accessibilityValue(isSelected ? "選択中" : "未選択")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])

                    // 区切り線（最後以外）
                    if index < displayMobilityTypes.count - 1 {
                        Divider()
                            .padding(.leading, 74)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
        }
    }

    // ラジオボタンUI
    private func radioButton(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(isSelected ? Color(hex: 0x007AFF) : Color(.systemGray3), lineWidth: 2)
                .frame(width: 24, height: 24)

            if isSelected {
                Circle()
                    .fill(Color(hex: 0x007AFF))
                    .frame(width: 14, height: 14)
            }
        }
        .accessibilityHidden(true)
    }

    // 移動手段ごとのカラー値
    private func mobilityColorValue(for type: MobilityType) -> UInt {
        switch type {
        case .wheelchair: return 0x007AFF
        case .stroller: return 0x5856D6
        case .cane: return 0xFF9500
        case .walk: return 0x34C759
        case .other: return 0x8E8E93
        }
    }

    // MARK: - 3. 回避したい条件セクション

    private var avoidSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("回避したい条件")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)
                .padding(.leading, 4)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(AvoidCondition.allCases) { condition in
                    let isSelected = viewModel.selectedAvoidConditions.contains(condition)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.toggleAvoidCondition(condition)
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(condition.emoji)
                                .font(.system(size: 28))

                            Text(condition.label)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.black)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            isSelected
                                ? Color(hex: 0xFFF5F5)
                                : Color.white,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    isSelected ? Color(hex: 0xFF3B30) : Color(.systemGray5),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(condition.label)
                    .accessibilityValue(isSelected ? "回避する" : "回避しない")
                }
            }
        }
    }

    // MARK: - 4. 優先したい条件セクション

    private var preferSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("優先したい条件")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)
                .padding(.leading, 4)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(PreferCondition.allCases) { condition in
                    let isSelected = viewModel.selectedPreferConditions.contains(condition)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.togglePreferCondition(condition)
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(condition.emoji)
                                .font(.system(size: 28))

                            Text(condition.label)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.black)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            isSelected
                                ? Color(hex: 0xF2FFF5)
                                : Color.white,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    isSelected ? Color(hex: 0x34C759) : Color(.systemGray5),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(condition.label)
                    .accessibilityValue(isSelected ? "希望する" : "希望しない")
                }
            }
        }
    }

    // MARK: - 5. 最大移動距離カード

    private var distanceCard: some View {
        VStack(spacing: 16) {
            // ラベル
            HStack {
                Text("最大移動距離")
                    .font(.subheadline)
                    .foregroundStyle(.black)
                Spacer()
            }

            // 大きな数字表示
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", viewModel.maxDistanceMeters / 1000))
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.black)

                Text("km")
                    .font(.system(size: 20))
                    .foregroundStyle(.black)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                AccessibilityHelpers.distanceText(meters: viewModel.maxDistanceMeters)
            )

            // スライダー + −/＋ボタン
            HStack(spacing: 16) {
                // −ボタン
                Button {
                    viewModel.maxDistanceMeters = max(100, viewModel.maxDistanceMeters - 100)
                } label: {
                    Image(systemName: "minus")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(hex: 0x007AFF))
                        .frame(width: 44, height: 44)
                        .background(Color(.systemGray5), in: Circle())
                }
                .disabled(viewModel.maxDistanceMeters <= 100)
                .accessibilityLabel("距離を100m減らす")

                Slider(
                    value: $viewModel.maxDistanceMeters,
                    in: 100...5000,
                    step: 100
                )
                .tint(Color(hex: 0x007AFF))
                .accessibilityLabel("最大移動距離")
                .accessibilityValue(
                    AccessibilityHelpers.distanceText(meters: viewModel.maxDistanceMeters)
                )

                // ＋ボタン
                Button {
                    viewModel.maxDistanceMeters = min(5000, viewModel.maxDistanceMeters + 100)
                } label: {
                    Image(systemName: "plus")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(hex: 0x007AFF))
                        .frame(width: 44, height: 44)
                        .background(Color(.systemGray5), in: Circle())
                }
                .disabled(viewModel.maxDistanceMeters >= 5000)
                .accessibilityLabel("距離を100m増やす")
            }
        }
        .padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - 6. 固定保存ボタン

    private var saveButton: some View {
        VStack(spacing: 0) {
            Divider()

            Button {
                Task {
                    await viewModel.saveProfile()
                    if viewModel.saveSucceeded {
                        showSaveAlert = true
                    }
                }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isSaving {
                        ProgressView()
                            .tint(.white)
                            .padding(.trailing, 8)
                    }
                    Text("設定を保存する")
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Spacer()
                }
                .frame(height: 56)
                .background(Color(hex: 0x007AFF), in: RoundedRectangle(cornerRadius: 16))
            }
            .disabled(viewModel.isSaving)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .accessibilityLabel("設定を保存する")
            .accessibilityHint("現在の設定内容を保存します")
        }
        .background(Color.white.opacity(0.95))
    }
}

// MARK: - Color hex初期化ヘルパー

private extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
