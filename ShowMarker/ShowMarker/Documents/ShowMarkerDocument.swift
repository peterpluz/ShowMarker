import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct ShowMarkerDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.smark] }

    var file: ProjectFile

    // MARK: - Init (new)

    init() {
        self.file = ProjectFile(
            project: Project(name: "New Project")
        )
    }

    // MARK: - Init (open)

    init(configuration: ReadConfiguration) throws {
        guard
            let wrappers = configuration.file.fileWrappers,
            let projectWrapper = wrappers["project.json"],
            let data = projectWrapper.regularFileContents
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoded = try JSONDecoder().decode(ProjectFile.self, from: data)
        guard decoded.formatVersion == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        self.file = decoded
    }

    // MARK: - Save (package)

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {

        let projectData = try JSONEncoder().encode(file)

        let wrappers: [String: FileWrapper] = [
            "project.json": FileWrapper(
                regularFileWithContents: projectData
            ),
            "Audio": FileWrapper(
                directoryWithFileWrappers: [:]
            )
        ]

        return FileWrapper(
            directoryWithFileWrappers: wrappers
        )
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

    // MARK: - Audio (временно)

    mutating func addAudio(
        to timelineID: UUID,
        sourceURL: URL,
        duration: Double
    ) throws {
        guard let index = file.project.timelines.firstIndex(where: { $0.id == timelineID }) else {
            return
        }

        let relativePath = try AudioStorage.copyToProject(from: sourceURL)

        file.project.timelines[index].audio = TimelineAudio(
            relativePath: relativePath,
            originalFileName: sourceURL.lastPathComponent,
            duration: duration
        )
    }
}
