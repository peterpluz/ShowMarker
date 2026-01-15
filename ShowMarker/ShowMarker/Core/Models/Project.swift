import Foundation

struct Project: Codable, Identifiable, Sendable {
    nonisolated(unsafe) static let currentFormatVersion = 1
    
    let formatVersion: Int
    let id: UUID
    var name: String
    var fps: Int
    var timelines: [Timeline]

    init(
        name: String,
        fps: Int = 30,
        formatVersion: Int = Self.currentFormatVersion
    ) {
        self.formatVersion = formatVersion
        self.id = UUID()
        self.name = name
        self.fps = fps
        self.timelines = []
    }
}
