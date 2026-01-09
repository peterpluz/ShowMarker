import SwiftUI
import UniformTypeIdentifiers
import Foundation
import Combine

final class ShowMarkerDocument: ReferenceFileDocument, ObservableObject {

    // MARK: - ReferenceFileDocument config

    static var readableContentTypes: [UTType] { [.smark] }
    static var writableContentTypes: [UTType] { [.smark] }

    // Snapshot = immutable state for saving
    typealias Snapshot = (project: ProjectFile, audioFiles: [String: Data])

    // MARK: - Source of truth (LIVE STATE)

    @Published var file: ProjectFile
    @Published var audioFiles: [String: Data]

    // MARK: - New document

    init() {
        self.file = ProjectFile(project: Project(name: "New Project"))
        self.audioFiles = [:]
    }

    // MARK: - Open existing document

    required init(configuration: ReadConfiguration) throws {
        let wrapper = configuration.file

        guard
            wrapper.isDirectory,
            let wrappers = wrapper.fileWrappers,
            let projectWrapper = wrappers["project.json"],
            let data = projectWrapper.regularFileContents
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        self.file = try JSONDecoder().decode(ProjectFile.self, from: data)
        self.audioFiles = [:]

        for (path, fw) in wrappers where path.hasPrefix("Audio/") {
            if let bytes = fw.regularFileContents {
                let name = URL(fileURLWithPath: path).lastPathComponent
                audioFiles[name] = bytes
            }
        }
    }

    // MARK: - Snapshot (CRITICAL)

    func snapshot(contentType: UTType) throws -> Snapshot {
        // Immutable copy for save operation
        (project: file, audioFiles: audioFiles)
    }

    // MARK: - Save document

    func fileWrapper(
        snapshot: Snapshot,
        configuration: WriteConfiguration
    ) throws -> FileWrapper {

        let projectData = try JSONEncoder().encode(snapshot.project)
        let projectWrapper = FileWrapper(regularFileWithContents: projectData)

        var wrappers: [String: FileWrapper] = [
            "project.json": projectWrapper
        ]

        for (name, data) in snapshot.audioFiles {
            wrappers["Audio/\(name)"] = FileWrapper(regularFileWithContents: data)
        }

        return FileWrapper(directoryWithFileWrappers: wrappers)
    }

    // MARK: - Timeline ops

    func addTimeline(name: String) {
        file.project.timelines.append(Timeline(name: name))
    }

    func renameTimeline(id: UUID, name: String) {
        guard let index = file.project.timelines.firstIndex(where: { $0.id == id }) else { return }
        file.project.timelines[index].name = name
    }

    func removeTimelines(at offsets: IndexSet) {
        file.project.timelines.remove(atOffsets: offsets)
    }

    func moveTimelines(from source: IndexSet, to destination: Int) {
        file.project.timelines.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Audio

    func addAudio(
        to timelineID: UUID,
        sourceURL: URL,
        duration: Double
    ) throws {
        guard let index = file.project.timelines.firstIndex(where: { $0.id == timelineID }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let ext = sourceURL.pathExtension
        let fileName = UUID().uuidString + "." + ext
        let data = try Data(contentsOf: sourceURL)

        audioFiles[fileName] = data

        file.project.timelines[index].audio = TimelineAudio(
            relativePath: "Audio/\(fileName)",
            originalFileName: sourceURL.lastPathComponent,
            duration: duration
        )
    }
}
