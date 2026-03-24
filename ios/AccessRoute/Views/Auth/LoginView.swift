import SwiftUI

// ログイン画面
struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var showAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 80)

                headerSection

                Spacer()
                    .frame(height: 48)

                formSection
            }
            .padding(.horizontal, 24)
        }
        .background(Color(.systemGray6))
        .scrollDismissesKeyboard(.interactively)
        .alert("エラー", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(authViewModel.errorMessage ?? "")
        }
        .onChange(of: authViewModel.errorMessage) { _, newValue in
            if newValue != nil {
                showAlert = true
            }
        }
    }

    // ヘッダー部分
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("フェスマップ")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.blue)

            Text("学園祭コンシェルジュ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // フォーム部分
    private var formSection: some View {
        VStack(spacing: 0) {
            // ゲストログインボタン（APIキー未設定時はオフラインモードで続行）
            Button {
                Task {
                    if AppConfig.firebaseAPIKey.isEmpty {
                        // APIキー未設定時はオフラインモードで直接メイン画面へ
                        authViewModel.isAuthenticated = true
                    } else {
                        await authViewModel.signInAsGuest()
                    }
                }
            } label: {
                Text("ゲストとして続ける")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.blue, lineWidth: 2)
                    )
            }
            .disabled(authViewModel.isLoading)
            .accessibilityLabel("ゲストとして続ける")

            // 区切り線
            divider
                .padding(.vertical, 24)

            // メールアドレス入力
            TextField("メールアドレス", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 1)
                )
                .disabled(authViewModel.isLoading)
                .accessibilityLabel("メールアドレス")
                .padding(.bottom, 12)

            // パスワード入力
            SecureField("パスワード", text: $password)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 1)
                )
                .disabled(authViewModel.isLoading)
                .accessibilityLabel("パスワード")
                .padding(.bottom, 16)

            // ログイン/新規登録ボタン
            Button {
                Task { await handleEmailAuth() }
            } label: {
                Group {
                    if authViewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(isSignUp ? "新規登録" : "ログイン")
                            .fontWeight(.semibold)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.blue, in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(authViewModel.isLoading)
            .accessibilityLabel(isSignUp ? "新規登録" : "ログイン")

            // 切替リンク
            Button {
                isSignUp.toggle()
            } label: {
                Text(isSignUp
                    ? "既にアカウントをお持ちの方はこちら"
                    : "アカウントをお持ちでない方はこちら")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }
            .disabled(authViewModel.isLoading)
            .padding(.top, 16)
        }
    }

    // 区切り線
    private var divider: some View {
        HStack {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1)
            Text("または")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1)
        }
    }

    // メール認証処理
    private func handleEmailAuth() async {
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty,
              !password.trimmingCharacters(in: .whitespaces).isEmpty else {
            authViewModel.errorMessage = "メールアドレスとパスワードを入力してください"
            return
        }
        guard password.count >= 6 else {
            authViewModel.errorMessage = "パスワードは6文字以上で入力してください"
            return
        }

        if isSignUp {
            await authViewModel.signUpWithEmail(email, password)
        } else {
            await authViewModel.signInWithEmail(email, password)
        }
    }
}
