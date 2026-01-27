import Foundation

// ✅ ИСПРАВЛЕНО: добавлен Sendable для Swift 6
struct Project: Codable, Identifiable, Sendable {
    static let currentFormatVersion = 2  // Increased for tags support

    let formatVersion: Int
    let id: UUID
    var name: String
    var fps: Int
    var tags: [Tag]                      // Global project tags
    var timelines: [Timeline]
    var isMarkerHapticFeedbackEnabled: Bool = true

    init(
        name: String,
        fps: Int = 30,
        tags: [Tag] = Tag.defaultTags,
        isMarkerHapticFeedbackEnabled: Bool = true,
        formatVersion: Int = Self.currentFormatVersion
    ) {
        self.formatVersion = formatVersion
        self.id = UUID()
        self.name = name
        self.fps = fps
        self.tags = tags
        self.isMarkerHapticFeedbackEnabled = isMarkerHapticFeedbackEnabled
        self.timelines = []
    }
}
