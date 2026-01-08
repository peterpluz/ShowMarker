import Foundation

struct Project: Codable, Identifiable {
    let id: UUID
    var name: String
    var timelines: [Timeline]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.timelines = []
    }
}
