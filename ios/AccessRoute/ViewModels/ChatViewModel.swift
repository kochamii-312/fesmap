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
    
    // 学園祭企画データセット
    private var allProjects: [FestivalProject] = []

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
        
        // 企画データの読み込み
        loadFestivalProjects()

        messages.append(AppChatMessage(
            role: .assistant,
            content: "学園祭コンシェルジュの「フェス君」だよ！\n行きたい企画（模擬店、ライブ、展示など）のことや、場所、バリアフリー情報について何でも聞いてね！\n例：「おすすめの模擬店は？」「11棟への行き方」「車椅子で入れる展示」"
        ))
    }
    
    private func loadFestivalProjects() {
        // 本来はサーバーから取得するが、今回は検証用にローカルファイルを読み込む
        // ここでは AIサーバーと同じデータをシミュレート
        self.allProjects = [
            FestivalProject(projectId: "p001", name: "爆速たこ焼き", organization: "テニスサークル", description: "外はカリッと、中はトロッと！秘伝の出汁が自慢です。学生に大人気！", classification: "stall", form: "stall", location: "stall_road", detailedLocation: "模擬店ロード B-12", latitude: 35.6048, longitude: 139.6845, isAccessible: true, tags: ["グルメ", "粉もの", "人気"], startTime: "10:00", endTime: "18:00"),
            FestivalProject(projectId: "p002", name: "JAZZ Big Band Live", organization: "ジャズ研究会", description: "迫力あるビッグバンドの生演奏をお楽しみください。スイングしようぜ！", classification: "stage_event", form: "stage", location: "stage_area", detailedLocation: "メインステージ", latitude: 35.6055, longitude: 139.6835, isAccessible: true, tags: ["音楽", "ライブ", "ステージ"], startTime: "13:00", endTime: "14:30"),
            FestivalProject(projectId: "p003", name: "VR体験：宇宙旅行", organization: "物理学研究会", description: "最新のVR機器を使って、宇宙の果てまで旅をしよう！お子様でも楽しめます。", classification: "general", form: "experience", location: "b11", detailedLocation: "11棟 301教室", latitude: 35.5559487, longitude: 139.6523348, isAccessible: false, tags: ["体験", "科学", "最新技術"], startTime: "10:00", endTime: "17:00"),
            FestivalProject(projectId: "p004", name: "古着チャリティセール", organization: "ボランティアサークル", description: "掘り出し物が見つかるかも！売上は寄付されます。", classification: "general", form: "exhibit", location: "b12", detailedLocation: "12棟 1Fロビー", latitude: 35.6058, longitude: 139.6840, isAccessible: true, tags: ["ショッピング", "チャリティ", "SDGs"], startTime: "11:00", endTime: "16:00"),
            FestivalProject(projectId: "p005", name: "激辛カレー対決", organization: "激辛同好会", description: "あなたはどこまで耐えられるか…！？挑戦者求む！", classification: "stall", form: "stall", location: "ground", detailedLocation: "グラウンド 模擬店ブースC", latitude: 35.6042, longitude: 139.6828, isAccessible: true, tags: ["グルメ", "カレー", "激辛"], startTime: "10:00", endTime: "18:00")
        ]
    }
    
    // キーワードから企画を検索する
    private func searchFestivalProjects(query: String) -> [RecommendedSpot] {
        return allProjects.filter { project in
            project.name.contains(query) || 
            project.description.contains(query) || 
            project.tags.contains(where: { $0.contains(query) }) ||
            project.detailedLocation.contains(query)
        }.map { project in
            RecommendedSpot(
                id: project.projectId,
                name: project.name,
                reason: "\(project.detailedLocation)で実施中！",
                latitude: project.latitude,
                longitude: project.longitude,
                organization: project.organization,
                classification: project.classification,
                form: project.form,
                location: project.location,
                description: project.description,
                detailedLocation: project.detailedLocation
            )
        }
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

            // AIサーバーへのリクエスト
            let conversationHistory = self.messages.map {
                AIServerMessage(role: $0.role.rawValue, content: $0.content)
            }
            async let aiReplyTask = self.fetchAIReply(history: conversationHistory)

            // メッセージから場所名やキーワードを検出
            let detectedLocation = await self.detectLocation(from: messageText)
            let defaultLoc = LocationManager.defaultLocation
            let searchLocation = detectedLocation ?? currentLocation ?? defaultLoc
            
            var allSpots: [RecommendedSpot] = []
            
            // 学園祭企画を検索
            let festivalSpots = self.searchFestivalProjects(query: messageText)
            allSpots.append(contentsOf: festivalSpots)
            
            // もし企画が見つからない場合は、建物名などで再度検索を試みる
            if allSpots.isEmpty {
                let locations = ["11棟", "12棟", "14棟", "グラウンド", "ステージ", "模擬店ロード"]
                for loc in locations {
                    if messageText.contains(loc) {
                        allSpots.append(contentsOf: self.searchFestivalProjects(query: loc))
                    }
                }
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
                    content: "学園祭の企画（模擬店、ステージなど）について探したけど、今はそれに関連する情報が見つからなかったよ。企画名や場所（11棟など）を教えてくれるかな？",
                    followupQuestion: "11棟のおすすめを教えて"
                ))
            } else {
                let spotNames = allSpots.prefix(3).map(\.name).joined(separator: "、")
                let spotIds = allSpots.map(\.id)
                self.messages.append(AppChatMessage(
                    role: .assistant,
                    content: "学園祭の情報を探してみたよ！近くには \(allSpots.count) 件の企画やスポットがあるみたい。\n\n\(spotNames) などがおすすめだよ！気になるものはあるかな？",
                    spots: allSpots,
                    followupQuestion: "場所を詳しく教えて",
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
            print("[ChatVM] AI Server Success: \(response.reply)")
            return response.reply
        } catch {
            // AIサーバー未起動・タイムアウト等 → ローカルフォールバック
            print("[ChatVM] AI Server Error: \(error.localizedDescription)")
            return nil
        }
    }

    // スポットの詳細を取得してチャットに表示
    func fetchSpotDetail(spot: RecommendedSpot) {
        // 学園祭企画の詳細を表示（サーバー通信なしで即座に応答）
        var detailText = "【\(spot.name)】の情報を教えるね！\n\n"
        
        if let org = spot.organization {
            detailText += "🏫 団体名: \(org)\n"
        }
        
        let classificationLabel: String = {
            switch spot.classification {
            case "stage_event": return "ステージ企画"
            case "stall": return "模擬店"
            case "general": return "一般企画"
            default: return spot.classification ?? "その他"
            }
        }()
        detailText += "📌 区分: \(classificationLabel)\n"
        
        let formLabel: String = {
            switch spot.form {
            case "stage": return "ステージ"
            case "stall": return "模擬店"
            case "exhibit": return "展示"
            case "experience": return "体験"
            default: return spot.form ?? "その他"
            }
        }()
        detailText += "🎭 形態: \(formLabel)\n"
        
        if let loc = spot.detailedLocation {
            detailText += "📍 場所: \(loc)\n"
        }
        
        if let desc = spot.description {
            detailText += "\n💬 紹介:\n\(desc)\n"
        }
        
        messages.append(AppChatMessage(
            role: .assistant,
            content: detailText
        ))
    }

    // マップで表示
    func showSpotsOnMap(spots: [RecommendedSpot]) {
        appState.spotsToShowOnMap = spots
        messages.append(AppChatMessage(
            role: .assistant,
            content: "地図にスポットを表示しました。ホームタブで確認してください。"
        ))
    }

    // MARK: - 場所検出

    // メッセージから場所名を抽出
    nonisolated private static func extractPlaceName(from message: String) -> String? {
        let knownPlaces = ["11棟", "12棟", "14棟", "グラウンド", "ステージ", "模擬店ロード"]
        for place in knownPlaces {
            if message.contains(place) {
                return place
            }
        }
        return nil
    }

    // 場所名をジオコーディングして座標を取得
    private func detectLocation(from message: String) async -> CLLocationCoordinate2D? {
        guard let placeName = Self.extractPlaceName(from: message) else { return nil }
        // 学園祭内の座標は固定または検索結果から取得
        if placeName == "11棟" { return CLLocationCoordinate2D(latitude: 35.6062, longitude: 139.6852) }
        if placeName == "ステージ" { return CLLocationCoordinate2D(latitude: 35.6055, longitude: 139.6835) }
        return nil
    }

    // MARK: - キーワード抽出

    private struct SearchQuery {
        let keyword: String
        let reason: String
    }

    // MARK: - フォローアップ質問生成

    nonisolated private static func generateFollowup(for message: String) -> String? {
        if message.contains("模擬店") || message.contains("食べ") || message.contains("たこ焼き") {
            return "おすすめの模擬店を教えて！"
        }
        if message.contains("11棟") || message.contains("b11") {
            return "11棟でやってる体験企画は？"
        }
        if message.contains("ステージ") || message.contains("ライブ") {
            return "次のステージの開始時間は？"
        }
        if message.contains("トイレ") || message.contains("車椅子") {
            return "近くの多目的トイレはどこ？"
        }
        return "他におすすめの企画はあるかな？"
    }
}
