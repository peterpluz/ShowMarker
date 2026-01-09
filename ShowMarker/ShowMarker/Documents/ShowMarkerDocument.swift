import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct ShowMarkerDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.smark] }
    static var writableContentTypes: [UTType] { [.smark] }

    var file: ProjectFile

    // MARK: - New document

    init() {
        self.file = ProjectFile(
            project: Project(name: "New Project")
        )
    }

    // MARK: - Open existing package

    init(configuration: ReadConfiguration) throws {
        let wrapper = configuration.file

        guard
            wrapper.isDirectory,
            let projectWrapper = wrapper.fileWrappers?["project.json"],
            let data = projectWrapper.regularFileContents
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        self.file = try JSONDecoder().decode(ProjectFile.self, from: data)
    }

    // MARK: - Save as package

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {

        let data = try JSONEncoder().encode(file)

        let projectWrapper = FileWrapper(
            regularFileWithContents: data
        )
        projectWrapper.preferredFilename = "project.json"

        return FileWrapper(
            directoryWithFileWrappers: [
                "project.json": projectWrapper
            ]
        )
    }

    // MARK: - Timeline ops

    mutating func addTimeline(name: String) {
        file.project.timelines.append(Timeline(name: name))
    }

    mutating func renameTimeline(id: UUID, name: String) {
        guard let index = file.project.timelines.firstIndex(where: { $0.id == id }) else {
            return
        }
        file.project.timelines[index].name = name
    }

    mutating func removeTimelines(at offsets: IndexSet) {
        file.project.timelines.remove(atOffsets: offsets)
    }

    mutating func moveTimelines(from source: IndexSet, to destination: Int) {
        file.project.timelines.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Audio (model only, safe)

    mutating func addAudio(
        to timelineID: UUID,
        sourceURL: URL,
        duration: Double
    ) throws {

        guard let index = file.project.timelines.firstIndex(where: { $0.id == timelineID }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        file.project.timelines[index].audio = TimelineAudio(
            relativePath: "",
            originalFileName: sourceURL.lastPathComponent,
            duration: duration
        )
    }
}
