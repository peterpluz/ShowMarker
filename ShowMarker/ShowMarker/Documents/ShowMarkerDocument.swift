import SwiftUI
import UniformTypeIdentifiers

struct ShowMarkerDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.data] }

    init() {}

    init(configuration: ReadConfiguration) throws {
        // пока пусто
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data())
    }
}
