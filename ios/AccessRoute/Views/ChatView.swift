
import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var appState: AppState
    
    @StateObject private var viewModel: ChatViewModel

    init() {
        // EnvironmentObjectはinitの後で注入されるため、
        // ここではプレースホルダーやデフォルト値で初期化し、
        // onAppearなどで実際の値を設定するか、
        // 以下のようにinit内で依存性を解決するラッパーを設ける。
        // この実装では、ViewModelのinitで直接依存性を渡すアプローチをとる。
        
        // _viewModelの初期化は一度しか行われない。
        // このViewが再生成されてもViewModelのインスタンスは維持される。
        let state = _viewModel
        let lm = Environment(\.locationManager).wrappedValue
        let app = Environment(\.appState).wrappedValue
        state.wrappedValue = ChatViewModel(locationManager: lm, appState: app)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 会話履歴
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(viewModel.messages) { message in
                                MessageView(message: message, viewModel: viewModel)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        // 新しいメッセージが追加されたら一番下にスクロール
                        if let lastMessage = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // ローディングインジケーター
                if viewModel.isLoading {
                    ProgressView()
                        .padding()
                }
                
                // 入力エリア
                MessageInputView(
                    inputText: $viewModel.inputText,
                    onSend: viewModel.sendMessage
                )
            }
            .navigationTitle("AIチャット")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Message Views

private struct MessageView: View {
    let message: AppChatMessage
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer()
                Text(message.content)
                    .padding(12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                if !message.recommendedConditions.isEmpty {
                    ConditionChipsView(conditions: message.recommendedConditions)
                }

                if !message.spots.isEmpty {
                    SpotsCarouselView(spots: message.spots, viewModel: viewModel)
                }
                
                if let question = message.followupQuestion {
                    Text(question)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                }
            }
            .padding(12)
            .background(Color(UIColor.systemGray6))
            .cornerRadius(16)
        }
    }
}

private struct ConditionChipsView: View {
    let conditions: [String]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(conditions, id: \.self) { condition in
                    Text(condition)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

private struct SpotsCarouselView: View {
    let spots: [RecommendedSpot]
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(spots) { spot in
                        SpotCardView(spot: spot)
                    }
                }
                .padding(.horizontal)
            }
            
            Button(action: {
                viewModel.showSpotsOnMap(spots: spots)
            }) {
                HStack {
                    Image(systemName: "map.fill")
                    Text("提案をすべてマップで表示")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(10)
            }
            .padding(.horizontal)
        }
    }
}

private struct SpotCardView: View {
    let spot: RecommendedSpot
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(spot.name)
                .font(.headline)
                .lineLimit(2)
            
            Text(spot.reason)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(3)
            
            Spacer()
            
            Text(String(format: "緯度: %.4f, 経度: %.4f", spot.latitude, spot.longitude))
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .frame(width: 220, height: 150)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}


// MARK: - Input View

private struct MessageInputView: View {
    @Binding var inputText: String
    let onSend: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("メッセージを入力...", text: $inputText)
                .padding(10)
                .background(Color(UIColor.systemGray5))
                .cornerRadius(16)
                .onSubmit(onSend)
            
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(inputText.isEmpty ? .gray : .blue)
            }
            .disabled(inputText.isEmpty)
        }
        .padding()
        .background(.thinMaterial)
    }
}

// MARK: - Environment Keys for DI
// ViewModelの初期化でEnvironmentObjectを使うためのヘルパー

private struct LocationManagerKey: EnvironmentKey {
    static let defaultValue: LocationManager = LocationManager()
}

private struct AppStateKey: EnvironmentKey {
    static let defaultValue: AppState = AppState()
}

extension EnvironmentValues {
    var locationManager: LocationManager {
        get { self[LocationManagerKey.self] }
        set { self[LocationManagerKey.self] = newValue }
    }
    
    var appState: AppState {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }
}
