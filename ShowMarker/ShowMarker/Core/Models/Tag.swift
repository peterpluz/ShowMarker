import Foundation

struct Tag: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String  // Format: "#FF0000"
    var order: Int

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.order = order
    }

    // Default tags for new projects
    static var defaultTags: [Tag] {
        [
            Tag(id: UUID(), name: "Light", colorHex: "#FF3B30", order: 0),   // Red
            Tag(id: UUID(), name: "Video", colorHex: "#007AFF", order: 1),   // Blue
            Tag(id: UUID(), name: "SFX", colorHex: "#34C759", order: 2)      // Green
        ]
    }
}
