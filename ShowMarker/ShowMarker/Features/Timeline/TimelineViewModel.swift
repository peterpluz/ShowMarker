import Foundation
import SwiftUI
import Combine
import AVFoundation

@MainActor
final class TimelineViewModel: ObservableObject {

    @Published private(set) var audio: TimelineAudio?
    @Published private(set) var name: String = ""

    // Player state
    @Published var currentTime: Double = 0
    @Published var isPlaying: Bool = false

    private let player = AudioPlayerService()
    private var cancellables = Set<AnyCancellable>()

    private var document: Binding<ShowMarkerDocument>
    let timelineID: UUID

    init(document: Binding<ShowMarkerDocument>, timelineID: UUID) {
        self.document = document
        self.timelineID = timelineID
        bindPlayer()
        syncFromDocument()
    }

    // MARK: - Player binding

    private func bindPlayer() {
        player.$currentTime
            .assign(to: &$currentTime)

        player.$isPlaying
            .assign(to: &$isPlaying)
    }

    // MARK: - Actions

    func addAudio(sourceURL: URL, duration: Double) throws {
        var doc = document.wrappedValue
        try doc.addAudio(
            to: timelineID,
            sourceURL: sourceURL,
            duration: duration
        )
        document.wrappedValue = doc
        syncFromDocument()

        try player.load(url: sourceURL)
    }

    func togglePlayPause() {
        player.togglePlayPause()
    }

    func seekBackward() {
        player.seek(by: -5)
    }

    func seekForward() {
        player.seek(by: 5)
    }

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
            self.name = ""
            self.audio = nil
            return
        }

        self.name = timeline.name
        self.audio = timeline.audio
    }

    // MARK: - Timecode

    func timecode(fps: Int = 30) -> String {
        let totalFrames = Int(currentTime * Double(fps))

        let frames = totalFrames % fps
        let totalSeconds = totalFrames / fps

        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60

        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60

        return String(
            format: "%02d:%02d:%02d:%02d",
            hours, minutes, seconds, frames
        )
    }
}
