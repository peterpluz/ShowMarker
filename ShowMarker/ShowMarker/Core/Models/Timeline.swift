import Foundation

struct Timeline: Codable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    var audio: TimelineAudio?

    /// FPS таймлайна (25 / 30 / 50 / 60 / 100)
    var fps: Int

    /// Маркеры таймлайна
    var markers: [TimelineMarker]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        audio: TimelineAudio? = nil,
        fps: Int = 30,
        markers: [TimelineMarker] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.audio = audio
        self.fps = fps
        self.markers = markers
    }
}
