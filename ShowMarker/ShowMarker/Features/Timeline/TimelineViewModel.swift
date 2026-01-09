import Foundation
import SwiftUI
import Combine

/// ViewModel for a single timeline.
/// Keeps local @Published state to guarantee immediate UI updates.
@MainActor
final class TimelineViewModel: ObservableObject {

    // MARK: - Published state (IMPORTANT)

    @Published private(set) var audio: TimelineAudio?
    @Published private(set) var name: String = ""

    // MARK: - Dependencies

    private var document: Binding<ShowMarkerDocument>
    let timelineID: UUID

    // MARK: - Init

    init(document: Binding<ShowMarkerDocument>, timelineID: UUID) {
        self.document = document
        self.timelineID = timelineID
        syncFromDocument()
    }

    // MARK: - Actions

    /// This method mutates the document; it is main-actor isolated.
    func addAudio(sourceURL: URL, duration: Double) throws {
        var doc = document.wrappedValue
        try doc.addAudio(
            to: timelineID,
            sourceURL: sourceURL,
            duration: duration
        )
        document.wrappedValue = doc
        syncFromDocument()
    }

    /// Rename helper — main-actor isolated
    func renameTimeline(name: String) {
        var doc = document.wrappedValue
        doc.renameTimeline(id: timelineID, name: name)
        document.wrappedValue = doc
        syncFromDocument()
    }

    // MARK: - Sync

    private func syncFromDocument() {
        guard let timeline = document.wrappedValue
            .file.project.timelines
            .first(where: { $0.id == timelineID })
        else {
            // If timeline was removed, clear local state
            self.name = ""
            self.audio = nil
            return
        }

        self.name = timeline.name
        self.audio = timeline.audio
    }
}
