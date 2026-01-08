import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct ShowMarkerDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.smark] }

    var file: ProjectFile

    init() {
        file = ProjectFile(project: Project(name: "New Project"))
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            file = try JSONDecoder().decode(ProjectFile.self, from: data)
        } else {
            file = ProjectFile(project: Project(name: "New Project"))
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(file)
        return FileWrapper(regularFileWithContents: data)
    }
}
