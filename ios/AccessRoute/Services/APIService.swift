import Foundation

// API通信エラー
enum APIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case unauthorized
    case notFound
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "無効なURLです"
        case .networkError(let error):
            return "通信エラー: \(error.localizedDescription)"
        case .decodingError(let error):
            return "データ変換エラー: \(error.localizedDescription)"
        case .unauthorized:
            return "認証エラー。再ログインしてください"
        case .notFound:
            return "データが見つかりません"
        case .serverError(let code):
            return "サーバーエラー (コード: \(code))"
        }
    }
}

// API通信サービス
actor APIService {
    static let shared = APIService()

    // AppConfigから環境別ベースURLを取得
    private let baseURL = AppConfig.apiBaseURL

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private init() {}

    // MARK: - ユーザープロファイル

    // プロファイル取得
    func getProfile(token: String) async throws -> UserProfile {
        return try await request(method: "GET", path: "/auth/profile", token: token)
    }

    // プロファイル作成・更新
    func saveProfile(input: UserProfileInput, token: String) async throws -> UserProfile {
        return try await request(method: "POST", path: "/auth/profile", body: input, token: token)
    }

    // MARK: - ルート検索

    // バリアフリールート検索
    func searchRoute(request routeRequest: RouteRequest, token: String) async throws -> RouteResponse {
        return try await request(method: "POST", path: "/route/search", body: routeRequest, token: token)
    }

    // MARK: - スポット

    // 周辺スポット検索
    func getNearbySpots(
        lat: Double,
        lng: Double,
        radiusMeters: Int = 500,
        category: SpotCategory? = nil,
        token: String
    ) async throws -> [SpotSummary] {
        var queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
            URLQueryItem(name: "radiusMeters", value: String(radiusMeters))
        ]
        if let category = category {
            queryItems.append(URLQueryItem(name: "category", value: category.rawValue))
        }

        struct SpotsResponse: Codable {
            let spots: [SpotSummary]
        }
        let response: SpotsResponse = try await request(
            method: "GET",
            path: "/spots/nearby",
            queryItems: queryItems,
            token: token
        )
        return response.spots
    }

    // スポット詳細取得
    func getSpotDetail(spotId: String, token: String) async throws -> SpotDetail {
        return try await request(method: "GET", path: "/spots/\(spotId)", token: token)
    }

    // MARK: - AIチャット

    // チャットメッセージ送信
    func sendChatMessage(
        userId: String,
        message: String,
        conversationHistory: [[String: String]],
        token: String
    ) async throws -> ChatResponse {
        let chatRequest = ChatRequest(
            userId: userId,
            message: message,
            conversationHistory: conversationHistory
        )
        return try await request(method: "POST", path: "/chat", body: chatRequest, token: token)
    }

    // SSEストリーミングでチャット応答を受信
    func streamChatMessage(
        userId: String,
        message: String,
        conversationHistory: [[String: String]],
        token: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        let chatRequest = ChatRequest(
            userId: userId,
            message: message,
            conversationHistory: conversationHistory
        )

        guard let url = URL(string: baseURL + "/chat") else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try encoder.encode(chatRequest)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        // SSEフォーマット: "data: ..."
                        guard line.hasPrefix("data: ") else { continue }
                        let data = String(line.dropFirst(6))
                        if data == "[DONE]" {
                            break
                        }
                        continuation.yield(data)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // 会話からニーズ抽出
    func extractNeeds(
        userId: String,
        conversationHistory: [[String: String]],
        token: String
    ) async throws -> ExtractNeedsResponse {
        let extractRequest = ExtractNeedsRequest(
            userId: userId,
            conversationHistory: conversationHistory
        )
        return try await request(method: "POST", path: "/extract-needs", body: extractRequest, token: token)
    }

    // MARK: - 共通リクエスト処理

    private func request<T: Decodable>(
        method: String,
        path: String,
        body: (some Encodable)? = nil as String?,
        queryItems: [URLQueryItem]? = nil,
        token: String
    ) async throws -> T {
        guard var components = URLComponents(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        if let queryItems = queryItems {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            urlRequest.httpBody = try encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}

// MARK: - YOLP (Yahoo! Open Local Platform)

// YOLPのレスポンスをデコードするための構造体
private struct YOLPResponse: Codable {
    let feature: [YOLPFeature]?

    enum CodingKeys: String, CodingKey {
        case feature = "Feature"
    }
}

private struct YOLPFeature: Codable {
    let id: String // swiftlint:disable:this identifier_name
    let name: String?
    let geometry: YOLPGeometry?
    let category: [String]?
    let property: YOLPProperty?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case geometry = "Geometry"
        case category = "Category"
        case property = "Property"
    }

    struct YOLPGeometry: Codable {
        let coordinates: String? // "経度,緯度"

        enum CodingKeys: String, CodingKey {
            case coordinates = "Coordinates"
        }
    }
    struct YOLPProperty: Codable {
        let address: String?
        let tel1: String?
        let gid: String?

        enum CodingKeys: String, CodingKey {
            case address = "Address"
            case tel1 = "Tel1"
            case gid = "Gid"
        }
    }
}

extension APIService {
    // YOLPで周辺スポットを検索
    func searchNearbySpotsYOLP(
        lat: Double,
        lng: Double,
        appId: String,
        dist: Int = 1000, // 検索半径(m)
        query: String? = nil // 検索キーワード
    ) async throws -> [SpotSummary] {
        
        guard var components = URLComponents(string: "https://map.yahooapis.jp/search/local/V1/localSearch") else {
            throw APIError.invalidURL
        }

        // YOLP の dist パラメータは km 単位（範囲: 0.001〜50）
        let distKm = min(Double(dist) / 1000.0, 50.0)

        var queryItems = [
            URLQueryItem(name: "appid", value: appId),
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lng)),
            URLQueryItem(name: "dist", value: String(distKm)),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "sort", value: "dist"), // 距離順でソート
        ]
        if let query = query {
            queryItems.append(URLQueryItem(name: "query", value: query))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        let yolpResponse = try decoder.decode(YOLPResponse.self, from: data)

        // YOLPのレスポンス ([YOLPFeature]) をアプリの共通モデル ([SpotSummary]) に変換
        let spots = yolpResponse.feature?.compactMap { feature -> SpotSummary? in
            guard let name = feature.name,
                  let coordinatesString = feature.geometry?.coordinates else {
                return nil
            }

            let coordinates = coordinatesString.split(separator: ",").compactMap { Double($0) }
            guard coordinates.count == 2 else { return nil }
            let spotLng = coordinates[0]
            let spotLat = coordinates[1]

            // YOLPのカテゴリをアプリのカテゴリに大まかにマッピング (簡易版)
            let spotCategory: SpotCategory = {
                guard let yolpCategory = feature.category?.first else { return .other }
                if yolpCategory.contains("カフェ") { return .cafe }
                if yolpCategory.contains("トイレ") { return .restroom }
                if yolpCategory.contains("レストラン") { return .restaurant }
                if yolpCategory.contains("公園") { return .park }
                return .other
            }()

            return SpotSummary(
                spotId: feature.property?.gid ?? UUID().uuidString,
                name: name,
                category: spotCategory,
                location: LatLng(lat: spotLat, lng: spotLng),
                accessibilityScore: 50,
                distanceFromRoute: 0
            )
        }

        return spots ?? []
    }
}
