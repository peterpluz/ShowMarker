import SwiftUI
import UniformTypeIdentifiers
import Foundation

@MainActor
struct ShowMarkerDocument: FileDocument {

    // MARK: - FileDocument requirements

    static var readableContentTypes: [UTType] {
        [.smark]
    }

    // MARK: - Model

    var file: ProjectFile

    // MARK: - Init (new document)

    init() {
        self.file = ProjectFile(
            project: Project(name: "New Project")
        )
    }

    // MARK: - Init (open document)

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            self.file = ProjectFile(
                project: Project(name: "New Project")
            )
            return
        }

        self.file = try JSONDecoder().decode(ProjectFile.self, from: data)
    }

    // MARK: - Save document

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(file)
        return .init(regularFileWithContents: data)
    }

    // MARK: - Timeline operations

    mutating func addTimeline(name: String) {
        file.project.timelines.append(
            Timeline(name: name)
        )
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

    // MARK: - Audio

    mutating func addAudio(
        to timelineID: UUID,
        sourceURL: URL,
        duration: Double
    ) throws {

        guard let index = file.project.timelines.firstIndex(where: { $0.id == timelineID }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let relativePath = try Self.copyAudioToDocuments(sourceURL)

        file.project.timelines[index].audio = TimelineAudio(
            relativePath: relativePath,
            originalFileName: sourceURL.lastPathComponent,
            duration: duration
        )
    }

    // MARK: - Audio storage

    private static func copyAudioToDocuments(_ sourceURL: URL) throws -> String {
        let fm = FileManager.default

        let documents = try fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let audioDir = documents.appendingPathComponent("ShowMarkerAudio", isDirectory: true)

        if !fm.fileExists(atPath: audioDir.path) {
            try fm.createDirectory(
                at: audioDir,
                withIntermediateDirectories: true
            )
        }

        let fileName = UUID().uuidString + "_" + sourceURL.lastPathComponent
        let destinationURL = audioDir.appendingPathComponent(fileName)

        try fm.copyItem(at: sourceURL, to: destinationURL)

        return "ShowMarkerAudio/\(fileName)"
    }
}
