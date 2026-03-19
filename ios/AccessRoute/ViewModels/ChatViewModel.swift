import Foundation
import Combine
import CoreLocation
@preconcurrency import MapKit

// チャットメッセージの構造体（UI表示用）
struct AppChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let content: String
    var spots: [RecommendedSpot] = []
    var recommendedConditions: [String] = []
    var followupQuestion: String?
    var showOnMapAction: ShowOnMapAction?
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [AppChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false

    private var locationManager: LocationManager
    private var appState: AppState

    func setAppState(_ state: AppState) {
        self.appState = state
    }

    func setLocationManager(_ manager: LocationManager) {
        self.locationManager = manager
    }

    init(
        apiService: APIService = .shared,
        locationManager: LocationManager = LocationManager(),
        appState: AppState = AppState()
    ) {
        self.locationManager = locationManager
        self.appState = appState

        messages.append(AppChatMessage(
            role: .assistant,
            content: "行きたい場所について、自由に入力してください。\n例：「静かで桜が見れる場所」「車いすで入れるカフェ」"
        ))
    }

    // MARK: - メッセージ送信

    private var chatTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var activeTaskId: UUID?

    func sendMessage() {
        let messageText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }

        messages.append(AppChatMessage(role: .user, content: messageText))
        inputText = ""
        isLoading = true

        chatTask?.cancel()
        detailTask?.cancel()

        let taskId = UUID()
        activeTaskId = taskId

        let currentLocation = locationManager.isLocationAvailable
            ? locationManager.currentLocation : nil

        chatTask = Task { [weak self] in
            guard let self else { return }

            defer {
                if self.activeTaskId == taskId {
                    self.isLoading = false
                }
            }

            // AIサーバーへのリクエストとMapKit検索を並行実行
            let conversationHistory = self.messages.map {
                AIServerMessage(role: $0.role.rawValue, content: $0.content)
            }
            async let aiReplyTask = self.fetchAIReply(history: conversationHistory)

            let queries = Self.extractSearchQueries(from: messageText)

            // メッセージから場所名を検出してジオコーディング
            let detectedLocation = await self.detectLocation(from: messageText)
            let defaultLoc = LocationManager.defaultLocation
            let searchLocation = detectedLocation ?? currentLocation ?? defaultLoc
            let locationLabel = detectedLocation != nil
                ? Self.extractPlaceName(from: messageText) ?? "指定地点"
                : "現在地"
            var allSpots: [RecommendedSpot] = []

            // バックグラウンドで検索（最大3件のクエリに制限）
            for query in queries.prefix(3) {
                guard !Task.isCancelled else { return }
                let spots = await self.searchMapKit(
                    query: query.keyword,
                    near: searchLocation,
                    reason: query.reason
                )
                allSpots.append(contentsOf: spots)
            }

            // 重複除去
            var seen = Set<String>()
            allSpots = allSpots.filter { spot in
                let key = String(spot.name.prefix(5))
                if seen.contains(key) { return false }
                seen.insert(key)
                return true
            }

            // 検索地点から近い順にソートして最大7件
            allSpots.sort { a, b in
                let distA = TransitRouteService.haversineDistance(
                    from: searchLocation,
                    to: CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude)
                )
                let distB = TransitRouteService.haversineDistance(
                    from: searchLocation,
                    to: CLLocationCoordinate2D(latitude: b.latitude, longitude: b.longitude)
                )
                return distA < distB
            }
            allSpots = Array(allSpots.prefix(7))

            guard !Task.isCancelled else { return }

            // AI応答を取得（サーバー未起動ならnil）
            let aiReply = await aiReplyTask

            // AI応答があればそれを使い、なければ従来テンプレートにフォールバック
            if let aiReply = aiReply {
                let spotIds = allSpots.map(\.id)
                self.messages.append(AppChatMessage(
                    role: .assistant,
                    content: aiReply,
                    spots: allSpots,
                    followupQuestion: Self.generateFollowup(for: messageText),
                    showOnMapAction: allSpots.isEmpty ? nil : ShowOnMapAction(type: "show", spotIds: spotIds)
                ))
            } else if allSpots.isEmpty {
                self.messages.append(AppChatMessage(
                    role: .assistant,
                    content: "\(locationLabel)周辺で「\(messageText)」に関連するスポットが見つかりませんでした。別のキーワードや場所で試してみてください。",
                    followupQuestion: "渋谷のカフェを探して"
                ))
            } else {
                let spotNames = allSpots.prefix(3).map(\.name).joined(separator: "、")
                let spotIds = allSpots.map(\.id)
                self.messages.append(AppChatMessage(
                    role: .assistant,
                    content: "\(locationLabel)周辺で\(allSpots.count)件のスポットが見つかりました。\n\n\(spotNames) などがおすすめです。",
                    spots: allSpots,
                    followupQuestion: Self.generateFollowup(for: messageText),
                    showOnMapAction: ShowOnMapAction(type: "show", spotIds: spotIds)
                ))
            }
        }
    }

    // MARK: - AI応答取得

    // AIサーバーから応答を取得（失敗時はnilを返してフォールバック）
    private func fetchAIReply(history: [AIServerMessage]) async -> String? {
        do {
            let response = try await APIService.shared.sendAIChatMessage(
                messages: history
            )
            return response.reply
        } catch {
            // AIサーバー未起動・タイムアウト等 → ローカルフォールバック
            return nil
        }
    }

    // スポットの詳細を取得してチャットに表示
    func fetchSpotDetail(spot: RecommendedSpot) {
        // 前の詳細取得タスクをキャンセル
        detailTask?.cancel()

        // ローディングメッセージ
        messages.append(AppChatMessage(
            role: .assistant,
            content: "「\(spot.name)」の詳細を調べています..."
        ))
        isLoading = true

        let taskId = UUID()
        activeTaskId = taskId

        detailTask = Task { [weak self] in
            guard let self else { return }

            defer {
                if self.activeTaskId == taskId {
                    self.isLoading = false
                }
            }

            let coord = CLLocationCoordinate2D(
                latitude: spot.latitude, longitude: spot.longitude
            )

            // Google Places API で詳細取得
            let detail = await GooglePlacesService.fetchDetail(
                name: spot.name, coordinate: coord
            )

            guard !Task.isCancelled else { return }

            // ローディングメッセージを削除（IDではなくスポット名で特定）
            let loadingText = "「\(spot.name)」の詳細を調べています..."
            if let idx = self.messages.lastIndex(where: { $0.content == loadingText }) {
                self.messages.remove(at: idx)
            }

            if let gd = detail {
                // 詳細情報をAIが調べた形で表示
                var info = "📍 **\(spot.name)** の詳細情報\n\n"

                if let cuisine = gd.cuisineType {
                    info += "🍽️ ジャンル: \(cuisine)\n"
                }
                if let rating = gd.rating {
                    info += "⭐ 評価: \(String(format: "%.1f", rating))\n"
                }
                if let price = GooglePlacesService.priceLevelText(gd.priceLevel) {
                    info += "💰 価格帯: \(price)\n"
                }
                if let openNow = gd.openNow {
                    info += openNow ? "🟢 現在営業中\n" : "🔴 現在営業時間外\n"
                }
                if let wheelchair = gd.isWheelchairAccessible {
                    info += wheelchair ? "♿ 車椅子対応入口あり\n" : "⚠️ 車椅子対応入口なし\n"
                }
                if let address = gd.address {
                    info += "📮 \(address)\n"
                }
                if let phone = gd.phone {
                    info += "📞 \(phone)\n"
                }
                if !gd.openingHours.isEmpty {
                    info += "\n🕐 営業時間:\n"
                    for hours in gd.openingHours {
                        info += "  \(hours)\n"
                    }
                }
                if let review = gd.review {
                    info += "\n💬 レビュー:\n\(review)..."
                }

                self.messages.append(AppChatMessage(
                    role: .assistant,
                    content: info,
                    spots: [spot],
                    followupQuestion: "このお店への行き方を教えて",
                    showOnMapAction: ShowOnMapAction(type: "show", spotIds: [spot.id])
                ))
            } else {
                self.messages.append(AppChatMessage(
                    role: .assistant,
                    content: "「\(spot.name)」の詳細情報を取得できませんでした。",
                    followupQuestion: "他のおすすめを教えて"
                ))
            }
        }
    }

    // マップで表示
    func showSpotsOnMap(spots: [RecommendedSpot]) {
        appState.spotsToShowOnMap = spots
        messages.append(AppChatMessage(
            role: .assistant,
            content: "地図にスポットを表示しました。ホームタブで確認してください。"
        ))
    }

    // searchSpotsLocally は sendMessage() 内に統合済み

    // MARK: - 場所検出

    // メッセージから場所名を抽出
    nonisolated private static func extractPlaceName(from message: String) -> String? {
        // 非地名ワードのブロックリスト
        let nonPlaceWords = [
            "静か", "ゆっくり", "のんびり", "車椅子", "車いす", "バリアフリー",
            "ベビーカー", "落ち着", "広く", "狭い", "おしゃれ", "きれい",
            "安い", "高い", "美味し", "楽し", "近く", "遠く",
            "移動", "食べ", "飲み", "休み", "遊び", "買い物",
            "カフェ", "レストラン", "トイレ", "エレベーター", "公園",
            "図書館", "カラオケ", "体育館", "コンビニ", "病院",
        ]

        // 1. 既知の地名が含まれているかチェック（最優先）
        let knownPlaces = [
            "東京駅", "新宿駅", "渋谷駅", "池袋駅", "品川駅", "上野駅",
            "秋葉原駅", "銀座駅", "六本木駅", "原宿駅", "表参道駅",
            "恵比寿駅", "目黒駅", "浜松町駅", "横浜駅", "川崎駅",
            "溝の口駅", "武蔵小杉駅", "二子玉川駅", "自由が丘駅",
            "東京", "新宿", "渋谷", "池袋", "品川", "上野", "秋葉原",
            "銀座", "六本木", "原宿", "表参道", "恵比寿", "目黒",
            "浜松町", "横浜", "川崎", "溝の口", "武蔵小杉", "二子玉川",
            "自由が丘", "大阪", "梅田", "難波", "京都", "名古屋",
            "福岡", "札幌", "浅草", "お台場", "スカイツリー", "東京タワー",
            "紀尾井町", "赤坂", "永田町", "大手町", "丸の内", "日本橋",
            "神保町", "飯田橋", "四ツ谷", "市ヶ谷", "高田馬場",
            "中野", "荻窪", "吉祥寺", "三鷹", "立川",
        ]

        // 長い名前から優先的にマッチ（「東京駅」が「東京」より先にマッチ）
        let sortedPlaces = knownPlaces.sorted { $0.count > $1.count }
        for place in sortedPlaces {
            if message.contains(place) {
                return place
            }
        }

        // 2. 「〇〇駅」「〇〇区」「〇〇市」「〇〇町」パターン
        let locationSuffixes = ["駅", "区", "市", "町", "村", "県"]
        for suffix in locationSuffixes {
            if let range = message.range(of: suffix) {
                // suffix の前の文字列を取得（最大10文字）
                let startIdx = message.index(range.lowerBound, offsetBy: -min(10, message.distance(from: message.startIndex, to: range.lowerBound)))
                let before = String(message[startIdx..<range.lowerBound])
                // 最後の助詞以降を地名として抽出
                let components = before.components(separatedBy: CharacterSet(charactersIn: "のでをにはがとも"))
                if let lastPart = components.last, !lastPart.isEmpty, lastPart.count >= 2 {
                    let placeName = lastPart + suffix
                    // ブロックリストチェック
                    if !nonPlaceWords.contains(where: { placeName.contains($0) }) {
                        return placeName
                    }
                }
            }
        }

        // 3. 「〇〇周辺」「〇〇付近」パターン（これは地名の可能性が高い）
        let locationPatterns = ["周辺", "付近", "あたり", "近辺"]
        for pattern in locationPatterns {
            if let range = message.range(of: pattern) {
                let before = String(message[message.startIndex..<range.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                // 助詞で分割して最後の部分を取得
                let parts = before.components(separatedBy: CharacterSet(charactersIn: "のでをにはがとも"))
                if let lastPart = parts.last, lastPart.count >= 2 {
                    if !nonPlaceWords.contains(where: { lastPart.contains($0) }) {
                        return lastPart
                    }
                }
            }
        }

        return nil
    }

    // 場所名をジオコーディングして座標を取得
    private func detectLocation(from message: String) async -> CLLocationCoordinate2D? {
        guard let placeName = Self.extractPlaceName(from: message) else { return nil }

        do {
            let latLng = try await GeocodingService.shared.geocode(placeName)
            return CLLocationCoordinate2D(latitude: latLng.lat, longitude: latLng.lng)
        } catch {
            return nil
        }
    }

    // MARK: - キーワード抽出

    private struct SearchQuery {
        let keyword: String
        let reason: String
    }

    nonisolated private static func extractSearchQueries(from message: String) -> [SearchQuery] {
        var queries: [SearchQuery] = []

        // カフェ関連
        let cafeKeywords = ["カフェ", "コーヒー", "珈琲", "喫茶", "スタバ", "cafe"]
        if cafeKeywords.contains(where: { message.contains($0) }) {
            queries.append(SearchQuery(keyword: "カフェ", reason: "カフェのおすすめ"))
        }

        // レストラン・食事関連
        let foodKeywords = ["レストラン", "ランチ", "ディナー", "食事", "ご飯", "食べ", "料理"]
        if foodKeywords.contains(where: { message.contains($0) }) {
            queries.append(SearchQuery(keyword: "レストラン", reason: "食事のおすすめ"))
        }

        // ラーメン
        if message.contains("ラーメン") || message.contains("らーめん") {
            queries.append(SearchQuery(keyword: "ラーメン", reason: "ラーメン店"))
        }

        // 寿司
        if message.contains("寿司") || message.contains("すし") || message.contains("鮨") {
            queries.append(SearchQuery(keyword: "寿司", reason: "寿司屋"))
        }

        // トイレ関連
        let toiletKeywords = ["トイレ", "お手洗い", "化粧室", "バリアフリー"]
        if toiletKeywords.contains(where: { message.contains($0) }) {
            queries.append(SearchQuery(keyword: "多目的トイレ", reason: "バリアフリートイレ"))
        }

        // 公園・自然
        let parkKeywords = ["公園", "緑", "自然", "散歩", "桜"]
        if parkKeywords.contains(where: { message.contains($0) }) {
            queries.append(SearchQuery(keyword: "公園", reason: "公園・自然スポット"))
        }

        // カラオケ
        if message.contains("カラオケ") {
            queries.append(SearchQuery(keyword: "カラオケ", reason: "カラオケ"))
        }

        // 図書館
        if message.contains("図書館") || message.contains("本") {
            queries.append(SearchQuery(keyword: "図書館", reason: "図書館"))
        }

        // ジム・体育館
        let gymKeywords = ["ジム", "体育館", "運動", "スポーツ", "フィットネス"]
        if gymKeywords.contains(where: { message.contains($0) }) {
            queries.append(SearchQuery(keyword: "スポーツジム", reason: "ジム・体育館"))
        }

        // 車椅子対応
        let wheelchairKeywords = ["車椅子", "車いす", "くるまいす", "wheelchair"]
        if wheelchairKeywords.contains(where: { message.contains($0) }) {
            // 車椅子 + 他のキーワードがあればそのまま、なければバリアフリー施設
            if queries.isEmpty {
                queries.append(SearchQuery(keyword: "バリアフリー", reason: "車椅子対応施設"))
            }
            // 既存クエリに「バリアフリー」を追加
            for i in queries.indices {
                queries[i] = SearchQuery(
                    keyword: queries[i].keyword + " バリアフリー",
                    reason: queries[i].reason + "（車椅子対応）"
                )
            }
        }

        // エレベーター
        if message.contains("エレベーター") {
            queries.append(SearchQuery(keyword: "エレベーター", reason: "エレベーター"))
        }

        // 自然・景色関連（地名内の「ガーデン」等を除外するため、前後の文脈で判定）
        let natureKeywords = ["桜", "花見", "紅葉", "自然", "緑"]
        if natureKeywords.contains(where: { message.contains($0) }) {
            queries.append(SearchQuery(keyword: "公園 桜", reason: "桜・自然スポット"))
            queries.append(SearchQuery(keyword: "庭園", reason: "庭園"))
        }
        // 「庭園」は単独で出てきた場合のみ（「ガーデンテラス」等の地名は除外）
        if message.contains("庭園") && !message.contains("ガーデン") {
            queries.append(SearchQuery(keyword: "庭園", reason: "庭園"))
        }

        // 静か・落ち着く関連（具体的なカテゴリが未指定の場合のみ）
        let quietKeywords = ["静か", "落ち着", "ゆっくり", "のんびり", "穏やか", "癒し"]
        if quietKeywords.contains(where: { message.contains($0) }) && queries.isEmpty {
            queries.append(SearchQuery(keyword: "公園", reason: "静かな場所"))
            queries.append(SearchQuery(keyword: "図書館", reason: "静かな施設"))
            queries.append(SearchQuery(keyword: "カフェ 静か", reason: "落ち着けるカフェ"))
        }

        // 観光・遊び関連（具体的なカテゴリが未指定の場合のみ）
        let tourKeywords = ["観光", "観る", "遊ぶ", "遊び", "デート", "散策"]
        if tourKeywords.contains(where: { message.contains($0) }) && queries.isEmpty {
            queries.append(SearchQuery(keyword: "観光", reason: "観光スポット"))
            queries.append(SearchQuery(keyword: "公園", reason: "散策スポット"))
        }

        // 買い物関連
        let shopKeywords = ["買い物", "ショッピング", "お土産", "雑貨", "服", "本屋"]
        if shopKeywords.contains(where: { message.contains($0) }) {
            queries.append(SearchQuery(keyword: "ショッピング", reason: "買い物スポット"))
        }

        // コンビニ
        if message.contains("コンビニ") {
            queries.append(SearchQuery(keyword: "コンビニ", reason: "コンビニ"))
        }

        // 薬局・ドラッグストア
        let pharmacyKeywords = ["薬局", "ドラッグストア", "薬"]
        if pharmacyKeywords.contains(where: { message.contains($0) }) {
            queries.append(SearchQuery(keyword: "ドラッグストア", reason: "薬局"))
        }

        // 病院・クリニック
        let hospitalKeywords = ["病院", "クリニック", "医者", "医院"]
        if hospitalKeywords.contains(where: { message.contains($0) }) {
            queries.append(SearchQuery(keyword: "病院", reason: "医療施設"))
        }

        // 何も一致しなかった場合は自然言語からキーワードを抽出して検索
        if queries.isEmpty {
            // メッセージからキーワードを分解して検索
            let extracted = extractNaturalKeywords(from: message)
            for keyword in extracted {
                queries.append(SearchQuery(keyword: keyword, reason: "「\(keyword)」の検索結果"))
            }
        }

        // それでも空なら全文で検索
        if queries.isEmpty {
            queries.append(SearchQuery(keyword: message, reason: "検索結果"))
        }

        return queries
    }

    // 自然言語からキーワードを抽出
    nonisolated private static func extractNaturalKeywords(from message: String) -> [String] {
        // 不要な助詞・接続詞を除去してキーワードを抽出
        let stopWords = ["が", "を", "に", "は", "の", "で", "と", "も", "な", "い",
                         "たい", "ほしい", "ある", "いる", "できる", "ない", "ます",
                         "です", "する", "した", "して", "れる", "場所", "ところ",
                         "見れる", "行ける", "探して", "教えて", "知りたい", "おすすめ"]

        var cleaned = message
        for word in stopWords {
            cleaned = cleaned.replacingOccurrences(of: word, with: " ")
        }

        let keywords = cleaned.components(separatedBy: .whitespaces)
            .filter { $0.count >= 2 }

        return Array(keywords.prefix(3))
    }

    // MARK: - MKLocalSearch

    private func searchMapKit(
        query: String,
        near coordinate: CLLocationCoordinate2D,
        reason: String
    ) async -> [RecommendedSpot] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        )
        request.resultTypes = .pointOfInterest

        let search = MKLocalSearch(request: request)
        let searchReason = reason

        // MKLocalSearch.Responseはnon-Sendableのためコールバック版を使用
        let items: [(name: String, lat: Double, lng: Double)] = await withCheckedContinuation { continuation in
            search.start { response, _ in
                let results = response?.mapItems.prefix(5).compactMap { item -> (String, Double, Double)? in
                    guard let name = item.name else { return nil }
                    let c = item.placemark.coordinate
                    return (name, c.latitude, c.longitude)
                } ?? []
                continuation.resume(returning: results)
            }
        }

        do {
            return items.map { item in
                RecommendedSpot(
                    id: UUID().uuidString,
                    name: item.name,
                    reason: searchReason,
                    latitude: item.lat,
                    longitude: item.lng
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - フォローアップ質問生成

    nonisolated private static func generateFollowup(for message: String) -> String? {
        if message.contains("カフェ") { return "車椅子で入れるカフェはある？" }
        if message.contains("レストラン") || message.contains("食事") { return "バリアフリー対応のレストランは？" }
        if message.contains("トイレ") { return "近くのカフェも教えて" }
        if message.contains("公園") { return "ベンチがある休憩スポットは？" }
        if message.contains("駅") { return "エレベーターがある出口はどこ？" }
        return "他に探したいものはありますか？"
    }
}
