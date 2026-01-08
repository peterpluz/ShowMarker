import SwiftUI
import UniformTypeIdentifiers
import Combine

final class ShowMarkerDocument: ReferenceFileDocument, ObservableObject {

    static var readableContentTypes: [UTType] {
        [.smark]
    }

    // Храним весь файл целиком
    @Published private(set) var file: ProjectFile

    // Удобный доступ для UI
    var project: Project {
        get { file.project }
        set { file.project = newValue }
    }

    // Создание нового документа
    init() {
        let project = Project(name: "New Project")
        self.file = ProjectFile(project: project)
    }

    // Открытие существующего файла
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            let project = Project(name: "New Project")
            self.file = ProjectFile(project: project)
            return
        }

        let decoded = try JSONDecoder().decode(ProjectFile.self, from: data)

        // Подготовка к будущим миграциям
        switch decoded.formatVersion {
        case 1:
            self.file = decoded
        default:
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    // Snapshot для сохранения
    func snapshot(contentType: UTType) throws -> ProjectFile {
        file
    }

    // Запись на диск
    func fileWrapper(
        snapshot: ProjectFile,
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        let data = try JSONEncoder().encode(snapshot)
        return .init(regularFileWithContents: data)
    }
}
