import Foundation
import SwiftUI
import Combine

// ✅ ИСПРАВЛЕНО: убран @MainActor для совместимости
final class ProjectRepository: ObservableObject {

    @Published var project: Project

    var documentURL: URL? {
        didSet {
            if let url = documentURL {
                print("📁 [ProjectRepository] documentURL set: \(url.lastPathComponent)")
            } else {
                print("📁 [ProjectRepository] documentURL cleared (nil)")
            }
        }
    }

    init(project: Project, documentURL: URL? = nil) {
        self.project = project
        self.documentURL = documentURL
        print("📁 [ProjectRepository.init] documentURL: \(documentURL?.lastPathComponent ?? "nil")")
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

    func addTimeline(_ timeline: Timeline) {
        project.timelines.append(timeline)
    }

    func removeTimelines(at offsets: IndexSet) {
        // Удаляем аудиофайлы перед удалением таймлайнов
        if let docURL = documentURL {
            let manager = AudioFileManager(documentURL: docURL)

            for index in offsets {
                if let audio = project.timelines[index].audio {
                    do {
                        try manager.deleteAudioFile(fileName: audio.relativePath)
                        print("✅ Audio file deleted: \(audio.relativePath)")
                    } catch {
                        print("⚠️ Failed to delete audio file: \(error.localizedDescription)")
                        // Continue with timeline deletion even if file deletion fails
                    }
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

    // MARK: - Tags

    func addTag(_ tag: Tag) {
        project.tags.append(tag)
    }

    func updateTag(_ tag: Tag) {
        guard let index = project.tags.firstIndex(where: { $0.id == tag.id }) else {
            return
        }
        project.tags[index] = tag
    }

    func deleteTag(id: UUID) {
        // Remove tag from project
        project.tags.removeAll { $0.id == id }

        // Get default tag (first tag) to reassign markers
        guard let defaultTag = project.tags.first else { return }

        // Reassign all markers with deleted tag to default tag
        for timelineIndex in project.timelines.indices {
            for markerIndex in project.timelines[timelineIndex].markers.indices {
                if project.timelines[timelineIndex].markers[markerIndex].tagId == id {
                    project.timelines[timelineIndex].markers[markerIndex].tagId = defaultTag.id
                }
            }
        }
    }

    func getTag(id: UUID) -> Tag? {
        project.tags.first(where: { $0.id == id })
    }

    func getDefaultTag() -> Tag? {
        project.tags.first
    }
}
