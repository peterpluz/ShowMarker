import Foundation

struct ProjectFile: Codable {
    let formatVersion: Int
    var project: Project

    init(project: Project) {
        self.formatVersion = 1
        self.project = project
    }
}
