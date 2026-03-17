import Foundation
import Combine

// プロファイル編集画面のViewModel
@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var mobilityType: MobilityType = .walk
    @Published var selectedCompanions: Set<Companion> = []
    @Published var maxDistanceMeters: Double = 1000
    @Published var selectedAvoidConditions: Set<AvoidCondition> = []
    @Published var selectedPreferConditions: Set<PreferCondition> = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var saveSucceeded = false

    // バリデーションエラー（セクションごと）
    @Published var validationErrors: [String: String] = [:]

    // チャットから抽出されたニーズとの差分
    @Published var extractedNeeds: ExtractedNeeds?
    @Published var needsDiffItems: [NeedsDiffItem] = []

    // 保存成功アニメーション用
    @Published var showSaveSuccessOverlay = false

    // MARK: - プロファイル完了度

    // プロファイルの入力完了度（0〜100%）
    // Expo版と同じ計算式: 移動手段40% + 回避条件30% + 希望条件30%
    var completionPercentage: Int {
        var percentage = 0

        // 移動手段: デフォルト(.walk)以外なら40%、.walkなら20%
        if mobilityType != .walk {
            percentage += 40
        } else {
            percentage += 20
        }

        // 回避条件が1つ以上選択されていれば30%
        if !selectedAvoidConditions.isEmpty {
            percentage += 30
        }

        // 希望条件が1つ以上選択されていれば30%
        if !selectedPreferConditions.isEmpty {
            percentage += 30
        }

        return percentage
    }

    // 完了度に応じたアドバイステキスト
    var completionAdvice: String {
        switch completionPercentage {
        case 100:
            return "すべての項目が設定されています"
        case 60..<100:
            return "あと少しで完了です。未設定の項目を入力するとより正確なルート提案ができます"
        case 20..<60:
            return "プロファイルを充実させると、よりあなたに合ったルートを提案できます"
        default:
            return "プロファイルを設定して、最適なルート提案を受けましょう"
        }
    }

    // MARK: - プロファイル読み込み

    func loadProfile() async {
        isLoading = true
        errorMessage = nil

        // TODO: Firebase Auth トークン取得後に実装
        // do {
        //     let token = try await AuthService.shared.getToken()
        //     let profile = try await APIService.shared.getProfile(token: token)
        //     mobilityType = profile.mobilityType
        //     selectedCompanions = Set(profile.companions)
        //     maxDistanceMeters = profile.maxDistanceMeters
        //     selectedAvoidConditions = Set(profile.avoidConditions)
        //     selectedPreferConditions = Set(profile.preferConditions)
        // } catch {
        //     errorMessage = error.localizedDescription
        // }

        // ローカル保存から復元
        loadFromUserDefaults()

        // チャットから抽出されたニーズを読み込み差分を計算
        loadExtractedNeeds()

        isLoading = false
    }

    // MARK: - プロファイル保存

    func saveProfile() async {
        isSaving = true
        errorMessage = nil
        saveSucceeded = false
        validationErrors = [:]

        // バリデーション実行
        guard validateProfile() else {
            isSaving = false
            return
        }

        // TODO: Firebase Auth トークン取得後に実装
        // let input = buildProfileInput()
        // do {
        //     let token = try await AuthService.shared.getToken()
        //     _ = try await APIService.shared.saveProfile(input: input, token: token)
        //     saveSucceeded = true
        // } catch {
        //     errorMessage = error.localizedDescription
        // }

        // ローカル保存
        saveToUserDefaults()
        saveSucceeded = true
        isSaving = false

        // 保存成功オーバーレイを表示（自動で閉じる）
        showSaveSuccessOverlay = true
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒後に非表示
        showSaveSuccessOverlay = false
    }

    // MARK: - バリデーション

    // 入力値の妥当性を検証する（エラーがあれば validationErrors に格納）
    private func validateProfile() -> Bool {
        var errors: [String: String] = [:]

        // 最大移動距離の範囲チェック
        if maxDistanceMeters < 100 || maxDistanceMeters > 5000 {
            errors["maxDistance"] = "移動距離は100m〜5kmの範囲で設定してください"
        }

        // 車椅子利用者が階段回避を設定していない場合の警告（エラーではなく警告）
        if mobilityType == .wheelchair && !selectedAvoidConditions.contains(.stairs) {
            errors["avoidWarning"] = "車椅子をご利用の場合、「階段」の回避をおすすめします"
        }

        validationErrors = errors

        // 警告（avoidWarning）は保存を妨げない
        let blockingErrors = errors.filter { $0.key != "avoidWarning" }
        if !blockingErrors.isEmpty {
            errorMessage = blockingErrors.values.first
            return false
        }

        return true
    }

    // MARK: - トグル操作

    // 同行者トグル
    func toggleCompanion(_ companion: Companion) {
        if selectedCompanions.contains(companion) {
            selectedCompanions.remove(companion)
        } else {
            selectedCompanions.insert(companion)
        }
    }

    // 回避条件トグル
    func toggleAvoidCondition(_ condition: AvoidCondition) {
        if selectedAvoidConditions.contains(condition) {
            selectedAvoidConditions.remove(condition)
        } else {
            selectedAvoidConditions.insert(condition)
        }
    }

    // 希望条件トグル
    func togglePreferCondition(_ condition: PreferCondition) {
        if selectedPreferConditions.contains(condition) {
            selectedPreferConditions.remove(condition)
        } else {
            selectedPreferConditions.insert(condition)
        }
    }

    // MARK: - チャット抽出ニーズとの差分

    // チャットから抽出されたニーズを適用する
    func applyExtractedNeeds() {
        guard let needs = extractedNeeds else { return }

        if let mobility = needs.mobilityType {
            mobilityType = mobility
        }
        if let companions = needs.companions {
            selectedCompanions = Set(companions)
        }
        if let distance = needs.maxDistanceMeters {
            maxDistanceMeters = distance
        }
        if let avoids = needs.avoidConditions {
            selectedAvoidConditions = Set(avoids)
        }
        if let prefers = needs.preferConditions {
            selectedPreferConditions = Set(prefers)
        }

        // 差分をクリア
        needsDiffItems = []
    }

    // チャット抽出ニーズとの差分を計算する
    func calculateNeedsDiff() {
        guard let needs = extractedNeeds else {
            needsDiffItems = []
            return
        }

        var diffs: [NeedsDiffItem] = []

        if let mobility = needs.mobilityType, mobility != mobilityType {
            diffs.append(NeedsDiffItem(
                field: "移動手段",
                currentValue: mobilityType.label,
                suggestedValue: mobility.label,
                iconName: "figure.roll"
            ))
        }

        if let companions = needs.companions {
            let currentLabels = selectedCompanions.map(\.label).sorted().joined(separator: "、")
            let suggestedLabels = companions.map(\.label).sorted().joined(separator: "、")
            if currentLabels != suggestedLabels {
                diffs.append(NeedsDiffItem(
                    field: "同行者",
                    currentValue: currentLabels.isEmpty ? "未設定" : currentLabels,
                    suggestedValue: suggestedLabels.isEmpty ? "なし" : suggestedLabels,
                    iconName: "person.2"
                ))
            }
        }

        if let distance = needs.maxDistanceMeters, distance != maxDistanceMeters {
            diffs.append(NeedsDiffItem(
                field: "最大移動距離",
                currentValue: AccessibilityHelpers.distanceText(meters: maxDistanceMeters),
                suggestedValue: AccessibilityHelpers.distanceText(meters: distance),
                iconName: "map"
            ))
        }

        if let avoids = needs.avoidConditions {
            let currentLabels = selectedAvoidConditions.map(\.label).sorted().joined(separator: "、")
            let suggestedLabels = avoids.map(\.label).sorted().joined(separator: "、")
            if currentLabels != suggestedLabels {
                diffs.append(NeedsDiffItem(
                    field: "回避条件",
                    currentValue: currentLabels.isEmpty ? "未設定" : currentLabels,
                    suggestedValue: suggestedLabels.isEmpty ? "なし" : suggestedLabels,
                    iconName: "exclamationmark.triangle"
                ))
            }
        }

        if let prefers = needs.preferConditions {
            let currentLabels = selectedPreferConditions.map(\.label).sorted().joined(separator: "、")
            let suggestedLabels = prefers.map(\.label).sorted().joined(separator: "、")
            if currentLabels != suggestedLabels {
                diffs.append(NeedsDiffItem(
                    field: "希望条件",
                    currentValue: currentLabels.isEmpty ? "未設定" : currentLabels,
                    suggestedValue: suggestedLabels.isEmpty ? "なし" : suggestedLabels,
                    iconName: "star"
                ))
            }
        }

        needsDiffItems = diffs
    }

    // MARK: - UserProfileInput生成

    func buildProfileInput() -> UserProfileInput {
        UserProfileInput(
            mobilityType: mobilityType,
            companions: Array(selectedCompanions),
            maxDistanceMeters: maxDistanceMeters,
            avoidConditions: Array(selectedAvoidConditions),
            preferConditions: Array(selectedPreferConditions)
        )
    }

    // MARK: - ローカル保存

    private func saveToUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(mobilityType.rawValue, forKey: StorageKeys.mobilityType)
        defaults.set(selectedCompanions.map(\.rawValue), forKey: StorageKeys.companions)
        defaults.set(maxDistanceMeters, forKey: StorageKeys.maxDistance)
        defaults.set(selectedAvoidConditions.map(\.rawValue), forKey: StorageKeys.avoidConditions)
        defaults.set(selectedPreferConditions.map(\.rawValue), forKey: StorageKeys.preferConditions)
    }

    private func loadFromUserDefaults() {
        let defaults = UserDefaults.standard
        if let rawMobility = defaults.string(forKey: StorageKeys.mobilityType),
           let mobility = MobilityType(rawValue: rawMobility) {
            mobilityType = mobility
        }
        if let rawCompanions = defaults.stringArray(forKey: StorageKeys.companions) {
            selectedCompanions = Set(rawCompanions.compactMap { Companion(rawValue: $0) })
        }
        let distance = defaults.double(forKey: StorageKeys.maxDistance)
        if distance > 0 {
            maxDistanceMeters = distance
        }
        if let rawAvoid = defaults.stringArray(forKey: StorageKeys.avoidConditions) {
            selectedAvoidConditions = Set(rawAvoid.compactMap { AvoidCondition(rawValue: $0) })
        }
        if let rawPrefer = defaults.stringArray(forKey: StorageKeys.preferConditions) {
            selectedPreferConditions = Set(rawPrefer.compactMap { PreferCondition(rawValue: $0) })
        }
    }

    // チャットから抽出されたニーズをUserDefaultsから読み込む
    private func loadExtractedNeeds() {
        // TODO: 実際にはチャット画面から共有されたExtractedNeedsを読み込む
        // 現在はUserDefaultsに保存されたJSON文字列から復元する実装
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: StorageKeys.chatExtractedNeeds),
           let needs = try? JSONDecoder().decode(ExtractedNeeds.self, from: data) {
            if needs.hasAnyNeeds {
                extractedNeeds = needs
                calculateNeedsDiff()
            }
        }
    }
}

// MARK: - チャット抽出ニーズ差分表示用モデル

// プロファイルとチャット抽出ニーズの差分を表す項目
struct NeedsDiffItem: Identifiable {
    let id = UUID()
    let field: String          // 項目名
    let currentValue: String   // 現在のプロファイル値
    let suggestedValue: String // チャットから提案された値
    let iconName: String       // SF Symbolsアイコン名
}
