import Foundation

struct Timeline: Codable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    var audio: TimelineAudio?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        audio: TimelineAudio? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.audio = audio
    }
}
