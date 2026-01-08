import SwiftUI
import UniformTypeIdentifiers

struct ShowMarkerDocument: FileDocument {

    static var readableContentTypes: [UTType] {
        [.smark]
    }

    // ЕДИНСТВЕННЫЙ source of truth
    var file: ProjectFile

    // Удобный доступ для UI
    var project: Project {
        get { file.project }
        set { file.project = newValue }
    }

    // MARK: - New document

    init() {
        let project = Project(name: "New Project")
        self.file = ProjectFile(project: project)
    }

    // MARK: - Open document

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            let project = Project(name: "New Project")
            self.file = ProjectFile(project: project)
            return
        }

        let decoded = try JSONDecoder().decode(ProjectFile.self, from: data)

        guard decoded.formatVersion == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        self.file = decoded
    }

    // MARK: - Save

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(file)
        return FileWrapper(regularFileWithContents: data)
    }

    // MARK: - Mutations

    mutating func addTimeline(name: String) {
        let timeline = Timeline(name: name)
        file.project.timelines.append(timeline)
    }

    mutating func removeTimelines(at offsets: IndexSet) {
        file.project.timelines.remove(atOffsets: offsets)
    }

    mutating func renameTimeline(id: UUID, name: String) {
        guard let index = file.project.timelines.firstIndex(where: { $0.id == id }) else {
            return
        }
        file.project.timelines[index].name = name
    }

    mutating func moveTimelines(from source: IndexSet, to destination: Int) {
        file.project.timelines.move(fromOffsets: source, toOffset: destination)
    }
}
