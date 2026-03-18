import Foundation
import Combine
import CoreLocation

// チャットメッセージの構造体（UI表示用）
struct AppChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let content: String
    var spots: [RecommendedSpot] = []
    var recommendedConditions: [String] = []
    var followupQuestion: String? = nil
    var showOnMapAction: ShowOnMapAction? = nil
}

@MainActor
final class ChatViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var messages: [AppChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    
    // MARK: - Dependencies
    private let apiService: APIService
    private let locationManager: LocationManager
    private var appState: AppState

    private var cancellables = Set<AnyCancellable>()

    init(
        apiService: APIService = .shared,
        locationManager: LocationManager,
        appState: AppState
    ) {
        self.apiService = apiService
        self.locationManager = locationManager
        self.appState = appState
        
        // 初期メッセージを追加
        messages.append(AppChatMessage(role: .assistant, content: "行きたい場所について、自由に入力してください。\n例：「静かで桜が見れる場所」「車いすで入れるカフェ」"))
    }

    // MARK: - Public Methods
    
    func sendMessage() {
        let messageText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }
        
        // ユーザーメッセージをUIに追加
        messages.append(AppChatMessage(role: .user, content: messageText))
        self.inputText = ""
        self.isLoading = true

        // 現在地を取得
        let currentLocation = locationManager.isLocationAvailable ? locationManager.currentLocation : nil

        Task {
            do {
                let response = try await apiService.getSpotSuggestions(
                    message: messageText,
                    latitude: currentLocation?.latitude,
                    longitude: currentLocation?.longitude
                )
                
                // AIアシスタントの応答をUIに追加
                let assistantMessage = AppChatMessage(
                    role: .assistant,
                    content: response.assistantMessage,
                    spots: response.spots,
                    recommendedConditions: response.recommendedConditions,
                    followupQuestion: response.followupQuestion,
                    showOnMapAction: response.action
                )
                self.messages.append(assistantMessage)
                
            } catch {
                // エラーメッセージをUIに追加
                let errorMessage = "申し訳ありません、エラーが発生しました。しばらくしてからもう一度お試しください。"
                self.messages.append(AppChatMessage(role: .assistant, content: errorMessage))
                print("ChatViewModel Error: \(error.localizedDescription)")
            }
            
            self.isLoading = false
        }
    }
    
    /// 「マップで表示」ボタンが押されたときのアクション
    func showSpotsOnMap(spots: [RecommendedSpot]) {
        // AppStateを更新してHomeViewに通知する
        appState.spotsToShowOnMap = spots
        
        // TODO: ここでタブをホームタブに切り替える処理を追加するのが望ましい
        // (例: TabViewのselectionを管理するAppStateのプロパティを更新する)
        
        // ユーザーへのフィードバックメッセージ
        let feedbackMessage = AppChatMessage(role: .assistant, content: "地図にスポットを表示しました。")
        messages.append(feedbackMessage)
    }
}