import SwiftUI
import UniformTypeIdentifiers
import Foundation
import Combine

/// Document implementation for the `.smark` project file.
/// Designed for Swift 6: initializer that decodes runs on the MainActor,
/// while snapshot/fileWrapper are nonisolated (required by ReferenceFileDocument).
final class ShowMarkerDocument: ReferenceFileDocument, ObservableObject {

    static var readableContentTypes: [UTType] { [.smark] }

    /// Core model. Not @Published to avoid actor-isolation issues;
    /// we manually publish changes via `objectWillChange`.
    private(set) var file: ProjectFile

    // ObservableObject publisher
    let objectWillChange = ObservableObjectPublisher()

    // MARK: - Init

    init() {
        self.file = ProjectFile(project: Project(name: "New Project"))
    }

    /// Decoding can rely on main-actor-isolated Codable conformances.
    @MainActor
    required init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            let decoded = try JSONDecoder().decode(ProjectFile.self, from: data)
            guard decoded.formatVersion == 1 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            self.file = decoded
        } else {
            self.file = ProjectFile(project: Project(name: "New Project"))
        }
    }

    // MARK: - Save

    /// Must be nonisolated so ReferenceFileDocument can call it off-main safely.
    nonisolated func snapshot(contentType: UTType) throws -> ProjectFile {
        file
    }

    nonisolated func fileWrapper(
        snapshot: ProjectFile,
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        let data = try JSONEncoder().encode(snapshot)
        return FileWrapper(regularFileWithContents: data)
    }

    // MARK: - Timelines API (mutating helpers)

    /// Each mutating helper signals `objectWillChange` so SwiftUI updates views.
    func addTimeline(name: String) {
        file.project.timelines.append(Timeline(name: name))
        objectWillChange.send()
    }

    func removeTimelines(at offsets: IndexSet) {
        file.project.timelines.remove(atOffsets: offsets)
        objectWillChange.send()
    }

    func moveTimelines(from source: IndexSet, to destination: Int) {
        file.project.timelines.move(fromOffsets: source, toOffset: destination)
        objectWillChange.send()
    }

    func renameTimeline(id: UUID, name: String) {
        guard let index = file.project.timelines.firstIndex(where: { $0.id == id }) else { return }
        file.project.timelines[index].name = name
        objectWillChange.send()
    }

    // MARK: - Audio

    func addAudio(
        to timelineID: UUID,
        sourceURL: URL,
        duration: Double
    ) throws {
        guard let index = file.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }

        let relativePath = try AudioStorage.copyToProject(from: sourceURL)

        file.project.timelines[index].audio = TimelineAudio(
            relativePath: relativePath,
            originalFileName: sourceURL.lastPathComponent,
            duration: duration
        )
        objectWillChange.send()
    }
}
