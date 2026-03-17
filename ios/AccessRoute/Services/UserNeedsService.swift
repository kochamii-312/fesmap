import Foundation

// 統合ユーザーニーズ
struct UnifiedUserNeeds {
    var mobilityType: MobilityType
    var companions: [Companion]
    var maxDistanceMeters: Double
    var avoidConditions: [AvoidCondition]
    var preferConditions: [PreferCondition]
    var destination: String?
}

// プロフィール + チャット抽出ニーズの統合管理
enum UserNeedsService {

    // プロフィール設定とチャット抽出ニーズを統合して返す
    static func loadUnifiedNeeds() -> UnifiedUserNeeds {
        let defaults = UserDefaults.standard

        // プロフィールから取得
        let mobilityType = MobilityType(
            rawValue: defaults.string(forKey: StorageKeys.mobilityType) ?? ""
        ) ?? .walk

        let companions = (defaults.stringArray(forKey: StorageKeys.companions) ?? [])
            .compactMap { Companion(rawValue: $0) }

        let maxDistance = defaults.double(forKey: StorageKeys.maxDistance)
        let avoidConditions = (defaults.stringArray(forKey: StorageKeys.avoidConditions) ?? [])
            .compactMap { AvoidCondition(rawValue: $0) }
        let preferConditions = (defaults.stringArray(forKey: StorageKeys.preferConditions) ?? [])
            .compactMap { PreferCondition(rawValue: $0) }

        // チャットから抽出されたニーズを統合
        var needs = UnifiedUserNeeds(
            mobilityType: mobilityType,
            companions: companions,
            maxDistanceMeters: maxDistance > 0 ? maxDistance : 1000,
            avoidConditions: avoidConditions,
            preferConditions: preferConditions,
            destination: nil
        )

        // チャットニーズで上書き/追加
        if let chatData = defaults.dictionary(forKey: StorageKeys.chatExtractedNeeds) {
            if let chatMobility = chatData["mobilityType"] as? String,
               let type = MobilityType(rawValue: chatMobility) {
                needs.mobilityType = type
            }

            if let chatCompanions = chatData["companions"] as? [String] {
                let additional = chatCompanions.compactMap { Companion(rawValue: $0) }
                needs.companions = Array(Set(needs.companions + additional))
            }

            if let chatAvoid = chatData["avoidConditions"] as? [String] {
                let additional = chatAvoid.compactMap { AvoidCondition(rawValue: $0) }
                needs.avoidConditions = Array(Set(needs.avoidConditions + additional))
            }

            if let chatPrefer = chatData["preferConditions"] as? [String] {
                let additional = chatPrefer.compactMap { PreferCondition(rawValue: $0) }
                needs.preferConditions = Array(Set(needs.preferConditions + additional))
            }

            if let dest = chatData["destination"] as? String {
                needs.destination = dest
            }
        }

        return needs
    }

    // チャットから抽出したニーズを保存
    static func saveChatNeeds(_ needs: [String: Any]) {
        UserDefaults.standard.set(needs, forKey: StorageKeys.chatExtractedNeeds)
    }

    // チャットニーズをクリア
    static func clearChatNeeds() {
        UserDefaults.standard.removeObject(forKey: StorageKeys.chatExtractedNeeds)
    }
}
