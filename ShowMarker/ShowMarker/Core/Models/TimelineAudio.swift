import Foundation

// ✅ ИСПРАВЛЕНО: добавлен Sendable
struct TimelineAudio: Codable, Identifiable, Sendable {
    let id: UUID
    let relativePath: String      // Audio/xxxx.ext
    let originalFileName: String
    let duration: Double

    init(
        relativePath: String,
        originalFileName: String,
        duration: Double
    ) {
        self.id = UUID()
        self.relativePath = relativePath
        self.originalFileName = originalFileName
        self.duration = duration
    }
}
