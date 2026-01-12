import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct ShowMarkerDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.smark] }
    static var writableContentTypes: [UTType] { [.smark] }

    var file: ProjectFile
    var audioFiles: [String: Data] = [:]

    init() {
        // По умолчанию проект с глобальным FPS = 30
        self.file = ProjectFile(project: Project(name: "New Project", fps: 30))
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

    // MARK: - Project-wide FPS change (миграция маркеров)

    /// Меняет глобальный FPS проекта на newFPS.
    /// При этом пересчитывает все маркеры так, чтобы позиция во времени не изменилась визуально:
    /// frames = round(timeSeconds * oldFPS)
    /// newSeconds = Double(frames) / Double(newFPS)
    mutating func setProjectFPS(_ newFPS: Int) {
        guard newFPS > 0 else { return }
        let oldFPS = file.project.fps
        guard oldFPS != newFPS else { return }

        for tIndex in file.project.timelines.indices {
            // Пересчёт маркеров
            for mIndex in file.project.timelines[tIndex].markers.indices {
                let oldSeconds = file.project.timelines[tIndex].markers[mIndex].timeSeconds
                let frames = Int(round(oldSeconds * Double(oldFPS)))
                let newSeconds = Double(frames) / Double(newFPS)
                file.project.timelines[tIndex].markers[mIndex].timeSeconds = newSeconds
            }

            // Синхронизируем поле fps в таймлайне (для совместимости)
            file.project.timelines[tIndex].fps = newFPS
        }

        // Устанавливаем новый глобальный FPS
        file.project.fps = newFPS
    }
}
