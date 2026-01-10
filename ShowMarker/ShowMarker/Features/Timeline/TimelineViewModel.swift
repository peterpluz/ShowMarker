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

    private let player = AudioPlayerService()
    private var cancellables = Set<AnyCancellable>()

    private var document: Binding<ShowMarkerDocument>
    private let timelineID: UUID

    init(document: Binding<ShowMarkerDocument>, timelineID: UUID) {
        self.document = document
        self.timelineID = timelineID

        bindPlayer()
        syncFromDocument()
    }

    private func bindPlayer() {
        player.$currentTime
            .receive(on: DispatchQueue.main)
            .assign(to: \.currentTime, on: self)
            .store(in: &cancellables)

        player.$isPlaying
            .receive(on: DispatchQueue.main)
            .assign(to: \.isPlaying, on: self)
            .store(in: &cancellables)
    }

    // MARK: - Actions

    func addAudio(sourceURL: URL, duration: Double) throws {
        var doc = document.wrappedValue
        try doc.addAudio(to: timelineID, sourceURL: sourceURL, duration: duration)
        document.wrappedValue = doc
        syncFromDocument()

        // load directly from the source URL to player for immediate playback
        player.load(url: sourceURL)
    }

    func togglePlayPause() {
        player.togglePlayPause()
    }

    func seekBackward() { player.seek(by: -5) }
    func seekForward() { player.seek(by: 5) }

    func renameTimeline(name: String) {
        var doc = document.wrappedValue
        doc.renameTimeline(id: timelineID, name: name)
        document.wrappedValue = doc
        syncFromDocument()
    }

    // MARK: - Sync

    func syncFromDocument() {
        guard let timeline = document.wrappedValue.file.project.timelines.first(where: { $0.id == timelineID }) else {
            self.name = ""
            self.audio = nil
            return
        }

        self.name = timeline.name
        self.audio = timeline.audio

        // If we have audio and audio bytes stored in document.audioFiles, write a temp file and load it.
        if let audio = self.audio {
            let fileName = URL(fileURLWithPath: audio.relativePath).lastPathComponent

            if let bytes = document.wrappedValue.audioFiles[fileName] {
                // write to temporary file and load (safe, short-lived)
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try? bytes.write(to: tmp, options: .atomic)
                player.load(url: tmp)
            } else {
                // No bytes in memory — maybe user loaded audio but not saved; skip
            }
        }
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

        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
}
