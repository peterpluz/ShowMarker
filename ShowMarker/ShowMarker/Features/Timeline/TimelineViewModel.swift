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
    @Published var waveform: [Float] = []

    var duration: Double {
        audio?.duration ?? 0
    }

    private let player = AudioPlayerService()
    private var cancellables = Set<AnyCancellable>()

    private var document: Binding<ShowMarkerDocument>
    private let timelineID: UUID

    private let baseSamples = 150
    private var cachedWaveform: WaveformCache.CachedWaveform?

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

    // MARK: - Audio

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

    // MARK: - Sync

    func syncFromDocument() {
        guard let timeline = document.wrappedValue
            .file.project.timelines
            .first(where: { $0.id == timelineID })
        else { return }

        name = timeline.name
        audio = timeline.audio
        waveform = []

        guard let audio else { return }

        let fileName = URL(fileURLWithPath: audio.relativePath).lastPathComponent
        guard let bytes = document.wrappedValue.audioFiles[fileName] else { return }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)

        try? bytes.write(to: tmp, options: .atomic)
        player.load(url: tmp)

        if let cached = WaveformCache.load(cacheKey: fileName) {
            cachedWaveform = cached
        } else {
            cachedWaveform = try? WaveformCache.generateAndCache(
                audioURL: tmp,
                cacheKey: fileName
            )
        }

        waveform = WaveformCache.bestLevel(
            from: cachedWaveform!,
            targetSamples: baseSamples
        )
    }

    // MARK: - Playback

    func seek(to seconds: Double) {
        player.seek(by: seconds - currentTime)
    }

    func togglePlayPause() {
        player.togglePlayPause()
    }

    func seekBackward() { player.seek(by: -5) }
    func seekForward() { player.seek(by: 5) }

    func onDisappear() {
        player.stop()
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

        return String(format: "%02d:%02d:%02d:%02d",
                      hours, minutes, seconds, frames)
    }
}
