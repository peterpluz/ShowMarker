import SwiftUI
import UniformTypeIdentifiers
import Combine

final class ShowMarkerDocument: ReferenceFileDocument, ObservableObject {

    static var readableContentTypes: [UTType] {
        [.smark]
    }

    // Храним весь файл целиком
    @Published private(set) var file: ProjectFile

    // Доступ к проекту (только через document)
    var project: Project {
        file.project
    }

    // MARK: - Init

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

        // Контроль версии формата
        switch decoded.formatVersion {
        case 1:
            self.file = decoded
        default:
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    // MARK: - ReferenceFileDocument

    func snapshot(contentType: UTType) throws -> ProjectFile {
        file
    }

    func fileWrapper(
        snapshot: ProjectFile,
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        let data = try JSONEncoder().encode(snapshot)
        return .init(regularFileWithContents: data)
    }

    // MARK: - Project mutations (Единственная точка бизнес-логики)

    func renameProject(_ name: String) {
        file.project.name = name
    }

    func addTimeline(name: String) {
        let timeline = Timeline(name: name)
        file.project.timelines.append(timeline)
    }

    func removeTimeline(id: UUID) {
        file.project.timelines.removeAll { $0.id == id }
    }
}
