import SwiftUI

// プロファイル編集画面
struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    // プロファイル完了度
                    profileCompletionSection

                    // チャットから抽出されたニーズとの差分
                    if !viewModel.needsDiffItems.isEmpty {
                        needsDiffSection
                    }

                    // 移動手段
                    mobilitySection

                    // 同行者
                    companionSection

                    // 最大移動距離
                    distanceSection

                    // 回避条件
                    avoidSection

                    // 希望条件
                    preferSection

                    // バリデーション警告
                    if let warning = viewModel.validationErrors["avoidWarning"] {
                        validationWarningSection(message: warning)
                    }

                    // 保存ボタン
                    saveSection

                    // エラー表示
                    if let error = viewModel.errorMessage {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                                .accessibilityLabel("エラー: \(error)")
                        }
                    }

                    // アプリ情報
                    appInfoSection
                }

                // 保存成功オーバーレイ
                if viewModel.showSaveSuccessOverlay {
                    saveSuccessOverlay
                }
            }
            .navigationTitle("プロファイル")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadProfile()
            }
        }
    }

    // MARK: - プロファイル完了度セクション

    private var profileCompletionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("プロファイル完了度")
                        .font(.headline)

                    Spacer()

                    Text("\(viewModel.completionPercentage)%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(completionColor)
                        .accessibilityLabel("完了度 \(viewModel.completionPercentage)パーセント")
                }

                // プログレスバー
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.systemGray5))
                            .frame(height: 12)

                        RoundedRectangle(cornerRadius: 6)
                            .fill(completionColor)
                            .frame(
                                width: geometry.size.width * CGFloat(viewModel.completionPercentage) / 100,
                                height: 12
                            )
                            .animation(.easeInOut(duration: 0.5), value: viewModel.completionPercentage)
                    }
                }
                .frame(height: 12)
                .accessibilityHidden(true)

                Text(viewModel.completionAdvice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // 完了度に応じたカラー
    private var completionColor: Color {
        switch viewModel.completionPercentage {
        case 80...100: return AppColors.success
        case 40..<80: return AppColors.warningText
        default: return AppColors.error
        }
    }

    // MARK: - チャット抽出ニーズ差分セクション

    private var needsDiffSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.needsDiffItems) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.iconName)
                            .foregroundStyle(AppColors.infoText)
                            .frame(width: 24)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.field)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            HStack(spacing: 4) {
                                Text(item.currentValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .strikethrough()

                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)

                                Text(item.suggestedValue)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.infoText)
                                    .fontWeight(.medium)
                            }
                        }

                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(item.field): 現在の値 \(item.currentValue)、提案値 \(item.suggestedValue)")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.applyExtractedNeeds()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Label("提案をすべて反映する", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .ensureMinimumTapTarget()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.accent)
                .accessibilityLabel("チャットの提案をプロファイルに反映")
                .accessibilityHint("タップするとチャットから抽出されたニーズでプロファイルを更新します")
            }
            .padding(.vertical, 4)
        } header: {
            Label("チャットからの提案", systemImage: "sparkles")
                .foregroundStyle(AppColors.infoText)
        } footer: {
            Text("会話の中で検出されたあなたのニーズです。反映ボタンでプロファイルに取り込めます。")
                .font(.caption)
        }
    }

    // MARK: - 移動手段セクション（絵文字 + カラー付き）

    private var mobilitySection: some View {
        Section {
            ForEach(MobilityType.allCases) { type in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.mobilityType = type
                    }
                } label: {
                    HStack(spacing: 12) {
                        // 絵文字アイコン
                        Text(type.emoji)
                            .font(.title2)
                            .frame(width: 36, height: 36)
                            .accessibilityHidden(true)

                        // ラベルと説明テキスト
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.label)
                                .font(.body)
                                .foregroundStyle(AppColors.textPrimary)

                            Text(type.descriptionText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // 選択状態インジケーター
                        if viewModel.mobilityType == type {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppColors.accent)
                                .font(.title3)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        viewModel.mobilityType == type
                            ? Color.blue.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .ensureMinimumTapTarget()
                .accessibilityLabel("\(type.label) — \(type.descriptionText)")
                .accessibilityValue(viewModel.mobilityType == type ? "選択中" : "未選択")
                .accessibilityAddTraits(viewModel.mobilityType == type ? .isSelected : [])
            }
        } header: {
            sectionHeader(title: "移動手段", systemImage: "figure.walk")
        } footer: {
            Text("ルート検索時に段差・勾配などの条件を最適化するために使用します")
                .font(.caption)
        }
    }

    // MARK: - 同行者セクション

    private var companionSection: some View {
        Section {
            ForEach(Companion.allCases) { companion in
                Toggle(isOn: Binding(
                    get: { viewModel.selectedCompanions.contains(companion) },
                    set: { _ in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.toggleCompanion(companion)
                        }
                    }
                )) {
                    HStack(spacing: 12) {
                        Image(systemName: companion.iconName)
                            .font(.title3)
                            .foregroundStyle(
                                viewModel.selectedCompanions.contains(companion)
                                    ? AppColors.accent : .secondary
                            )
                            .frame(width: 32, height: 32)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(companion.label)
                                .font(.body)

                            Text(companion.descriptionText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .ensureMinimumTapTarget()
                .accessibilityLabel("\(companion.label) — \(companion.descriptionText)")
                .accessibilityValue(viewModel.selectedCompanions.contains(companion) ? "オン" : "オフ")
            }
        } header: {
            sectionHeader(title: "同行者", systemImage: "person.2")
        } footer: {
            Text("同行者に合わせて歩行ペースや必要な設備の条件を調整します")
                .font(.caption)
        }
    }

    // MARK: - 最大移動距離セクション

    private var distanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // 距離表示（メイン）
                HStack(alignment: .firstTextBaseline) {
                    Text(AccessibilityHelpers.distanceText(meters: viewModel.maxDistanceMeters))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColors.textPrimary)

                    Text("—")
                        .foregroundStyle(.secondary)

                    Text(AccessibilityHelpers.distanceCategory(meters: viewModel.maxDistanceMeters))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(AccessibilityHelpers.distanceText(meters: viewModel.maxDistanceMeters))、\(AccessibilityHelpers.distanceCategory(meters: viewModel.maxDistanceMeters))"
                )

                // スライダー + ステッパーボタン
                HStack(spacing: 12) {
                    // -ボタン
                    Button {
                        viewModel.maxDistanceMeters = max(100, viewModel.maxDistanceMeters - 100)
                    } label: {
                        Image(systemName: "minus")
                            .font(.body)
                            .fontWeight(.bold)
                            .frame(width: 36, height: 36)
                            .background(Color(.systemGray5), in: Circle())
                    }
                    .disabled(viewModel.maxDistanceMeters <= 100)
                    .accessibilityLabel("距離を100m減らす")

                    Slider(
                        value: $viewModel.maxDistanceMeters,
                        in: 100...5000,
                        step: 100
                    )
                    .accessibilityLabel("最大移動距離")
                    .accessibilityValue(
                        AccessibilityHelpers.distanceText(meters: viewModel.maxDistanceMeters)
                    )

                    // +ボタン
                    Button {
                        viewModel.maxDistanceMeters = min(5000, viewModel.maxDistanceMeters + 100)
                    } label: {
                        Image(systemName: "plus")
                            .font(.body)
                            .fontWeight(.bold)
                            .frame(width: 36, height: 36)
                            .background(Color(.systemGray5), in: Circle())
                    }
                    .disabled(viewModel.maxDistanceMeters >= 5000)
                    .accessibilityLabel("距離を100m増やす")
                }

                // 目安マーカー
                HStack {
                    distanceMarker(label: "300m", sublabel: "短距離")
                    Spacer()
                    distanceMarker(label: "1km", sublabel: "中距離")
                    Spacer()
                    distanceMarker(label: "3km", sublabel: "長距離")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
        } header: {
            sectionHeader(title: "最大移動距離", systemImage: "map")
        } footer: {
            Text("一度に移動できる最大距離です。ルートの候補をこの距離内で絞り込みます")
                .font(.caption)
        }
    }

    // 距離マーカーの表示用ヘルパー
    private func distanceMarker(label: String, sublabel: String) -> some View {
        VStack(spacing: 2) {
            Text("|")
                .font(.caption2)
                .foregroundStyle(Color(.systemGray3))
            Text(label)
                .fontWeight(.medium)
            Text(sublabel)
        }
    }

    // MARK: - 回避条件セクション

    private var avoidSection: some View {
        Section {
            // グリッド表示（Expo版に合わせる）
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(AvoidCondition.allCases) { condition in
                    let isSelected = viewModel.selectedAvoidConditions.contains(condition)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.toggleAvoidCondition(condition)
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(condition.emoji)
                                .font(.title2)
                            Text(condition.label)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            isSelected ? Color.red.opacity(0.1) : Color(.systemGray6),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.red.opacity(0.5) : Color.clear, lineWidth: 2)
                        )
                        .foregroundStyle(isSelected ? .red : .primary)
                    }
                    .accessibilityLabel("\(condition.label)")
                    .accessibilityValue(isSelected ? "回避する" : "回避しない")
                }
            }
        } header: {
            sectionHeader(title: "回避したい条件", systemImage: "exclamationmark.triangle")
        } footer: {
            Text("ルート検索時にこれらの条件を含むルートを避けて提案します")
                .font(.caption)
        }
    }

    // MARK: - 希望条件セクション

    private var preferSection: some View {
        Section {
            // グリッド表示（Expo版に合わせる）
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(PreferCondition.allCases) { condition in
                    let isSelected = viewModel.selectedPreferConditions.contains(condition)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.togglePreferCondition(condition)
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(condition.emoji)
                                .font(.title2)
                            Text(condition.label)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            isSelected ? Color.green.opacity(0.1) : Color(.systemGray6),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2)
                        )
                        .foregroundStyle(isSelected ? .green : .primary)
                    }
                    .accessibilityLabel("\(condition.label)")
                    .accessibilityValue(isSelected ? "希望する" : "希望しない")
                }
            }
        } header: {
            sectionHeader(title: "希望条件", systemImage: "star")
        } footer: {
            Text("これらの設備や条件があるルートを優先的に提案します")
                .font(.caption)
        }
    }

    // MARK: - バリデーション警告セクション

    private func validationWarningSection(message: String) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColors.warningText)
                    .accessibilityHidden(true)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.warningText)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("警告: \(message)")
        }
    }

    // MARK: - 保存ボタンセクション

    private var saveSection: some View {
        Section {
            Button {
                Task {
                    await viewModel.saveProfile()
                }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isSaving {
                        ProgressView()
                            .padding(.trailing, 8)
                    }
                    Text("保存する")
                        .fontWeight(.bold)
                    Spacer()
                }
                .ensureMinimumTapTarget()
            }
            .disabled(viewModel.isSaving)
            .accessibilityLabel("プロファイルを保存")
            .accessibilityHint("現在の設定内容を保存します")
        }
    }

    // MARK: - 保存成功オーバーレイ

    private var saveSuccessOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppColors.success)
                .symbolEffect(.bounce, value: viewModel.showSaveSuccessOverlay)

            Text("保存しました")
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: AppColors.cardShadow, radius: 16)
        )
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.showSaveSuccessOverlay)
        .accessibilityLabel("保存が完了しました")
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: - アプリ情報セクション

    private var appInfoSection: some View {
        Section {
            HStack {
                Text("バージョン")
                Spacer()
                Text(AppConfig.displayVersion)
                    .foregroundStyle(.secondary)
            }
            if AppConfig.isDebug {
                HStack {
                    Text("環境")
                    Spacer()
                    Text(AppConfig.environment.displayName)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("アプリ情報")
        }
    }

    // MARK: - 共通ヘルパー

    // セクションヘッダー（アイコン付き）
    private func sectionHeader(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
    }
}
