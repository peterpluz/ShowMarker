import Foundation

struct Project: Codable, Identifiable {
    let id: UUID
    var name: String
    /// Глобальный FPS проекта (25,30,50,60,100)
    var fps: Int
    var timelines: [Timeline]

    init(name: String, fps: Int = 30) {
        self.id = UUID()
        self.name = name
        self.fps = fps
        self.timelines = []
    }
}
