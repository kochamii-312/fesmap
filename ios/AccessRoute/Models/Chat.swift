import Foundation

// チャットメッセージの役割
enum ChatRole: String, Codable {
    case user
    case assistant
}

// チャットメッセージ
struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    var content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: ChatRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    // API送信用の辞書形式（conversationHistory用）
    var asDictionary: [String: String] {
        ["role": role.rawValue, "content": content]
    }
}

// チャットAPIリクエスト
struct ChatRequest: Codable {
    let userId: String
    let message: String
    let conversationHistory: [[String: String]]
}

// チャットAPIレスポンス
struct ChatResponse: Codable {
    let reply: String
    let extractedNeeds: ExtractedNeeds?
    let suggestedAction: SuggestedAction?
}

// AIが提案するアクション
enum SuggestedAction: String, Codable {
    case askMore = "ask_more"
    case searchRoute = "search_route"
    case showSpots = "show_spots"
}

// 会話から抽出されたニーズ（UserProfileの部分型）
struct ExtractedNeeds: Codable {
    let mobilityType: MobilityType?
    let companions: [Companion]?
    let maxDistanceMeters: Double?
    let avoidConditions: [AvoidCondition]?
    let preferConditions: [PreferCondition]?

    // 抽出された項目があるかどうか
    var hasAnyNeeds: Bool {
        mobilityType != nil ||
        !(companions?.isEmpty ?? true) ||
        maxDistanceMeters != nil ||
        !(avoidConditions?.isEmpty ?? true) ||
        !(preferConditions?.isEmpty ?? true)
    }

    // 抽出された情報のサマリーテキスト
    var summaryItems: [(label: String, value: String)] {
        var items: [(String, String)] = []
        if let mobility = mobilityType {
            items.append(("移動手段", mobility.label))
        }
        if let companions = companions, !companions.isEmpty {
            items.append(("同行者", companions.map(\.label).joined(separator: "、")))
        }
        if let distance = maxDistanceMeters {
            items.append(("最大距離", AccessibilityHelpers.distanceText(meters: distance)))
        }
        if let avoids = avoidConditions, !avoids.isEmpty {
            items.append(("回避条件", avoids.map(\.label).joined(separator: "、")))
        }
        if let prefers = preferConditions, !prefers.isEmpty {
            items.append(("希望条件", prefers.map(\.label).joined(separator: "、")))
        }
        return items
    }
}

// ニーズ抽出APIリクエスト
struct ExtractNeedsRequest: Codable {
    let userId: String
    let conversationHistory: [[String: String]]
}

// ニーズ抽出APIレスポンス
struct ExtractNeedsResponse: Codable {
    let needs: ExtractedNeeds
    let confidence: Double
    let missingFields: [String]
}

// MARK: - YOLP Spot Suggestion Chat Models (v2)

/// `/v2/chat` エンドポイントへのリクエスト
struct YolpChatRequest: Codable {
    let message: String
    let latitude: Double?
    let longitude: Double?
}

/// `/v2/chat` エンドポイントからのレスポンス
struct YolpChatResponse: Codable {
    let assistantMessage: String
    let recommendedConditions: [String]
    let spots: [RecommendedSpot]
    let followupQuestion: String?
    let action: ShowOnMapAction?
}

/// AIによって推薦されたスポット情報
struct RecommendedSpot: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let reason: String
    let latitude: Double
    let longitude: Double
}

/// 地図表示をトリガーするアクション
struct ShowOnMapAction: Codable {
    let type: String
    let spotIds: [String]
}

// MARK: - AIサーバー直接通信用モデル（/v1/chat）

/// AIサーバーへ送るメッセージ（OpenAI互換形式）
struct AIServerMessage: Codable {
    let role: String
    let content: String
}

/// AIサーバー `/v1/chat` へのリクエスト
struct AIServerChatRequest: Codable {
    let messages: [AIServerMessage]
    let maxTokens: Int
    let temperature: Double
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case messages
        case maxTokens = "max_tokens"
        case temperature
        case stream
    }
}

/// AIサーバー `/v1/chat` からのレスポンス（replyのみ使用）
struct AIServerChatResponse: Codable {
    let reply: String
}
