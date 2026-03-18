import SwiftUI

// AIチャット画面
struct ChatView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager
    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // メッセージ一覧
                messagesArea

                // メッセージ入力バー
                inputBar
            }
            .navigationTitle("AIチャット")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.setAppState(appState)
                viewModel.setLocationManager(locationManager)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.messages.removeAll()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .ensureMinimumTapTarget()
                    .accessibilityLabel("会話をリセット")
                    .accessibilityHint("チャット履歴をすべて削除します")
                }
            }
        }
    }

    // MARK: - メッセージ一覧エリア

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty {
                    welcomeMessage
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            messageBubble(for: message)
                                .id(message.id)
                        }

                        // ローディングインジケーター
                        if viewModel.isLoading {
                            loadingIndicator
                                .id("loading")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
            }
            .onTapGesture {
                isInputFocused = false
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    // 最新メッセージに自動スクロール
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if viewModel.isLoading {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("loading", anchor: .bottom)
            }
        } else if let lastId = viewModel.messages.last?.id {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }

    // MARK: - メッセージバブル

    @ViewBuilder
    private func messageBubble(for message: AppChatMessage) -> some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // メッセージ本文
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.role == .user ? Color.blue : Color(.systemGray5),
                        in: RoundedRectangle(cornerRadius: 16)
                    )

                // スポットカード（アシスタントメッセージのみ）
                if message.role == .assistant, !message.spots.isEmpty {
                    spotCards(for: message.spots)
                }

                // 「マップで表示」ボタン
                if message.role == .assistant, let action = message.showOnMapAction {
                    mapButton(spots: message.spots.filter { spot in
                        action.spotIds.contains(spot.id)
                    })
                }

                // フォローアップ質問チップ
                if let followup = message.followupQuestion {
                    Button {
                        viewModel.inputText = followup
                        viewModel.sendMessage()
                    } label: {
                        SuggestionChip(text: followup)
                    }
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.role == .user ? "ユーザー" : "AIアシスタント"): \(message.content)")
    }

    // MARK: - スポットカード

    private func spotCards(for spots: [RecommendedSpot]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(spots) { spot in
                VStack(alignment: .leading, spacing: 4) {
                    Text(spot.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(spot.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - マップ表示ボタン

    private func mapButton(spots: [RecommendedSpot]) -> some View {
        Button {
            viewModel.showSpotsOnMap(spots: spots)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "map")
                    .font(.subheadline)
                Text("マップで表示")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.15), in: Capsule())
            .foregroundStyle(.green)
        }
        .accessibilityLabel("マップで表示")
        .accessibilityHint("推薦されたスポットを地図に表示します")
    }

    // MARK: - ローディングインジケーター

    private var loadingIndicator: some View {
        HStack {
            ProgressView()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 16))
            Spacer()
        }
        .accessibilityLabel("AIアシスタントが応答中")
    }

    // MARK: - ウェルカムメッセージ

    private let initialSuggestions = [
        "車椅子で東京駅に行きたい",
        "近くのバリアフリートイレを探して",
        "ベビーカーで移動しやすいルートは？",
        "エレベーターのある駅を教えて",
        "高齢者と一緒に観光したい",
        "雨の日でも歩きやすいルートは？",
        "休憩できる場所を探して",
    ]

    private var welcomeMessage: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue.opacity(0.6))

            Text("AIチャットに\n旅行の相談をしてみましょう")
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            // サジェストチップ（タップ可能）
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 8) {
                ForEach(initialSuggestions, id: \.self) { suggestion in
                    Button {
                        viewModel.inputText = suggestion
                        viewModel.sendMessage()
                    } label: {
                        SuggestionChip(text: suggestion)
                    }
                }
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AIチャットへようこそ")
    }

    // MARK: - メッセージ入力バー

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("メッセージを入力...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 20))
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit {
                    sendIfPossible()
                }
                .accessibilityLabel("メッセージ入力フィールド")

            // 送信ボタン
            Button {
                sendIfPossible()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? .blue : .gray)
            }
            .disabled(!canSend)
            .ensureMinimumTapTarget()
            .accessibilityLabel("メッセージを送信")
            .accessibilityHint("入力したメッセージをAIに送信します")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty && !viewModel.isLoading
    }

    private func sendIfPossible() {
        guard canSend else { return }
        viewModel.sendMessage()
    }
}

// MARK: - 質問候補チップ

struct SuggestionChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.bubble")
                .font(.caption)
                .foregroundStyle(.blue)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6), in: Capsule())
    }
}
