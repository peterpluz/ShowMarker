import SwiftUI
import UniformTypeIdentifiers
import Foundation

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

        // Decode in nonisolated context
        let project = try Self.decodeProject(from: data)

        self.repository = ProjectRepository(project: project, documentURL: nil)
    }

    // Helper method for decoding in nonisolated context
    private static nonisolated func decodeProject(from data: Data) throws -> Project {
        let decoder = JSONDecoder()
        return try decoder.decode(Project.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let snapshot = repository.project

        // Encode in nonisolated context
        let projectData = try Self.encodeProject(snapshot)
        let projectWrapper = FileWrapper(regularFileWithContents: projectData)

        var root: [String: FileWrapper] = [
            "project.json": projectWrapper
        ]

        if let existingFile = configuration.existingFile,
           let audioWrapper = existingFile.fileWrappers?["Audio"] {
            root["Audio"] = audioWrapper
        }

        return FileWrapper(directoryWithFileWrappers: root)
    }

    // Helper method for encoding in nonisolated context
    private static nonisolated func encodeProject(_ project: Project) throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(project)
    }
}
