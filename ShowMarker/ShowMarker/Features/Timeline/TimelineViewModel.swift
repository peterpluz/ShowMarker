import Foundation
import SwiftUI
import Combine

@MainActor
final class TimelineViewModel: ObservableObject {

    @Published private(set) var audio: TimelineAudio?
    @Published private(set) var name: String = ""
    @Published private(set) var markers: [TimelineMarker] = []
    @Published private(set) var fps: Int = 30

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

    // MARK: - Init

    init(document: Binding<ShowMarkerDocument>, timelineID: UUID) {
        self.document = document
        self.timelineID = timelineID

        bindPlayer()
        syncAll()
    }

    // MARK: - Bindings

    private func bindPlayer() {
        player.$currentTime
            .assign(to: \.currentTime, on: self)
            .store(in: &cancellables)

        player.$isPlaying
            .assign(to: \.isPlaying, on: self)
            .store(in: &cancellables)
    }

    // MARK: - Sync

    private func syncAll() {
        guard let timeline = document.wrappedValue
            .file.project.timelines
            .first(where: { $0.id == timelineID })
        else { return }

        name = timeline.name
        audio = timeline.audio
        markers = timeline.markers
        fps = timeline.fps

        syncAudioIfNeeded()
    }

    private func syncAudioIfNeeded() {
        guard let audio else { return }

        let fileName = URL(fileURLWithPath: audio.relativePath).lastPathComponent
        guard let bytes = document.wrappedValue.audioFiles[fileName] else { return }

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)

        try? bytes.write(to: tmpURL, options: .atomic)

        player.load(url: tmpURL)

        if let cached = WaveformCache.load(cacheKey: fileName) {
            cachedWaveform = cached
        } else {
            cachedWaveform = try? WaveformCache.generateAndCache(
                audioURL: tmpURL,
                cacheKey: fileName
            )
        }

        if let cachedWaveform {
            waveform = WaveformCache.bestLevel(
                from: cachedWaveform,
                targetSamples: baseSamples
            )
        }
    }

    // MARK: - Marker ops

    func addMarkerAtCurrentTime() {
        guard audio != nil else { return }

        let marker = TimelineMarker(
            timeSeconds: currentTime,
            name: "Маркер \(markers.count + 1)"
        )

        var doc = document.wrappedValue
        doc.addMarker(timelineID: timelineID, marker: marker)
        document.wrappedValue = doc

        markers.append(marker)
    }

    // MARK: - Playback

    func seek(to seconds: Double) {
        guard audio != nil else { return }
        player.seek(by: seconds - currentTime)
    }

    func togglePlayPause() {
        guard audio != nil else { return }
        player.togglePlayPause()
    }

    func seekBackward() {
        guard audio != nil else { return }
        player.seek(by: -5)
    }

    func seekForward() {
        guard audio != nil else { return }
        player.seek(by: 5)
    }

    func onDisappear() {
        player.stop()
    }

    // MARK: - Audio

    func addAudio(
        sourceData: Data,
        originalFileName: String,
        fileExtension: String,
        duration: Double
    ) throws {
        var doc = document.wrappedValue

        guard let index = doc.file.project.timelines.firstIndex(where: { $0.id == timelineID }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let fileName = UUID().uuidString + "." + fileExtension
        doc.audioFiles[fileName] = sourceData

        doc.file.project.timelines[index].audio = TimelineAudio(
            relativePath: "Audio/\(fileName)",
            originalFileName: originalFileName,
            duration: duration
        )

        document.wrappedValue = doc
        syncAll()
    }

    // MARK: - Timecode

    func timecode() -> String {
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
