import Foundation

struct ProjectSettings: Codable, Sendable {
    var tags: [Tag]
    var defaultFPS: Int
    var isMarkerHapticFeedbackEnabled: Bool

    init(
        tags: [Tag] = Tag.defaultTags,
        defaultFPS: Int = 25,
        isMarkerHapticFeedbackEnabled: Bool = true
    ) {
        self.tags = tags
        self.defaultFPS = defaultFPS
        self.isMarkerHapticFeedbackEnabled = isMarkerHapticFeedbackEnabled
    }
}
