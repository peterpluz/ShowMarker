import SwiftUI
import UniformTypeIdentifiers

struct ShowMarkerDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.data] }

    // временная модель проекта
    var projectName: String = "New Project"

    init() {}

    init(configuration: ReadConfiguration) throws {
        // позже будет загрузка из файла
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // позже будет сохранение
        FileWrapper(regularFileWithContents: Data())
    }
}
