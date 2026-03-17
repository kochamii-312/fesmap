import Foundation

// 場所検索候補
struct PlaceSuggestion: Codable, Identifiable {
    let description: String
    let placeId: String

    var id: String { placeId }

    enum CodingKeys: String, CodingKey {
        case description
        case placeId = "place_id"
    }
}
