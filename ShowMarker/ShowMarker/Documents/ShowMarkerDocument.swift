import SwiftUI
import UniformTypeIdentifiers
import Combine

final class ShowMarkerDocument: ReferenceFileDocument, ObservableObject {

    static var readableContentTypes: [UTType] {
        [.smark]
    }

    // Весь файл целиком
    @Published private(set) var file: ProjectFile

    // Только чтение проекта
    var project: Project {
        file.project
    }

    // MARK: - Init

    init() {
        let project = Project(name: "New Project")
        self.file = ProjectFile(project: project)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            let project = Project(name: "New Project")
            self.file = ProjectFile(project: project)
            return
        }

        // ⚠️ ВАЖНО: decode вне main-actor
        let decodedFile = try JSONDecoder().decode(ProjectFile.self, from: data)

        switch decodedFile.formatVersion {
        case 1:
            self.file = decodedFile
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

    // MARK: - Mutations (ЕДИНСТВЕННАЯ точка изменений)

    func addTimeline(name: String) {
        let timeline = Timeline(name: name)
        file.project.timelines.append(timeline)
    }

    func removeTimeline(id: UUID) {
        file.project.timelines.removeAll { $0.id == id }
    }

    // ✅ НОВОЕ — для List.onDelete
    func removeTimelines(at offsets: IndexSet) {
        file.project.timelines.remove(atOffsets: offsets)
    }

    func renameTimeline(id: UUID, name: String) {
        guard let index = file.project.timelines.firstIndex(where: { $0.id == id }) else {
            return
        }
        file.project.timelines[index].name = name
    }
    // MARK: - Ordering

    func moveTimelines(from source: IndexSet, to destination: Int) {
        file.project.timelines.move(fromOffsets: source, toOffset: destination)
    }
}
