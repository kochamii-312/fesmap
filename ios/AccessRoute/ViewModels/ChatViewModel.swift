import Foundation

// チャット画面のViewModel
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isTyping = false
    @Published var errorMessage: String?
    @Published var extractedNeeds: ExtractedNeeds?
    @Published var suggestedAction: SuggestedAction?
    @Published var shouldNavigateToRoute = false
    @Published var shouldNavigateToSpots = false
    @Published var followUpSuggestions: [String] = []

    // MARK: - 会話フェーズ管理

    /// 会話の進行状況を追跡し、返答のトーンを変化させる
    private enum ConversationPhase {
        case greeting        // 初回挨拶
        case gathering       // 情報収集中
        case proposing       // 提案フェーズ
    }

    /// 現在の会話フェーズを判定
    private var conversationPhase: ConversationPhase {
        let userMessageCount = messages.filter { $0.role == .user }.count
        if userMessageCount <= 1 {
            return .greeting
        } else if extractedNeeds?.hasAnyNeeds == true {
            return .proposing
        } else {
            return .gathering
        }
    }

    // MARK: - 駅名・地名辞書（キーワードマッチ用）

    /// 主要な駅名・地名キーワード（マッチしたら目的地として認識）
    private static let stationKeywords: [String: String] = [
        "東京駅": "東京駅",
        "新宿駅": "新宿駅",
        "渋谷駅": "渋谷駅",
        "池袋駅": "池袋駅",
        "上野駅": "上野駅",
        "品川駅": "品川駅",
        "横浜駅": "横浜駅",
        "大阪駅": "大阪駅",
        "梅田駅": "梅田駅",
        "京都駅": "京都駅",
        "名古屋駅": "名古屋駅",
        "博多駅": "博多駅",
        "札幌駅": "札幌駅",
        "仙台駅": "仙台駅",
        "広島駅": "広島駅",
        "天王寺駅": "天王寺駅",
        "難波駅": "難波駅",
        "三宮駅": "三宮駅",
    ]

    /// 主要なランドマーク・施設名
    private static let landmarkKeywords: [String: String] = [
        "東京タワー": "東京タワー",
        "スカイツリー": "東京スカイツリー",
        "ディズニー": "東京ディズニーリゾート",
        "USJ": "ユニバーサル・スタジオ・ジャパン",
        "ユニバ": "ユニバーサル・スタジオ・ジャパン",
        "浅草寺": "浅草寺",
        "浅草": "浅草エリア",
        "原宿": "原宿エリア",
        "秋葉原": "秋葉原エリア",
        "お台場": "お台場エリア",
        "空港": "空港",
        "羽田": "羽田空港",
        "成田": "成田空港",
        "関空": "関西国際空港",
        "動物園": "動物園",
        "水族館": "水族館",
        "美術館": "美術館",
        "博物館": "博物館",
        "公園": "公園",
        "病院": "病院",
        "ショッピングモール": "ショッピングモール",
        "デパート": "デパート",
        "百貨店": "百貨店",
    ]

    // MARK: - メッセージ送信

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // ユーザーメッセージを追加
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""
        errorMessage = nil
        suggestedAction = nil
        isTyping = true

        // 会話履歴を構築
        let history = messages.map { $0.asDictionary }

        // TODO: Firebase Auth トークン取得後に実装
        // do {
        //     let token = try await AuthService.shared.getToken()
        //     // SSEストリーミング対応
        //     let stream = try await APIService.shared.streamChatMessage(
        //         userId: "current_user",
        //         message: text,
        //         conversationHistory: history,
        //         token: token
        //     )
        //     var assistantMessage = ChatMessage(role: .assistant, content: "")
        //     messages.append(assistantMessage)
        //     let assistantIndex = messages.count - 1
        //     for try await chunk in stream {
        //         messages[assistantIndex].content += chunk
        //     }
        //     isTyping = false
        //     // 非ストリーミングのニーズ抽出
        //     let needsResponse = try await APIService.shared.extractNeeds(
        //         userId: "current_user",
        //         conversationHistory: messages.map { $0.asDictionary },
        //         token: token
        //     )
        //     if needsResponse.needs.hasAnyNeeds {
        //         extractedNeeds = needsResponse.needs
        //     }
        // } catch {
        //     isTyping = false
        //     errorMessage = error.localizedDescription
        // }

        // モックレスポンスで表示確認
        await mockResponse(for: text, history: history)
    }

    // 会話履歴のリセット
    func resetConversation() {
        messages.removeAll()
        extractedNeeds = nil
        suggestedAction = nil
        errorMessage = nil
        followUpSuggestions = []
        UserNeedsService.clearChatNeeds()
    }

    // アクションボタンタップ処理
    func handleAction(_ action: SuggestedAction) {
        switch action {
        case .searchRoute:
            shouldNavigateToRoute = true
        case .showSpots:
            shouldNavigateToSpots = true
        case .askMore:
            break
        }
    }

    // MARK: - モックレスポンス

    private func mockResponse(for userText: String, history: [[String: String]]) async {
        // AIの応答を遅延してシミュレーション
        let assistantMessage = ChatMessage(role: .assistant, content: "")
        messages.append(assistantMessage)
        let assistantIndex = messages.count - 1

        // ストリーミングをシミュレーション（文字単位で表示）
        let mockReply = generateMockReply(for: userText)
        for char in mockReply {
            try? await Task.sleep(nanoseconds: 30_000_000) // 30ms
            messages[assistantIndex].content += String(char)
        }

        isTyping = false

        // モックのニーズ抽出とアクション提案
        applyMockExtraction(for: userText)
    }

    // MARK: - モックレスポンス生成（キーワードマッチング）

    /// ユーザーの入力テキストからキーワードを解析し、文脈に応じた返答を生成する
    private func generateMockReply(for text: String) -> String {
        let lowered = text.lowercased()

        // 検出されたコンテキストを収集
        let detectedMobility = detectMobilityKeywords(in: lowered)
        let detectedDestination = detectDestination(in: lowered)
        let detectedSpotType = detectSpotType(in: lowered)
        let detectedCompanion = detectCompanionKeywords(in: lowered)
        let detectedCondition = detectConditionKeywords(in: lowered)
        let isGreeting = detectGreeting(in: lowered)
        let isThanks = detectThanks(in: lowered)
        let isQuestion = detectQuestion(in: lowered)

        // 感謝・お礼への応答
        if isThanks {
            return thankYouReply()
        }

        // 挨拶への応答（他に具体的なキーワードがない場合）
        if isGreeting && detectedMobility == nil && detectedDestination == nil && detectedSpotType == nil {
            return greetingReply()
        }

        // 複合キーワードマッチ: 移動手段 + 目的地
        if let mobility = detectedMobility, let destination = detectedDestination {
            return mobilityWithDestinationReply(
                mobility: mobility,
                destination: destination,
                condition: detectedCondition,
                companion: detectedCompanion
            )
        }

        // 複合キーワードマッチ: 同行者 + 目的地
        if let companion = detectedCompanion, let destination = detectedDestination {
            return companionWithDestinationReply(companion: companion, destination: destination)
        }

        // 移動手段のみ言及
        if let mobility = detectedMobility {
            return mobilityOnlyReply(mobility: mobility, hasQuestion: isQuestion)
        }

        // 目的地のみ言及
        if let destination = detectedDestination {
            return destinationOnlyReply(destination: destination)
        }

        // スポット検索系
        if let spotType = detectedSpotType {
            return spotSearchReply(spotType: spotType, condition: detectedCondition)
        }

        // 同行者のみ言及
        if let companion = detectedCompanion {
            return companionOnlyReply(companion: companion)
        }

        // 条件のみ言及（回避条件・希望条件）
        if let condition = detectedCondition {
            return conditionOnlyReply(condition: condition)
        }

        // 距離・時間に関する質問
        if detectDistanceQuery(in: lowered) {
            return distanceReply()
        }

        // 天気・天候に関する質問
        if detectWeatherQuery(in: lowered) {
            return weatherReply()
        }

        // バリアフリー全般の質問
        if detectBarrierFreeQuery(in: lowered) {
            return barrierFreeGeneralReply()
        }

        // フェーズに応じたデフォルト返答
        return defaultReply()
    }

    // MARK: - キーワード検出ヘルパー

    /// 移動手段キーワードの検出
    private func detectMobilityKeywords(in text: String) -> MobilityType? {
        if text.contains("車椅子") || text.contains("車いす") || text.contains("くるまいす")
            || text.contains("wheelchair")
        {
            return .wheelchair
        }
        if text.contains("ベビーカー") || text.contains("乳母車") || text.contains("バギー")
            || text.contains("stroller")
        {
            return .stroller
        }
        if text.contains("杖") || text.contains("つえ") || text.contains("ステッキ") || text.contains("cane") {
            return .cane
        }
        if text.contains("歩き") || text.contains("徒歩") || text.contains("walking") {
            return .walk
        }
        return nil
    }

    /// 目的地キーワードの検出（駅名・ランドマーク）
    private func detectDestination(in text: String) -> String? {
        // 駅名マッチ
        for (keyword, name) in Self.stationKeywords {
            if text.contains(keyword) || text.contains(keyword.replacingOccurrences(of: "駅", with: "")) {
                return name
            }
        }
        // ランドマークマッチ
        for (keyword, name) in Self.landmarkKeywords {
            if text.contains(keyword.lowercased()) {
                return name
            }
        }
        // 「〜に行きたい」「〜まで」パターンから抽出を試みる
        // （簡易的な正規表現マッチ）
        let destinationPatterns = [
            "(.+?)に行きたい",
            "(.+?)まで",
            "(.+?)への",
            "(.+?)に向かいたい",
            "(.+?)へ行く",
        ]
        for pattern in destinationPatterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                let candidate = String(text[match]).replacingOccurrences(
                    of: "(に行きたい|まで|への|に向かいたい|へ行く)", with: "", options: .regularExpression
                )
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                // 短すぎるものや移動手段キーワードは除外
                if trimmed.count >= 2 && trimmed.count <= 20
                    && !["車椅子", "ベビーカー", "杖", "徒歩"].contains(trimmed)
                {
                    return trimmed
                }
            }
        }
        return nil
    }

    /// スポット種別キーワードの検出
    private func detectSpotType(in text: String) -> String? {
        if text.contains("トイレ") || text.contains("お手洗い") || text.contains("化粧室") {
            return "バリアフリートイレ"
        }
        if text.contains("休憩") || text.contains("ベンチ") || text.contains("座れる") {
            return "休憩所"
        }
        if text.contains("エレベーター") || text.contains("エレベータ") {
            return "エレベーター"
        }
        if text.contains("スロープ") || text.contains("傾斜路") {
            return "スロープ"
        }
        if text.contains("授乳") || text.contains("おむつ") || text.contains("オムツ")
            || text.contains("ベビールーム")
        {
            return "授乳室・おむつ替え台"
        }
        if text.contains("駐車") || text.contains("パーキング") {
            return "障がい者用駐車場"
        }
        if text.contains("レストラン") || text.contains("食事") || text.contains("カフェ")
            || text.contains("ご飯")
        {
            return "バリアフリー対応飲食店"
        }
        if text.contains("ホテル") || text.contains("宿泊") || text.contains("泊まる") {
            return "バリアフリー対応宿泊施設"
        }
        if text.contains("スポット") || text.contains("施設") || text.contains("場所") {
            return "バリアフリースポット"
        }
        return nil
    }

    /// 同行者キーワードの検出
    private func detectCompanionKeywords(in text: String) -> Companion? {
        if text.contains("子ども") || text.contains("子供") || text.contains("こども")
            || text.contains("幼児") || text.contains("赤ちゃん") || text.contains("乳幼児")
            || text.contains("キッズ")
        {
            return .child
        }
        if text.contains("高齢") || text.contains("お年寄り") || text.contains("おじいちゃん")
            || text.contains("おばあちゃん") || text.contains("祖父") || text.contains("祖母")
            || text.contains("シニア") || text.contains("年配")
        {
            return .elderly
        }
        if text.contains("障がい") || text.contains("障害") || text.contains("ハンディキャップ")
            || text.contains("身体が不自由")
        {
            return .disability
        }
        return nil
    }

    /// 回避・希望条件キーワードの検出
    private struct DetectedCondition {
        var avoidConditions: [AvoidCondition]
        var preferConditions: [PreferCondition]
    }

    private func detectConditionKeywords(in text: String) -> DetectedCondition? {
        var avoids: [AvoidCondition] = []
        var prefers: [PreferCondition] = []

        // 回避条件の検出
        if text.contains("階段") || text.contains("段差") || text.contains("ステップ") {
            avoids.append(.stairs)
        }
        if text.contains("坂") || text.contains("急な") || text.contains("傾斜") || text.contains("登り") {
            avoids.append(.slope)
        }
        if text.contains("混雑") || text.contains("人混み") || text.contains("人ごみ")
            || text.contains("混んでる") || text.contains("混む")
        {
            avoids.append(.crowd)
        }
        if text.contains("暗い") || text.contains("夜道") || text.contains("街灯") {
            avoids.append(.dark)
        }

        // 希望条件の検出
        if text.contains("トイレ") || text.contains("お手洗い") {
            prefers.append(.restroom)
        }
        if text.contains("休憩") || text.contains("ベンチ") || text.contains("座りたい")
            || text.contains("休める")
        {
            prefers.append(.rest_area)
        }
        if text.contains("屋根") || text.contains("雨") || text.contains("濡れない")
            || text.contains("アーケード")
        {
            prefers.append(.covered)
        }

        if avoids.isEmpty && prefers.isEmpty {
            return nil
        }
        return DetectedCondition(avoidConditions: avoids, preferConditions: prefers)
    }

    /// 挨拶の検出
    private func detectGreeting(in text: String) -> Bool {
        let greetings = [
            "こんにちは", "こんばんは", "おはよう", "はじめまして",
            "よろしく", "hello", "hi", "hey",
            "お願いします", "相談したい", "助けて", "教えて",
        ]
        return greetings.contains { text.contains($0) }
    }

    /// 感謝・お礼の検出
    private func detectThanks(in text: String) -> Bool {
        let thanks = [
            "ありがとう", "感謝", "助かり", "thank",
            "サンキュー", "了解", "わかりました", "わかった",
        ]
        return thanks.contains { text.contains($0) }
    }

    /// 質問形式の検出
    private func detectQuestion(in text: String) -> Bool {
        let questionMarkers = [
            "？", "?", "ですか", "ますか", "でしょうか",
            "かな", "どう", "どこ", "なに", "いつ",
        ]
        return questionMarkers.contains { text.contains($0) }
    }

    /// 距離・時間関連の質問検出
    private func detectDistanceQuery(in text: String) -> Bool {
        let keywords = [
            "距離", "何キロ", "何メートル", "どのくらい",
            "時間", "何分", "所要時間", "近い", "遠い",
        ]
        return keywords.contains { text.contains($0) }
    }

    /// 天気関連の質問検出
    private func detectWeatherQuery(in text: String) -> Bool {
        let keywords = ["天気", "雨", "雪", "台風", "天候"]
        return keywords.contains { text.contains($0) }
    }

    /// バリアフリー全般の質問検出
    private func detectBarrierFreeQuery(in text: String) -> Bool {
        let keywords = [
            "バリアフリー", "アクセシブル", "アクセシビリティ",
            "ユニバーサルデザイン", "段差なし", "手すり",
        ]
        return keywords.contains { text.contains($0) }
    }

    // MARK: - 返答生成ヘルパー

    /// 挨拶への返答
    private func greetingReply() -> String {
        let replies = [
            "こんにちは！AccessRouteへようこそ。バリアフリーの観点からお出かけをサポートいたします。目的地やお身体の状況を教えていただければ、最適なルートやスポットをご提案いたします。",
            "はじめまして！お出かけのお手伝いをいたします。車椅子やベビーカーでの移動、バリアフリートイレの検索など、何でもお気軽にご相談ください。",
            "ようこそ！バリアフリーなお出かけを一緒に計画しましょう。どちらへお出かけのご予定ですか？",
        ]
        return replies[messages.count % replies.count]
    }

    /// 感謝への返答
    private func thankYouReply() -> String {
        let replies = [
            "お役に立てて嬉しいです！他にも気になることがあれば、いつでもお聞きください。",
            "どういたしまして！安全で快適なお出かけになることを願っています。追加のご質問があればお気軽にどうぞ。",
            "こちらこそありがとうございます。他にお手伝いできることがあれば、お知らせください。",
        ]
        return replies[messages.count % replies.count]
    }

    /// 移動手段 + 目的地の複合返答
    private func mobilityWithDestinationReply(
        mobility: MobilityType,
        destination: String,
        condition: DetectedCondition?,
        companion: Companion?
    ) -> String {
        let mobilityLabel = mobility.label
        var reply = "\(mobilityLabel)で\(destination)へのお出かけですね。"

        // 移動手段別の具体的な情報を追加
        switch mobility {
        case .wheelchair:
            reply += "\(destination)周辺のバリアフリールートを検索いたします。エレベーターやスロープを優先した、段差のないルートをご案内いたします。"
        case .stroller:
            reply += "\(destination)周辺のベビーカーで通りやすいルートをお調べします。エレベーターの位置やおむつ替え台のある施設もあわせてご案内いたします。"
        case .cane:
            reply += "\(destination)までの歩きやすいルートを検索いたします。手すりのある通路や、段差の少ないルートを優先的にご案内いたします。"
        case .walk:
            reply += "\(destination)までの徒歩ルートを検索いたします。バリアフリー対応の安全なルートを優先的にご案内いたします。"
        case .other:
            reply += "\(destination)までのバリアフリールートを検索いたします。"
        }

        // 同行者情報がある場合の補足
        if let companion = companion {
            switch companion {
            case .child:
                reply += "お子様連れということで、キッズ向け施設の情報も添えてご案内しますね。"
            case .elderly:
                reply += "ご高齢の方とご一緒ということで、休憩所の情報も含めてご案内いたします。"
            case .disability:
                reply += "バリアフリー設備の詳細情報もあわせてお伝えいたします。"
            }
        }

        // 回避条件がある場合の補足
        if let cond = condition, !cond.avoidConditions.isEmpty {
            let avoidLabels = cond.avoidConditions.map(\.label)
            reply += "\(avoidLabels.joined(separator: "・"))を避けたルートを優先いたします。"
        }

        reply += "ルート検索を開始しますか？"
        return reply
    }

    /// 同行者 + 目的地の複合返答
    private func companionWithDestinationReply(companion: Companion, destination: String) -> String {
        switch companion {
        case .child:
            return "\(destination)へお子様連れでのお出かけですね。ベビーカーで通りやすいルートや、おむつ替え台・授乳室のある施設を含めてご案内いたします。移動手段はベビーカーでよろしいですか？"
        case .elderly:
            return "\(destination)へご高齢の方とお出かけですね。段差が少なく、途中に休憩できるベンチのあるルートを優先的にお探しします。移動手段を教えていただければ、より最適なルートをご提案いたします。"
        case .disability:
            return "\(destination)へのバリアフリールートをお探しですね。車椅子対応のエレベーターやスロープの情報を含めてご案内いたします。具体的な移動手段を教えていただけますか？"
        }
    }

    /// 移動手段のみ言及された場合の返答
    private func mobilityOnlyReply(mobility: MobilityType, hasQuestion: Bool) -> String {
        switch conversationPhase {
        case .greeting, .gathering:
            switch mobility {
            case .wheelchair:
                return "車椅子でのお出かけですね。バリアフリー対応のルートをお探しでしょうか？目的地をお教えいただければ、段差のない安全なルートをご提案いたします。"
            case .stroller:
                return "ベビーカーでの移動ですね。エレベーターやスロープを使った移動しやすいルートをお探しでしょうか？どちらへお出かけの予定ですか？"
            case .cane:
                return "杖をお使いでのお出かけですね。段差や急な坂を避けたルートをご案内できます。目的地を教えていただけますか？"
            case .walk:
                return "徒歩でのお出かけですね。バリアフリーに配慮したルートをお探しでしょうか？目的地を教えていただければ、安全なルートをご提案いたします。"
            case .other:
                return "承知いたしました。具体的な移動のご事情を教えていただければ、最適なルートをご提案いたします。目的地はお決まりですか？"
            }
        case .proposing:
            return "承知いたしました。\(mobility.label)での移動を考慮に入れて、ルートを再検索いたします。ルート検索を開始してよろしいですか？"
        }
    }

    /// 目的地のみ言及された場合の返答
    private func destinationOnlyReply(destination: String) -> String {
        switch conversationPhase {
        case .greeting:
            return "\(destination)へのお出かけですね！バリアフリーの観点からルートをご案内いたします。移動手段を教えていただけますか？（例: 車椅子、ベビーカー、杖、徒歩など）"
        case .gathering:
            return "\(destination)ですね、承知いたしました。より最適なルートをご案内するため、移動手段やお体の状況を教えていただけますか？"
        case .proposing:
            return "\(destination)への情報を追加で検索いたします。先ほどの条件を引き継いで、バリアフリールートをお調べしますね。"
        }
    }

    /// スポット検索系の返答
    private func spotSearchReply(spotType: String, condition: DetectedCondition?) -> String {
        var reply = "お近くの\(spotType)をお探しですね。"

        if let cond = condition {
            if !cond.preferConditions.isEmpty {
                let preferLabels = cond.preferConditions.map(\.label)
                reply += "\(preferLabels.joined(separator: "・"))の条件を考慮して検索いたします。"
            }
        }

        switch spotType {
        case "バリアフリートイレ":
            reply += "車椅子対応の多機能トイレや、オストメイト対応トイレの情報もあわせてご案内いたします。スポット一覧を表示しましょうか？"
        case "休憩所":
            reply += "ベンチや屋根付きの休憩所、車椅子でも利用しやすいスペースを優先的にお探しします。スポット一覧を表示しましょうか？"
        case "エレベーター":
            reply += "周辺のエレベーター設置場所をお調べいたします。車椅子対応の大型エレベーターの情報もお伝えします。"
        case "授乳室・おむつ替え台":
            reply += "お近くの授乳室やおむつ替え台のある施設を検索いたします。温水が使える施設を優先してお探ししますね。スポット一覧を表示しましょうか？"
        case "バリアフリー対応飲食店":
            reply += "車椅子のまま入店できるレストランやカフェを検索いたします。段差のない入口やテーブル席のあるお店を優先します。スポット一覧を表示しましょうか？"
        case "バリアフリー対応宿泊施設":
            reply += "バリアフリールームのあるホテルや、車椅子対応の施設を検索いたします。お部屋の設備詳細もあわせてご案内いたします。"
        case "障がい者用駐車場":
            reply += "車椅子マークの駐車場の位置をお調べいたします。広さや屋根の有無の情報もお伝えします。"
        default:
            reply += "バリアフリー対応の施設を優先して検索いたします。スポット一覧を表示しましょうか？"
        }

        return reply
    }

    /// 同行者のみ言及された場合の返答
    private func companionOnlyReply(companion: Companion) -> String {
        switch companion {
        case .child:
            return "お子様連れでのお出かけですね。ベビーカーで通りやすいルートや、おむつ替え台のある施設を優先的にご案内いたします。目的地はお決まりですか？"
        case .elderly:
            return "ご高齢の方とのお出かけですね。段差が少なく、休憩所が途中にあるルートをご提案いたします。目的地や移動手段を教えていただけますか？"
        case .disability:
            return "バリアフリーに配慮したお出かけのサポートをいたします。具体的な移動手段（車椅子、杖など）と目的地を教えていただければ、最適なルートをご案内いたします。"
        }
    }

    /// 回避・希望条件のみ言及された場合の返答
    private func conditionOnlyReply(condition: DetectedCondition) -> String {
        var parts: [String] = []
        if !condition.avoidConditions.isEmpty {
            let labels = condition.avoidConditions.map(\.label)
            parts.append("\(labels.joined(separator: "・"))を避けたルート")
        }
        if !condition.preferConditions.isEmpty {
            let labels = condition.preferConditions.map(\.label)
            parts.append("\(labels.joined(separator: "・"))がある経路")
        }
        let conditionText = parts.joined(separator: "で、かつ")
        return "\(conditionText)をご希望ですね。承知いたしました。目的地と移動手段を教えていただければ、条件に合ったルートを検索いたします。"
    }

    /// 距離・時間に関する返答
    private func distanceReply() -> String {
        return "ルートの距離や所要時間についてですね。目的地をお教えいただければ、バリアフリールートでの所要時間と距離をお調べいたします。車椅子やベビーカーの場合は、エレベーター利用時間も考慮した時間をご案内します。"
    }

    /// 天気関連の返答
    private func weatherReply() -> String {
        return "天候を気にされているのですね。雨天時はアーケードや屋根付きの通路を優先したルートをご案内できます。屋根あり経路のご希望として承りますね。目的地はどちらでしょうか？"
    }

    /// バリアフリー全般の返答
    private func barrierFreeGeneralReply() -> String {
        return "バリアフリーに関するお問い合わせですね。当サービスでは、車椅子・ベビーカー・杖での移動に対応したルート検索や、バリアフリートイレ・エレベーター・休憩所などのスポット検索が可能です。具体的にどのようなことをお調べしましょうか？"
    }

    /// デフォルト返答（会話フェーズに応じて変化）
    private func defaultReply() -> String {
        switch conversationPhase {
        case .greeting:
            return "ご相談ありがとうございます。お出かけ先やお困りのことを教えていただければ、バリアフリーの観点からお手伝いいたします。例えば「東京駅までの車椅子ルート」や「近くのバリアフリートイレ」などとお聞きください。"
        case .gathering:
            return "ありがとうございます。もう少し詳しく教えていただけますか？目的地、移動手段（車椅子・ベビーカー・杖など）、避けたい条件（階段・坂道など）がわかると、より最適なルートをご提案できます。"
        case .proposing:
            return "承知いたしました。これまでの情報をもとに、最適なルートをご提案できます。ルート検索を開始しますか？それとも他にご要望はございますか？"
        }
    }

    // MARK: - モックニーズ抽出（精度向上版）

    /// ユーザーメッセージと会話履歴全体からニーズを抽出する
    private func applyMockExtraction(for text: String) {
        let lowered = text.lowercased()

        // 全会話履歴から累積的にニーズを収集
        let allUserTexts = messages
            .filter { $0.role == .user }
            .map { $0.content.lowercased() }
            .joined(separator: " ")

        // 移動手段の抽出（現在のメッセージ優先、過去メッセージもフォールバック）
        let mobilityType = detectMobilityKeywords(in: lowered) ?? detectMobilityKeywords(in: allUserTexts)

        // 同行者の抽出（累積）
        var companions: [Companion] = []
        if let current = detectCompanionKeywords(in: lowered) {
            companions.append(current)
        }
        // 過去の会話からも同行者を収集（重複排除）
        for userText in messages.filter({ $0.role == .user }).map({ $0.content.lowercased() }) {
            if let companion = detectCompanionKeywords(in: userText), !companions.contains(companion) {
                companions.append(companion)
            }
        }

        // ベビーカー言及時は子ども同行を推測
        if mobilityType == .stroller && !companions.contains(.child) {
            companions.append(.child)
        }

        // 回避・希望条件の抽出（現在 + 累積）
        var allAvoids: [AvoidCondition] = []
        var allPrefers: [PreferCondition] = []

        // 現在のメッセージから
        if let cond = detectConditionKeywords(in: lowered) {
            allAvoids.append(contentsOf: cond.avoidConditions)
            allPrefers.append(contentsOf: cond.preferConditions)
        }
        // 過去の会話から（重複排除）
        for userText in messages.filter({ $0.role == .user }).map({ $0.content.lowercased() }) {
            if let cond = detectConditionKeywords(in: userText) {
                for avoid in cond.avoidConditions where !allAvoids.contains(avoid) {
                    allAvoids.append(avoid)
                }
                for prefer in cond.preferConditions where !allPrefers.contains(prefer) {
                    allPrefers.append(prefer)
                }
            }
        }

        // 移動手段からの暗黙的な回避条件を追加
        if mobilityType == .wheelchair && !allAvoids.contains(.stairs) {
            allAvoids.append(.stairs)
        }
        if mobilityType == .wheelchair && !allAvoids.contains(.slope) {
            allAvoids.append(.slope)
        }
        if mobilityType == .stroller && !allAvoids.contains(.stairs) {
            allAvoids.append(.stairs)
        }

        // 同行者からの暗黙的な条件を追加
        if companions.contains(.elderly) && !allAvoids.contains(.stairs) {
            allAvoids.append(.stairs)
        }
        if companions.contains(.child) && !allPrefers.contains(.restroom) {
            allPrefers.append(.restroom)
        }

        // 距離の推測（曖昧表現から）
        let maxDistance = estimateMaxDistance(from: allUserTexts)

        // ExtractedNeedsの構築
        let hasAnyData = mobilityType != nil
            || !companions.isEmpty
            || maxDistance != nil
            || !allAvoids.isEmpty
            || !allPrefers.isEmpty

        if hasAnyData {
            extractedNeeds = ExtractedNeeds(
                mobilityType: mobilityType,
                companions: companions.isEmpty ? nil : companions,
                maxDistanceMeters: maxDistance,
                avoidConditions: allAvoids.isEmpty ? nil : allAvoids,
                preferConditions: allPrefers.isEmpty ? nil : allPrefers
            )

            // Save extracted needs
            if let needs = self.extractedNeeds, needs.hasAnyNeeds {
                var needsDict: [String: Any] = [:]
                if let mobility = needs.mobilityType {
                    needsDict["mobilityType"] = mobility.rawValue
                }
                if let companions = needs.companions, !companions.isEmpty {
                    needsDict["companions"] = companions.map(\.rawValue)
                }
                if let avoidConds = needs.avoidConditions, !avoidConds.isEmpty {
                    needsDict["avoidConditions"] = avoidConds.map(\.rawValue)
                }
                if let preferConds = needs.preferConditions, !preferConds.isEmpty {
                    needsDict["preferConditions"] = preferConds.map(\.rawValue)
                }
                let destination = detectDestination(in: allUserTexts)
                if let dest = destination {
                    needsDict["destination"] = dest
                }
                UserNeedsService.saveChatNeeds(needsDict)
            }
        }

        // suggestedActionの判定（多角的に評価）
        suggestedAction = determineSuggestedAction(currentText: lowered, allTexts: allUserTexts)

        // フォローアップ提案の生成
        followUpSuggestions = generateFollowUpSuggestions(currentText: lowered, allTexts: allUserTexts)
    }

    /// 曖昧な距離表現から最大距離（メートル）を推定
    private func estimateMaxDistance(from text: String) -> Double? {
        // 具体的な数値パターン
        if let match = text.range(of: "([0-9]+)\\s*(km|キロ)", options: .regularExpression) {
            let numStr = String(text[match]).replacingOccurrences(
                of: "(km|キロ)", with: "", options: .regularExpression
            ).trimmingCharacters(in: .whitespaces)
            if let km = Double(numStr) {
                return km * 1000
            }
        }
        if let match = text.range(of: "([0-9]+)\\s*(m|メートル)", options: .regularExpression) {
            let numStr = String(text[match]).replacingOccurrences(
                of: "(m|メートル)", with: "", options: .regularExpression
            ).trimmingCharacters(in: .whitespaces)
            if let m = Double(numStr) {
                return m
            }
        }

        // 曖昧な表現からの推測
        if text.contains("すぐ近く") || text.contains("近場") || text.contains("近所") {
            return 500
        }
        if text.contains("歩いて行ける") || text.contains("徒歩圏内") || text.contains("散歩") {
            return 1500
        }
        if text.contains("あまり遠くない") || text.contains("そんなに遠くない") {
            return 3000
        }
        if text.contains("長い距離") || text.contains("遠い") || text.contains("ちょっと遠い") {
            return 5000
        }

        // 時間表現からの推測（車椅子は時速3km、徒歩は時速4kmとして）
        if let match = text.range(of: "([0-9]+)\\s*分", options: .regularExpression) {
            let numStr = String(text[match]).replacingOccurrences(
                of: "分", with: ""
            ).trimmingCharacters(in: .whitespaces)
            if let minutes = Double(numStr) {
                // 車椅子想定（時速3km = 50m/分）で計算
                return minutes * 50
            }
        }

        return nil
    }

    /// suggestedActionの判定ロジック（複数条件を総合的に評価）
    private func determineSuggestedAction(currentText: String, allTexts: String) -> SuggestedAction? {
        // スポット検索系キーワードが現在のメッセージにある場合
        let spotKeywords = [
            "トイレ", "お手洗い", "休憩", "スポット", "施設",
            "エレベーター", "授乳", "おむつ", "駐車",
            "レストラン", "カフェ", "食事", "ホテル", "宿泊",
            "探して", "どこ", "ある？", "ありますか",
        ]
        let isSpotQuery = spotKeywords.contains { currentText.contains($0) }

        // ルート検索系キーワードが現在のメッセージにある場合
        let routeKeywords = [
            "ルート", "行き方", "行きたい", "行く",
            "向かう", "移動", "道順", "経路",
            "最短", "安全", "検索", "案内",
        ]
        let isRouteQuery = routeKeywords.contains { currentText.contains($0) }

        // 目的地が特定されているか
        let hasDestination = detectDestination(in: currentText) != nil
            || detectDestination(in: allTexts) != nil

        // 移動手段が特定されているか
        let hasMobility = detectMobilityKeywords(in: allTexts) != nil

        // 判定ロジック
        if isSpotQuery && !isRouteQuery {
            return .showSpots
        }

        if isRouteQuery || (hasDestination && hasMobility) {
            return .searchRoute
        }

        if hasDestination && !hasMobility {
            // 目的地はあるが移動手段が不明 → もう少し聞く
            return .askMore
        }

        if hasMobility && !hasDestination {
            // 移動手段はあるが目的地が不明 → もう少し聞く
            return .askMore
        }

        // 抽出されたニーズがある場合はルート検索を提案
        if let needs = extractedNeeds, needs.hasAnyNeeds {
            if needs.mobilityType != nil {
                return .searchRoute
            }
            return .askMore
        }

        return nil
    }

    // MARK: - フォローアップ提案生成

    /// 会話の文脈に応じたフォローアップ提案を生成する
    private func generateFollowUpSuggestions(currentText: String, allTexts: String) -> [String] {
        let hasMobility = detectMobilityKeywords(in: allTexts) != nil
        let hasDestination = detectDestination(in: allTexts) != nil
        let hasCompanion = detectCompanionKeywords(in: allTexts) != nil
        let hasSpotType = detectSpotType(in: currentText) != nil

        // 移動手段も目的地もない初期段階
        if !hasMobility && !hasDestination {
            return [
                "車椅子で移動したい",
                "ベビーカーで出かけたい",
                "近くのバリアフリートイレを探して",
            ]
        }

        // 移動手段はあるが目的地がない
        if hasMobility && !hasDestination {
            return [
                "東京駅に行きたい",
                "近くのバリアフリースポットを探して",
                "階段を避けたルートがいい",
            ]
        }

        // 目的地はあるが移動手段がない
        if !hasMobility && hasDestination {
            return [
                "車椅子で移動します",
                "ベビーカーで行きます",
                "杖を使っています",
            ]
        }

        // スポット検索系の会話
        if hasSpotType {
            return [
                "スポット一覧を表示して",
                "もっと近い場所はある？",
                "ルート検索もしたい",
            ]
        }

        // 移動手段と目的地が揃っている場合
        if hasMobility && hasDestination {
            var suggestions = ["ルート検索を開始して"]
            if !hasCompanion {
                suggestions.append("高齢者と一緒に行きます")
            }
            suggestions.append("途中に休憩所があるルートがいい")
            return suggestions
        }

        return []
    }
}
