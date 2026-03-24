import Foundation

struct FestivalProject: Codable, Identifiable {
    var id: String { projectId }
    let projectId: String
    let name: String
    let organization: String
    let description: String
    let classification: String
    let form: String
    let location: String
    let detailedLocation: String
    let latitude: Double
    let longitude: Double
    let isAccessible: Bool
    let tags: [String]
    let startTime: String?
    let endTime: String?
}
