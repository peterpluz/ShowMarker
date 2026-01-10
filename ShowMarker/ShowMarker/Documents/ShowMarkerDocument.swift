import SwiftUI
import UniformTypeIdentifiers
import Foundation

// FileDocument must remain non-actor / non-isolated.
struct ShowMarkerDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.smark] }
    static var writableContentTypes: [UTType] { [.smark] }

    var file: ProjectFile
    /// Map filename -> bytes for audio files included in the package.
    /// Stored only in memory for the duration of editing; persisted in package via fileWrapper().
    var audioFiles: [String: Data] = [:]

    // MARK: - New document

    init() {
        self.file = ProjectFile(project: Project(name: "New Project"))
        self.audioFiles = [:]
    }

    // MARK: - Open existing package

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

        // Load any files from Audio/ into audioFiles
        for (path, fw) in wrappers where path.hasPrefix("Audio/") {
            if let bytes = fw.regularFileContents {
                let fileName = URL(fileURLWithPath: path).lastPathComponent
                audioFiles[fileName] = bytes
            }
        }
    }

    // MARK: - Save as package

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // encode project.json
        let projectData = try JSONEncoder().encode(file)
        let projectWrapper = FileWrapper(regularFileWithContents: projectData)

        var wrappers: [String: FileWrapper] = [
            "project.json": projectWrapper
        ]

        for (fileName, data) in audioFiles {
            wrappers["Audio/\(fileName)"] = FileWrapper(regularFileWithContents: data)
        }

        return FileWrapper(directoryWithFileWrappers: wrappers)
    }

    // MARK: - Timeline ops (mutating)

    mutating func addTimeline(name: String) {
        file.project.timelines.append(Timeline(name: name))
    }

    mutating func renameTimeline(id: UUID, name: String) {
        guard let index = file.project.timelines.firstIndex(where: { $0.id == id }) else { return }
        file.project.timelines[index].name = name
    }

    mutating func removeTimelines(at offsets: IndexSet) {
        file.project.timelines.remove(atOffsets: offsets)
    }

    mutating func moveTimelines(from source: IndexSet, to destination: Int) {
        file.project.timelines.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Audio handling

    mutating func addAudio(to timelineID: UUID, sourceURL: URL, duration: Double) throws {
        guard let index = file.project.timelines.firstIndex(where: { $0.id == timelineID }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let ext = sourceURL.pathExtension
        let fileName = UUID().uuidString + "." + ext
        let data = try Data(contentsOf: sourceURL)

        // store bytes in memory map (will be persisted on save)
        audioFiles[fileName] = data

        file.project.timelines[index].audio = TimelineAudio(
            relativePath: "Audio/\(fileName)",
            originalFileName: sourceURL.lastPathComponent,
            duration: duration
        )
    }
}
