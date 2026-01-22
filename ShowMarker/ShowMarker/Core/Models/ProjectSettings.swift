import Foundation

struct ProjectSettings: Codable, Sendable {
    var tags: [Tag]
    var defaultFPS: Int

    init(
        tags: [Tag] = Tag.defaultTags,
        defaultFPS: Int = 25
    ) {
        self.tags = tags
        self.defaultFPS = defaultFPS
    }
}
