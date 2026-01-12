import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct ShowMarkerDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.smark] }
    static var writableContentTypes: [UTType] { [.smark] }

    var project: Project
    var audioFiles: [String: Data] = [:]

    init() {
        self.project = Project(name: "New Project", fps: 30)
        self.audioFiles = [:]
    }

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

        self.project = try JSONDecoder().decode(Project.self, from: data)
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

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {

        let projectData = try JSONEncoder().encode(project)
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
        project.timelines.append(Timeline(name: name))
    }

    mutating func removeTimelines(at offsets: IndexSet) {
        project.timelines.remove(atOffsets: offsets)
    }

    mutating func moveTimelines(from source: IndexSet, to destination: Int) {
        project.timelines.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Marker ops

    mutating func addMarker(timelineID: UUID, marker: TimelineMarker) {
        guard let index = project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        project.timelines[index].markers.append(marker)
    }

    mutating func updateMarker(timelineID: UUID, marker: TimelineMarker) {
        guard
            let tIndex = project.timelines.firstIndex(where: { $0.id == timelineID }),
            let mIndex = project.timelines[tIndex]
                .markers
                .firstIndex(where: { $0.id == marker.id })
        else { return }

        project.timelines[tIndex].markers[mIndex] = marker
    }

    mutating func removeMarker(timelineID: UUID, markerID: UUID) {
        guard let index = project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        project.timelines[index].markers.removeAll { $0.id == markerID }
    }

    // MARK: - Project-wide FPS change

    mutating func setProjectFPS(_ newFPS: Int) {
        guard newFPS > 0 else { return }
        let oldFPS = project.fps
        guard oldFPS != newFPS else { return }

        for tIndex in project.timelines.indices {
            // Пересчёт маркеров
            for mIndex in project.timelines[tIndex].markers.indices {
                let oldSeconds = project.timelines[tIndex].markers[mIndex].timeSeconds
                let frames = Int(round(oldSeconds * Double(oldFPS)))
                let newSeconds = Double(frames) / Double(newFPS)
                project.timelines[tIndex].markers[mIndex].timeSeconds = newSeconds
            }

            // Синхронизируем поле fps в таймлайне
            project.timelines[tIndex].fps = newFPS
        }

        project.fps = newFPS
    }
}
