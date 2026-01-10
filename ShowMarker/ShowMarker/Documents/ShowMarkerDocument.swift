import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct ShowMarkerDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.smark] }
    static var writableContentTypes: [UTType] { [.smark] }

    var file: ProjectFile
    var audioFiles: [String: Data] = [:]

    // MARK: - New document

    init() {
        self.file = ProjectFile(project: Project(name: "New Project"))
        self.audioFiles = [:]
    }

    // MARK: - Open

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

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {

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
        file.project.timelines.append(Timeline(name: name))
    }

    mutating func removeTimelines(at offsets: IndexSet) {
        file.project.timelines.remove(atOffsets: offsets)
    }

    mutating func moveTimelines(from source: IndexSet, to destination: Int) {
        file.project.timelines.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Marker ops

    mutating func addMarker(timelineID: UUID, marker: TimelineMarker) {
        guard let index = file.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        file.project.timelines[index].markers.append(marker)
    }

    mutating func updateMarker(timelineID: UUID, marker: TimelineMarker) {
        guard
            let tIndex = file.project.timelines.firstIndex(where: { $0.id == timelineID }),
            let mIndex = file.project.timelines[tIndex]
                .markers
                .firstIndex(where: { $0.id == marker.id })
        else { return }

        file.project.timelines[tIndex].markers[mIndex] = marker
    }

    mutating func removeMarker(timelineID: UUID, markerID: UUID) {
        guard let index = file.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        file.project.timelines[index].markers.removeAll { $0.id == markerID }
    }
}
