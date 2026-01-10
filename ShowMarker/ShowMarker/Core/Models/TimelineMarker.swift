import Foundation

struct TimelineMarker: Codable, Identifiable {
    let id: UUID
    var timeSeconds: Double      // БАЗОВОЕ хранение
    var name: String
    var tag: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        timeSeconds: Double,
        name: String,
        tag: String = "Default",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.timeSeconds = timeSeconds
        self.name = name
        self.tag = tag
        self.createdAt = createdAt
    }
}
