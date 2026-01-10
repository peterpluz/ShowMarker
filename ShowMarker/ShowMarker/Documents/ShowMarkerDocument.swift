import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct ShowMarkerDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.smark] }
    static var writableContentTypes: [UTType] { [.smark] }

    var file: ProjectFile

    /// Audio bytes stored inside package
    var audioFiles: [String: Data] = [:]

    // MARK: - New document

    init() {
        self.file = ProjectFile(project: Project(name: "New Project"))
        self.audioFiles = [:]
    }

    // MARK: - Open existing package

    @MainActor
    init(configuration: ReadConfiguration) throws {
        let wrapper = configuration.file

        guard
            wrapper.isDirectory,
            let wrappers = wrapper.fileWrappers,
            let projectWrapper = wrappers["project.json"],
            let data = projectWrapper.regularFileContents
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        // Decoding occurs on main actor to match potential main-actor isolated model conformances
        self.file = try JSONDecoder().decode(ProjectFile.self, from: data)
        self.audioFiles = [:]

        if let audioDir = wrappers["Audio"],
           let audioWrappers = audioDir.fileWrappers {

            for (fileName, fw) in audioWrappers {
                if let bytes = fw.regularFileContents {
                    audioFiles[fileName] = bytes
                }
            }
        }
    }

    // MARK: - Save

    @MainActor
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {

        // Encoding occurs on main actor to match potential main-actor isolated model conformances
        let projectData = try JSONEncoder().encode(file)
        let projectWrapper = FileWrapper(regularFileWithContents: projectData)

        var root: [String: FileWrapper] = [
            "project.json": projectWrapper
        ]

        if !audioFiles.isEmpty {
            var audioWrappers: [String: FileWrapper] = [:]

            for (fileName, data) in audioFiles {
                audioWrappers[fileName] = FileWrapper(
                    regularFileWithContents: data
                )
            }

            root["Audio"] = FileWrapper(
                directoryWithFileWrappers: audioWrappers
            )
        }

        return FileWrapper(directoryWithFileWrappers: root)
    }

    // MARK: - Timeline ops

    mutating func addTimeline(name: String) {
        file.project.timelines.append(
            Timeline(name: name)
        )
    }

    mutating func renameTimeline(id: UUID, name: String) {
        guard let index = file.project.timelines.firstIndex(where: { $0.id == id }) else { return }
        file.project.timelines[index].name = name
    }

    mutating func removeTimelines(at offsets: IndexSet) {
        file.project.timelines.remove(atOffsets: offsets)
    }

    mutating func moveTimelines(from source: IndexSet, to destination: Int) {
        file.project.timelines.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Marker ops

    mutating func addMarker(
        timelineID: UUID,
        marker: TimelineMarker
    ) {
        guard let index = file.project.timelines.firstIndex(where: { $0.id == timelineID }) else {
            return
        }
        file.project.timelines[index].markers.append(marker)
    }

    mutating func updateMarker(
        timelineID: UUID,
        marker: TimelineMarker
    ) {
        guard
            let timelineIndex = file.project.timelines.firstIndex(where: { $0.id == timelineID }),
            let markerIndex = file.project.timelines[timelineIndex]
                .markers
                .firstIndex(where: { $0.id == marker.id })
        else { return }

        file.project.timelines[timelineIndex].markers[markerIndex] = marker
    }

    mutating func removeMarker(
        timelineID: UUID,
        markerID: UUID
    ) {
        guard let timelineIndex = file.project.timelines.firstIndex(where: { $0.id == timelineID }) else {
            return
        }

        file.project.timelines[timelineIndex]
            .markers
            .removeAll { $0.id == markerID }
    }

    // MARK: - Audio handling

    mutating func addAudio(
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

        // store bytes (persisted on save)
        audioFiles[fileName] = data

        file.project.timelines[index].audio = TimelineAudio(
            relativePath: "Audio/\(fileName)",
            originalFileName: sourceURL.lastPathComponent,
            duration: duration
        )
    }
}
