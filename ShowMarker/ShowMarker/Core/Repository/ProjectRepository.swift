import Foundation
import SwiftUI
import Combine

// ✅ ИСПРАВЛЕНО: убран @MainActor для совместимости
final class ProjectRepository: ObservableObject {

    @Published var project: Project
    var documentURL: URL?

    /// Хранилище для новых аудио файлов, которые ещё не сохранены в документ
    /// Ключ - относительный путь (Audio/filename.mp3), значение - данные файла
    var pendingAudioFiles: [String: Data] = [:]

    /// Временная директория для аудио файлов текущего документа
    /// Используется для воспроизведения аудио, так как прямой доступ к File Provider Storage запрещён
    lazy var audioTempDirectory: URL = {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShowMarker")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }()

    init(project: Project, documentURL: URL? = nil) {
        self.project = project
        self.documentURL = documentURL
    }

    /// Получить URL для воспроизведения аудио (из временной директории)
    func audioPlaybackURL(relativePath: String) -> URL {
        return audioTempDirectory.appendingPathComponent(relativePath)
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
    
    @discardableResult
    func addTimeline(name: String) -> Timeline {
        let timeline = Timeline(
            name: name,
            fps: project.fps
        )
        project.timelines.append(timeline)
        return timeline
    }

    func addTimeline(_ timeline: Timeline) {
        project.timelines.append(timeline)
    }

    func removeTimelines(at offsets: IndexSet) {
        // Удаляем аудиофайлы перед удалением таймлайнов
        let manager = AudioFileManager(tempDirectory: audioTempDirectory)

        for index in offsets {
            if let audio = project.timelines[index].audio {
                // Удаляем из временной директории
                do {
                    try manager.deleteAudioFile(relativePath: audio.relativePath)
                    print("✅ Audio file deleted from temp: \(audio.relativePath)")
                } catch {
                    print("⚠️ Failed to delete audio file: \(error.localizedDescription)")
                    // Continue with timeline deletion even if file deletion fails
                }

                // Удаляем из pending (если было добавлено, но ещё не сохранено)
                pendingAudioFiles.removeValue(forKey: audio.relativePath)
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
