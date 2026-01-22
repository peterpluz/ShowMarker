import Foundation

// ✅ ИСПРАВЛЕНО: добавлен Sendable
struct TimelineMarker: Codable, Identifiable, Sendable {
    let id: UUID
    var timeSeconds: Double      // БАЗОВОЕ хранение
    var name: String
    var tagId: UUID              // Reference to Tag
    let createdAt: Date

    init(
        id: UUID = UUID(),
        timeSeconds: Double,
        name: String,
        tagId: UUID,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.timeSeconds = timeSeconds
        self.name = name
        self.tagId = tagId
        self.createdAt = createdAt
    }
}
