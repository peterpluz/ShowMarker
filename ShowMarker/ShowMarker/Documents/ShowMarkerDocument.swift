import SwiftUI
import UniformTypeIdentifiers

struct ShowMarkerDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.data] }

    var project: Project = Project(name: "New Project")

    init() {}

    init(configuration: ReadConfiguration) throws {
        // позже загрузка
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // позже сохранение
        FileWrapper(regularFileWithContents: Data())
    }
}
