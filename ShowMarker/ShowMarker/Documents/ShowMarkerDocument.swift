import SwiftUI
import UniformTypeIdentifiers
import Foundation

// MARK: - UTType Extension

extension UTType {
    static let smark = UTType(exportedAs: "com.peterpluz.showmarker.smark")
}

// MARK: - Document

struct ShowMarkerDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.smark] }
    static var writableContentTypes: [UTType] { [.smark] }

    var project: Project
    
    // URL документа для доступа к файлам
    var documentURL: URL?

    init() {
        self.project = Project(name: "New Project", fps: 30)
        self.documentURL = nil
    }

    nonisolated init(configuration: ReadConfiguration) throws {
        let wrapper = configuration.file

        guard
            wrapper.isDirectory,
            let wrappers = wrapper.fileWrappers,
            let projectWrapper = wrappers["project.json"],
            let data = projectWrapper.regularFileContents
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()
        self.project = try decoder.decode(Project.self, from: data)
        self.documentURL = nil
    }

    nonisolated func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        let projectData = try encoder.encode(project)
        let projectWrapper = FileWrapper(regularFileWithContents: projectData)

        var root: [String: FileWrapper] = [
            "project.json": projectWrapper
        ]

        // Audio directory - будет создан автоматически через AudioFileManager
        // Просто включаем существующую директорию если она есть
        if let existingFile = configuration.existingFile,
           let audioWrapper = existingFile.fileWrappers?["Audio"] {
            root["Audio"] = audioWrapper
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
            for mIndex in project.timelines[tIndex].markers.indices {
                let oldSeconds = project.timelines[tIndex].markers[mIndex].timeSeconds
                let frames = Int(round(oldSeconds * Double(oldFPS)))
                let newSeconds = Double(frames) / Double(newFPS)
                project.timelines[tIndex].markers[mIndex].timeSeconds = newSeconds
            }

            project.timelines[tIndex].fps = newFPS
        }

        project.fps = newFPS
    }
    
    // MARK: - Audio Operations
    
    mutating func addAudioFile(
        timelineID: UUID,
        sourceData: Data,
        originalFileName: String,
        fileExtension: String,
        duration: Double
    ) throws {
        guard let docURL = documentURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        
        guard let tIndex = project.timelines.firstIndex(where: { $0.id == timelineID }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        
        let fileName = UUID().uuidString + "." + fileExtension
        
        // Создаём Audio директорию если нужно
        let audioDir = docURL.appendingPathComponent("Audio")
        if !FileManager.default.fileExists(atPath: audioDir.path) {
            try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        }
        
        // Записываем файл
        let targetURL = audioDir.appendingPathComponent(fileName)
        try sourceData.write(to: targetURL, options: .atomic)
        
        project.timelines[tIndex].audio = TimelineAudio(
            relativePath: "Audio/\(fileName)",
            originalFileName: originalFileName,
            duration: duration
        )
    }
    
    mutating func removeAudioFile(timelineID: UUID) throws {
        guard let docURL = documentURL else { return }
        
        guard let tIndex = project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        
        if let audio = project.timelines[tIndex].audio {
            let fileName = URL(fileURLWithPath: audio.relativePath).lastPathComponent
            let fileURL = docURL.appendingPathComponent("Audio").appendingPathComponent(fileName)
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        }
        
        project.timelines[tIndex].audio = nil
    }
}
