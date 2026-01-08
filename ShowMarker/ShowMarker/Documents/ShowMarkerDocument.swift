import SwiftUI
import UniformTypeIdentifiers
import Combine

@MainActor
final class ShowMarkerDocument: ReferenceFileDocument, ObservableObject {

    static var readableContentTypes: [UTType] {
        [.smark]
    }

    // Весь файл целиком — единая точка истины
    @Published private(set) var file: ProjectFile

    // Только чтение проекта для UI
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

    // MARK: - Mutations
    // ❗️ВАЖНО: каждая мутация = новое присваивание file

    func addTimeline(name: String) {
        var updated = file
        updated.project.timelines.append(Timeline(name: name))
        file = updated
    }

    func removeTimeline(id: UUID) {
        var updated = file
        updated.project.timelines.removeAll { $0.id == id }
        file = updated
    }

    func removeTimelines(at offsets: IndexSet) {
        var updated = file
        updated.project.timelines.remove(atOffsets: offsets)
        file = updated
    }

    func renameTimeline(id: UUID, name: String) {
        var updated = file
        guard let index = updated.project.timelines.firstIndex(where: { $0.id == id }) else {
            return
        }
        updated.project.timelines[index].name = name
        file = updated
    }

    func moveTimelines(from source: IndexSet, to destination: Int) {
        var updated = file
        updated.project.timelines.move(fromOffsets: source, toOffset: destination)
        file = updated
    }
}
