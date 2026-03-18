import SwiftUI

// AIチャット画面
struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // メッセージ一覧
                messagesArea

                // ニーズ抽出結果カード
                if let needs = viewModel.extractedNeeds, needs.hasAnyNeeds {
                    ExtractedNeedsCard(needs: needs)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // アクションボタン
                if let action = viewModel.suggestedAction, action != .askMore {
                    actionButton(for: action)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // エラーメッセージ
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }

                // メッセージ入力バー
                inputBar
            }
            .navigationTitle("AIコンシェルジュ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.resetConversation()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .ensureMinimumTapTarget()
                    .accessibilityLabel("会話をリセット")
                    .accessibilityHint("チャット履歴をすべて削除します")
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.extractedNeeds?.hasAnyNeeds)
            .animation(.easeInOut(duration: 0.3), value: viewModel.suggestedAction)
            .navigationDestination(isPresented: $viewModel.shouldNavigateToRoute) {
                RouteView()
            }
            .navigationDestination(isPresented: $viewModel.shouldNavigateToSpots) {
                SpotView()
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
                            ChatBubbleView(message: message)
                                .id(message.id)
                        }

                        // タイピングインジケーター
                        if viewModel.isTyping {
                            TypingIndicator()
                                .id("typing")
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
            .onChange(of: viewModel.messages.last?.content) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    // 最新メッセージに自動スクロール
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if viewModel.isTyping {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("typing", anchor: .bottom)
            }
        } else if let lastId = viewModel.messages.last?.id {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }

    // MARK: - ウェルカムメッセージ

    // サジェストチップの定義（Expo版と同様）
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

            Text("AIコンシェルジュに\n旅行の相談をしてみましょう")
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            // サジェストチップ（タップ可能）
            FlowLayout(spacing: 8) {
                ForEach(initialSuggestions, id: \.self) { suggestion in
                    Button {
                        viewModel.inputText = suggestion
                        Task { await viewModel.sendMessage() }
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
        .accessibilityLabel("AIコンシェルジュへようこそ")
    }

    // MARK: - アクションボタン

    // アクションカード（Expo版の緑カードスタイル）
    @ViewBuilder
    private func actionButton(for action: SuggestedAction) -> some View {
        Button {
            viewModel.handleAction(action)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action == .searchRoute
                    ? "point.topleft.down.to.point.bottomright.curvepath.fill"
                    : "mappin.and.ellipse")
                    .font(.title3)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action == .searchRoute ? "ルートを検索する" : "スポットを見る")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(action == .searchRoute
                        ? "条件に合ったルートを探します"
                        : "周辺のおすすめスポットを表示します")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.green.opacity(0.3), lineWidth: 1)
                    .fill(Color.green.opacity(0.05))
            )
        }
        .accessibilityLabel(action == .searchRoute ? "ルートを検索する" : "スポットを見る")
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
        !viewModel.inputText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty && !viewModel.isTyping
    }

    private func sendIfPossible() {
        guard canSend else { return }
        Task {
            await viewModel.sendMessage()
        }
    }
}

// MARK: - チャットバブル

struct ChatBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(message.role == .user ? AppColors.chatUserText : AppColors.chatAssistantText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.role == .user ? AppColors.chatUserBubble : AppColors.chatAssistantBubble,
                        in: ChatBubbleShape(isUser: message.role == .user)
                    )

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.role == .user ? "ユーザー" : "AIアシスタント"): \(message.content)")
    }
}

// チャットバブルの形状
struct ChatBubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        let tailRadius: CGFloat = 6

        var path = Path()

        if isUser {
            // ユーザー側（右下に尻尾）
            path.addRoundedRect(
                in: CGRect(x: rect.minX, y: rect.minY, width: rect.width - tailRadius, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius)
            )
            // 右下の尻尾
            path.move(to: CGPoint(x: rect.maxX - tailRadius, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.maxX - tailRadius, y: rect.maxY)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - tailRadius - 4, y: rect.maxY),
                control: CGPoint(x: rect.maxX - tailRadius, y: rect.maxY)
            )
        } else {
            // AI側（左下に尻尾）
            path.addRoundedRect(
                in: CGRect(x: rect.minX + tailRadius, y: rect.minY, width: rect.width - tailRadius, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius)
            )
            // 左下の尻尾
            path.move(to: CGPoint(x: rect.minX + tailRadius, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY),
                control: CGPoint(x: rect.minX + tailRadius, y: rect.maxY)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + tailRadius + 4, y: rect.maxY),
                control: CGPoint(x: rect.minX + tailRadius, y: rect.maxY)
            )
        }

        return path
    }
}

// MARK: - タイピングインジケーター（3つのドットが波打つアニメーション）

struct TypingIndicator: View {
    @State private var animationPhase = 0.0

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .offset(y: dotOffset(for: index))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 16))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    animationPhase = 1.0
                }
            }

            Spacer()
        }
        .accessibilityLabel("AIアシスタントが応答中")
    }

    private func dotOffset(for index: Int) -> CGFloat {
        let delay = Double(index) * 0.15
        let progress = max(0, animationPhase - delay)
        return -6 * sin(progress * .pi)
    }
}

// MARK: - ニーズ抽出結果カード

struct ExtractedNeedsCard: View {
    let needs: ExtractedNeeds

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.text.rectangle")
                    .foregroundStyle(.blue)
                Text("プロファイル情報を検出しました")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
            }

            ForEach(needs.summaryItems, id: \.label) { item in
                HStack(spacing: 8) {
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Text(item.value)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("検出されたプロファイル情報: \(needs.summaryItems.map { "\($0.label) \($0.value)" }.joined(separator: "、"))")
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
