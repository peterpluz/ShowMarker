import Foundation
import SwiftUI
import Combine

/// Единый источник правды для Project
/// Управляет всеми изменениями без копирования всего проекта
final class ProjectRepository: ObservableObject {
    
    // MARK: - Published State
    
    @Published var project: Project
    
    // URL документа для доступа к аудиофайлам
    var documentURL: URL?
    
    // MARK: - Init
    
    init(project: Project, documentURL: URL? = nil) {
        self.project = project
        self.documentURL = documentURL
    }
    
    // MARK: - Project Operations
    
    @MainActor
    func updateProjectName(_ name: String) {
        project.name = name
    }
    
    @MainActor
    func setProjectFPS(_ newFPS: Int) {
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
    
    // MARK: - Timeline Operations
    
    @MainActor
    func addTimeline(name: String) {
        let timeline = Timeline(name: name, fps: project.fps)
        project.timelines.append(timeline)
    }
    
    @MainActor
    func removeTimelines(at offsets: IndexSet) {
        project.timelines.remove(atOffsets: offsets)
    }
    
    @MainActor
    func moveTimelines(from source: IndexSet, to destination: Int) {
        project.timelines.move(fromOffsets: source, toOffset: destination)
    }
    
    @MainActor
    func renameTimeline(id: UUID, newName: String) {
        guard let index = project.timelines.firstIndex(where: { $0.id == id }) else { return }
        project.timelines[index].name = newName
    }
    
    @MainActor
    func timeline(for id: UUID) -> Timeline? {
        project.timelines.first(where: { $0.id == id })
    }
    
    // MARK: - Marker Operations
    
    @MainActor
    func addMarker(timelineID: UUID, marker: TimelineMarker) {
        guard let index = project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        project.timelines[index].markers.append(marker)
        sortMarkers(timelineID: timelineID)
    }
    
    @MainActor
    func updateMarker(timelineID: UUID, marker: TimelineMarker) {
        guard
            let tIndex = project.timelines.firstIndex(where: { $0.id == timelineID }),
            let mIndex = project.timelines[tIndex].markers.firstIndex(where: { $0.id == marker.id })
        else { return }
        
        project.timelines[tIndex].markers[mIndex] = marker
        sortMarkers(timelineID: timelineID)
    }
    
    @MainActor
    func removeMarker(timelineID: UUID, markerID: UUID) {
        guard let index = project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        project.timelines[index].markers.removeAll { $0.id == markerID }
    }
    
    @MainActor
    private func sortMarkers(timelineID: UUID) {
        guard let index = project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        project.timelines[index].markers.sort { $0.timeSeconds < $1.timeSeconds }
    }
    
    // MARK: - Audio Operations
    
    @MainActor
    func addAudioFile(
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
        
        let audioDir = docURL.appendingPathComponent("Audio")
        if !FileManager.default.fileExists(atPath: audioDir.path) {
            try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        }
        
        let targetURL = audioDir.appendingPathComponent(fileName)
        try sourceData.write(to: targetURL, options: .atomic)
        
        project.timelines[tIndex].audio = TimelineAudio(
            relativePath: "Audio/\(fileName)",
            originalFileName: originalFileName,
            duration: duration
        )
    }
    
    @MainActor
    func removeAudioFile(timelineID: UUID) throws {
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
    
    // MARK: - Serialization
    
    func snapshot() -> Project {
        project
    }
    
    @MainActor
    func load(project: Project, documentURL: URL?) {
        self.project = project
        self.documentURL = documentURL
    }
}
