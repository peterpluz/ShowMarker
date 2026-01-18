import Foundation
import SwiftUI
import Combine

// ✅ ИСПРАВЛЕНО: убран @MainActor для совместимости
final class ProjectRepository: ObservableObject {
    
    @Published var project: Project
    var documentURL: URL?
    
    init(project: Project, documentURL: URL? = nil) {
        self.project = project
        self.documentURL = documentURL
    }
    
    // MARK: - Project
    
    func setProjectFPS(_ fps: Int) {
        project.fps = fps
        
        // Обновляем FPS для всех таймлайнов
        for i in project.timelines.indices {
            project.timelines[i].fps = fps
        }
    }
    
    // MARK: - Timelines
    
    func addTimeline(name: String) {
        let timeline = Timeline(
            name: name,
            fps: project.fps
        )
        project.timelines.append(timeline)
    }
    
    func removeTimelines(at offsets: IndexSet) {
        // Удаляем аудиофайлы перед удалением таймлайнов
        if let docURL = documentURL {
            let manager = AudioFileManager(documentURL: docURL)
            
            for index in offsets {
                if let audio = project.timelines[index].audio {
                    try? manager.deleteAudioFile(fileName: audio.relativePath)
                }
            }
        }
        
        project.timelines.remove(atOffsets: offsets)
    }
    
    func moveTimelines(from source: IndexSet, to destination: Int) {
        project.timelines.move(fromOffsets: source, toOffset: destination)
    }
    
    func renameTimeline(id: UUID, newName: String) {
        guard let index = project.timelines.firstIndex(where: { $0.id == id }) else {
            return
        }
        project.timelines[index].name = newName
    }
    
    // MARK: - Markers
    
    func addMarker(timelineID: UUID, marker: TimelineMarker) {
        guard let index = project.timelines.firstIndex(where: { $0.id == timelineID }) else {
            return
        }
        project.timelines[index].markers.append(marker)
    }
    
    func removeMarker(timelineID: UUID, markerID: UUID) {
        guard let timelineIndex = project.timelines.firstIndex(where: { $0.id == timelineID }) else {
            return
        }
        project.timelines[timelineIndex].markers.removeAll { $0.id == markerID }
    }
    
    func updateMarker(timelineID: UUID, marker: TimelineMarker) {
        guard
            let timelineIndex = project.timelines.firstIndex(where: { $0.id == timelineID }),
            let markerIndex = project.timelines[timelineIndex].markers.firstIndex(where: { $0.id == marker.id })
        else {
            return
        }
        project.timelines[timelineIndex].markers[markerIndex] = marker
    }
}
