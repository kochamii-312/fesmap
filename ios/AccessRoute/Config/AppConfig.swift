import Foundation

// アプリ設定・環境管理
enum AppConfig {
    // MARK: - バージョン情報

    // アプリバージョン（セマンティックバージョニング）
    static let appVersion = "1.0.0"

    // ビルド番号
    static let buildNumber = "1"

    // 表示用バージョン文字列
    static var displayVersion: String {
        "\(appVersion) (\(buildNumber))"
    }

    // MARK: - 環境設定

    // 現在の環境
    static let environment: Environment = {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }()

    // 環境の種類
    enum Environment: String {
        case development
        case staging
        case production

        // 環境名（表示用）
        var displayName: String {
            switch self {
            case .development: return "開発"
            case .staging: return "ステージング"
            case .production: return "本番"
            }
        }
    }

    // MARK: - Firebase設定

    // Firebase APIキー（Info.plistから取得、フォールバック用に空文字）
    static var firebaseAPIKey: String {
        Bundle.main.infoDictionary?["FIREBASE_API_KEY"] as? String ?? ""
    }

    // Google Maps APIキー
    static let googleMapsAPIKey = "AIzaSyChnBsPbggORaeE9Kas8fcfzg52CQ7Vgp4"

    // Yahoo! YOLP アプリケーションID
    static var yolpAppId: String {
        Bundle.main.infoDictionary?["YOLP_APP_ID"] as? String
            ?? "dmVyPTIwMjUwNyZpZD1IOXlmQjZsVXU4Jmhhc2g9TkdGaVpUY3dZMlk1WlRjell6STNaZw"
    }

    // MARK: - API設定

    // APIベースURL（環境ごとに切替）
    static var apiBaseURL: String {
        switch environment {
        case .development:
            return "http://localhost:5001/accessroute-18207/asia-northeast1/api/api"
        case .staging:
            return "https://asia-northeast1-accessroute-staging.cloudfunctions.net/api/api"
        case .production:
            return "https://asia-northeast1-accessroute-18207.cloudfunctions.net/api/api"
        }
    }

    // AIサーバーURL
    static var aiServerURL: String {
        switch environment {
        case .development, .staging, .production:
            return "https://unopiatic-vonnie-compressibly.ngrok-free.dev"
        }
    }

    // APIタイムアウト（秒）
    static let apiTimeout: TimeInterval = 30

    // SSEストリーミングタイムアウト（秒）
    static let sseTimeout: TimeInterval = 120

    // MARK: - キャッシュ設定

    // 画像キャッシュ最大枚数
    static let imageCacheCountLimit = 50

    // 画像キャッシュ最大サイズ（バイト）
    static let imageCacheSizeLimit = 50 * 1024 * 1024

    // MARK: - デバッグ設定

    // デバッグモードかどうか
    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // ログ出力を有効にするか
    static var isLoggingEnabled: Bool {
        isDebug
    }

    // MARK: - アプリ情報

    // Bundle IDから取得するバージョン情報
    static var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? appVersion
    }

    static var bundleBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? buildNumber
    }

    // アプリ名
    static var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "フェスマップ"
    }
}
