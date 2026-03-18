import Foundation
import Combine
import CoreLocation
import MapKit

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

    func sendMessage() {
        let messageText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }

        messages.append(AppChatMessage(role: .user, content: messageText))
        inputText = ""
        isLoading = true

        chatTask?.cancel()

        let currentLocation = locationManager.isLocationAvailable
            ? locationManager.currentLocation : nil

        chatTask = Task.detached { [weak self] in
            guard let self else { return }

            let queries = await MainActor.run {
                self.extractSearchQueries(from: messageText)
            }

            let defaultLoc = await MainActor.run { LocationManager.defaultLocation }
            let searchLocation = currentLocation ?? defaultLoc
            var allSpots: [RecommendedSpot] = []

            // バックグラウンドで検索（最大3件のクエリに制限）
            for query in queries.prefix(3) {
                guard !Task.isCancelled else { break }
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

            guard !Task.isCancelled else { return }

            // メインスレッドでUI更新
            await MainActor.run {
                if allSpots.isEmpty {
                    self.messages.append(AppChatMessage(
                        role: .assistant,
                        content: "「\(messageText)」に関連するスポットが見つかりませんでした。別のキーワードで試してみてください。",
                        followupQuestion: "近くのカフェを探して"
                    ))
                } else {
                    let spotNames = allSpots.prefix(3).map(\.name).joined(separator: "、")
                    let spotIds = allSpots.map(\.id)
                    self.messages.append(AppChatMessage(
                        role: .assistant,
                        content: "「\(messageText)」に関連するスポットが\(allSpots.count)件見つかりました。\n\n\(spotNames) などがおすすめです。",
                        spots: allSpots,
                        followupQuestion: self.generateFollowup(for: messageText),
                        showOnMapAction: ShowOnMapAction(type: "show", spotIds: spotIds)
                    ))
                }
                self.isLoading = false
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

    // MARK: - キーワード抽出

    private struct SearchQuery {
        let keyword: String
        let reason: String
    }

    private func extractSearchQueries(from message: String) -> [SearchQuery] {
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

        // 何も一致しなかった場合はメッセージ全体で検索
        if queries.isEmpty {
            queries.append(SearchQuery(keyword: message, reason: "検索結果"))
        }

        return queries
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

        do {
            let response = try await search.start()
            return response.mapItems.prefix(5).compactMap { item -> RecommendedSpot? in
                guard let name = item.name else { return nil }
                let coord = item.placemark.coordinate
                return RecommendedSpot(
                    id: UUID().uuidString,
                    name: name,
                    reason: reason,
                    latitude: coord.latitude,
                    longitude: coord.longitude
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - フォローアップ質問生成

    private func generateFollowup(for message: String) -> String? {
        if message.contains("カフェ") { return "車椅子で入れるカフェはある？" }
        if message.contains("レストラン") || message.contains("食事") { return "バリアフリー対応のレストランは？" }
        if message.contains("トイレ") { return "近くのカフェも教えて" }
        if message.contains("公園") { return "ベンチがある休憩スポットは？" }
        if message.contains("駅") { return "エレベーターがある出口はどこ？" }
        return "他に探したいものはありますか？"
    }
}
