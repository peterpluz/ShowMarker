import SwiftUI
import UniformTypeIdentifiers

struct ShowMarkerDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.data] }

    var project: Project = Project(name: "New Project")

    init() {}

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            return
        }

        let decoded = try JSONDecoder().decode(Project.self, from: data)
        self.project = decoded
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(project)
        return FileWrapper(regularFileWithContents: data)
    }
}
