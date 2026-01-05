import SwiftUI
import UniformTypeIdentifiers

struct ShowMarkerDocument: FileDocument {

    static var readableContentTypes: [UTType] {
        [.smark]
    }

    var project: Project

    init() {
        self.project = Project(name: "New Project")
    }

    init(configuration: ReadConfiguration) throws {
        guard
            let data = configuration.file.regularFileContents
        else {
            self.project = Project(name: "New Project")
            return
        }

        self.project = try JSONDecoder().decode(Project.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(project)
        return .init(regularFileWithContents: data)
    }
}
