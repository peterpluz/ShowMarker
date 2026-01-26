import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import Foundation

// MARK: - UTType Extension

extension UTType {
    static let smark = UTType(exportedAs: "com.peterpluz.showmarker.smark")
}

// MARK: - Document
// ✅ ИСПРАВЛЕНО: убран @MainActor для совместимости с FileDocument

struct ShowMarkerDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.smark] }
    static var writableContentTypes: [UTType] { [.smark] }

    // ✅ КРИТИЧНО: repository должен быть nonisolated
    nonisolated(unsafe) var repository: ProjectRepository

    var project: Project {
        get { repository.project }
        set { repository.project = newValue }
    }

    var documentURL: URL? {
        get { repository.documentURL }
        set { repository.documentURL = newValue }
    }

    init() {
        self.repository = ProjectRepository(
            project: Project(name: "New Project", fps: 30)
        )
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

        let decoder = JSONDecoder()
        let project = try decoder.decode(Project.self, from: data)

        self.repository = ProjectRepository(project: project, documentURL: nil)

        // Извлекаем аудио файлы из FileWrapper во временную директорию
        if let audioWrapper = wrappers["Audio"], audioWrapper.isDirectory {
            extractAudioToTemp(from: audioWrapper)
        }
    }

    /// Извлекает аудио файлы из FileWrapper во временную директорию для воспроизведения
    private func extractAudioToTemp(from audioWrapper: FileWrapper) {
        guard let audioFiles = audioWrapper.fileWrappers else { return }

        let audioTempDir = repository.audioTempDirectory.appendingPathComponent("Audio")

        // Создаём директорию Audio во временной папке
        try? FileManager.default.createDirectory(
            at: audioTempDir,
            withIntermediateDirectories: true
        )

        for (filename, fileWrapper) in audioFiles {
            guard let data = fileWrapper.regularFileContents else { continue }

            let targetURL = audioTempDir.appendingPathComponent(filename)
            do {
                try data.write(to: targetURL, options: .atomic)
                print("✅ Extracted audio to temp: \(targetURL)")
            } catch {
                print("⚠️ Failed to extract audio \(filename): \(error)")
            }
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        print("📦 [Document] fileWrapper called - autosave triggered")

        let snapshot = repository.project

        let encoder = JSONEncoder()
        let projectData = try encoder.encode(snapshot)
        let projectWrapper = FileWrapper(regularFileWithContents: projectData)

        var root: [String: FileWrapper] = [
            "project.json": projectWrapper
        ]

        // Создаём Audio FileWrapper
        var audioWrappers: [String: FileWrapper] = [:]

        // 1. Копируем существующие аудио файлы из предыдущего сохранения
        if let existingFile = configuration.existingFile,
           let existingAudio = existingFile.fileWrappers?["Audio"],
           let existingAudioFiles = existingAudio.fileWrappers {
            for (filename, wrapper) in existingAudioFiles {
                // Не копируем файлы, которые были удалены (не referenced в таймлайнах)
                let relativePath = "Audio/\(filename)"
                let isReferenced = snapshot.timelines.contains { timeline in
                    timeline.audio?.relativePath == relativePath
                }
                if isReferenced {
                    audioWrappers[filename] = wrapper
                }
            }
        }

        // 2. Добавляем новые (pending) аудио файлы
        for (relativePath, data) in repository.pendingAudioFiles {
            // relativePath = "Audio/filename.mp3"
            let filename = (relativePath as NSString).lastPathComponent
            audioWrappers[filename] = FileWrapper(regularFileWithContents: data)
            print("📦 Including pending audio in FileWrapper: \(filename)")
        }

        // Добавляем Audio директорию только если есть файлы
        if !audioWrappers.isEmpty {
            root["Audio"] = FileWrapper(directoryWithFileWrappers: audioWrappers)
        }

        // Очищаем pending после сохранения
        repository.pendingAudioFiles.removeAll()

        return FileWrapper(directoryWithFileWrappers: root)
    }
}
