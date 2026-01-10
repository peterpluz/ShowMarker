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

    var duration: Double {
        audio?.duration ?? 0
    }

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
            .assign(to: \.currentTime, on: self)
            .store(in: &cancellables)

        player.$isPlaying
            .assign(to: \.isPlaying, on: self)
            .store(in: &cancellables)
    }

    // MARK: - Timeline control

    func seek(to seconds: Double) {
        let delta = seconds - currentTime
        player.seek(by: delta)
    }

    func togglePlayPause() {
        player.togglePlayPause()
    }

    func seekBackward() { player.seek(by: -5) }
    func seekForward() { player.seek(by: 5) }

    // MARK: - Audio

    func addAudio(sourceURL: URL, duration: Double) throws {
        var doc = document.wrappedValue
        try doc.addAudio(to: timelineID, sourceURL: sourceURL, duration: duration)
        document.wrappedValue = doc
        syncFromDocument()

        player.load(url: sourceURL)
    }

    // MARK: - Sync

    func syncFromDocument() {
        guard let timeline = document.wrappedValue.file.project.timelines.first(where: { $0.id == timelineID }) else {
            name = ""
            audio = nil
            return
        }

        name = timeline.name
        audio = timeline.audio

        if let audio {
            let fileName = URL(fileURLWithPath: audio.relativePath).lastPathComponent
            if let bytes = document.wrappedValue.audioFiles[fileName] {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try? bytes.write(to: tmp, options: .atomic)
                player.load(url: tmp)
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
