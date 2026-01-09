import Foundation
import SwiftUI
import Combine
import AVFoundation

@MainActor
final class TimelineViewModel: ObservableObject {

    @Published private(set) var audio: TimelineAudio?
    @Published private(set) var name: String = ""
    @Published var currentTime: Double = 0
    @Published var isPlaying: Bool = false

    private let document: ShowMarkerDocument
    private let timelineID: UUID
    private let player = AudioPlayerService()

    private var cancellables = Set<AnyCancellable>()

    init(
        document: ShowMarkerDocument,
        timelineID: UUID
    ) {
        self.document = document
        self.timelineID = timelineID

        bindPlayer()
        syncFromDocument()
    }

    private func bindPlayer() {
        player.$currentTime
            .assign(to: \.currentTime, on: self)
            .store(in: &cancellables)

        player.$isPlaying
            .assign(to: \.isPlaying, on: self)
            .store(in: &cancellables)
    }

    func addAudio(sourceURL: URL, duration: Double) throws {
        try document.addAudio(
            to: timelineID,
            sourceURL: sourceURL,
            duration: duration
        )

        syncFromDocument()
        player.load(url: sourceURL)
    }

    func togglePlayPause() { player.togglePlayPause() }
    func seekBackward() { player.seek(by: -5) }
    func seekForward() { player.seek(by: 5) }

    func syncFromDocument() {
        guard
            let timeline = document.file.project.timelines.first(where: { $0.id == timelineID })
        else { return }

        self.name = timeline.name
        self.audio = timeline.audio
    }

    func timecode(fps: Int = 30) -> String {
        let totalFrames = Int(currentTime * Double(fps))
        let frames = totalFrames % fps
        let totalSeconds = totalFrames / fps
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600

        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
}
