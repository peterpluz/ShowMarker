import Foundation

struct TimelineAudio: Codable, Identifiable {
    let id: UUID
    let fileName: String
    let duration: Double

    init(fileName: String, duration: Double) {
        self.id = UUID()
        self.fileName = fileName
        self.duration = duration
    }
}
