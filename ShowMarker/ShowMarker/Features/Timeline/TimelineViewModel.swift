import Foundation
import SwiftUI
import Combine

/// ViewModel for a single timeline.
/// Holds a Binding to the FileDocument so that mutations persist correctly.
/// Uses manual objectWillChange publishing to notify views after changes.
final class TimelineViewModel: ObservableObject {

    // We store the Binding explicitly (not @Binding property wrapper).
    private var document: Binding<ShowMarkerDocument>
    let timelineID: UUID

    // Manual publisher for ObservableObject
    let objectWillChange = ObservableObjectPublisher()

    init(document: Binding<ShowMarkerDocument>, timelineID: UUID) {
        self.document = document
        self.timelineID = timelineID
    }

    // MARK: - Accessors

    var timeline: Timeline? {
        guard let index = timelineIndex else { return nil }
        return document.wrappedValue.file.project.timelines[index]
    }

    var name: String {
        timeline?.name ?? ""
    }

    var audio: TimelineAudio? {
        timeline?.audio
    }

    // MARK: - Actions

    /// Adds audio to the timeline and writes change back to the binding.
    func addAudio(sourceURL: URL, duration: Double) throws {
        // Work on a local copy (struct), mutate it, then write back.
        var doc = document.wrappedValue
        try doc.addAudio(to: timelineID, sourceURL: sourceURL, duration: duration)
        document.wrappedValue = doc

        // notify SwiftUI observers
        objectWillChange.send()
    }

    // Add other mutating helpers the same way, for example:
    func renameTimeline(name: String) {
        var doc = document.wrappedValue
        doc.renameTimeline(id: timelineID, name: name)
        document.wrappedValue = doc
        objectWillChange.send()
    }

    // MARK: - Private

    private var timelineIndex: Int? {
        document.wrappedValue.file.project.timelines.firstIndex { $0.id == timelineID }
    }
}
