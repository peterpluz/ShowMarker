import SwiftUI
import UniformTypeIdentifiers
import Combine

final class ShowMarkerDocument: ReferenceFileDocument, ObservableObject {

    static var readableContentTypes: [UTType] {
        [.smark]
    }

    @Published var project: Project

    init() {
        self.project = Project(name: "New Project")
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            self.project = Project(name: "New Project")
            return
        }
        self.project = try JSONDecoder().decode(Project.self, from: data)
    }

    func snapshot(contentType: UTType) throws -> Project {
        project
    }

    func fileWrapper(
        snapshot: Project,
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        let data = try JSONEncoder().encode(snapshot)
        return .init(regularFileWithContents: data)
    }
}
