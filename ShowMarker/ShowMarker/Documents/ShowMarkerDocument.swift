import SwiftUI
import UniformTypeIdentifiers
import Foundation

@MainActor
struct ShowMarkerDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.smark] }

    var file: ProjectFile

    init() {
        self.file = ProjectFile(project: Project(name: "New Project"))
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            let decoded = try JSONDecoder().decode(ProjectFile.self, from: data)
            guard decoded.formatVersion == 1 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            self.file = decoded
        } else {
            self.file = ProjectFile(project: Project(name: "New Project"))
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(file)
        return FileWrapper(regularFileWithContents: data)
    }

    // MARK: - Timelines

    mutating func addTimeline(name: String) {
        file.project.timelines.append(Timeline(name: name))
    }

    mutating func removeTimelines(at offsets: IndexSet) {
        file.project.timelines.remove(atOffsets: offsets)
    }

    mutating func moveTimelines(from source: IndexSet, to destination: Int) {
        file.project.timelines.move(fromOffsets: source, toOffset: destination)
    }

    mutating func renameTimeline(id: UUID, name: String) {
        guard let index = file.project.timelines.firstIndex(where: { $0.id == id }) else { return }
        file.project.timelines[index].name = name
    }

    // MARK: - Audio

    mutating func addAudio(
        to timelineID: UUID,
        fileName: String,
        duration: Double
    ) {
        guard let index = file.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }

        file.project.timelines[index].audio = TimelineAudio(
            fileName: fileName,
            duration: duration
        )
    }
}
