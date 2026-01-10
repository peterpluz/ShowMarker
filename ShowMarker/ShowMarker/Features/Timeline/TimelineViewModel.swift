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

    // MARK: - Markers & timing

    @Published private(set) var markers: [TimelineMarker] = []
    @Published private(set) var fps: Int = 30
    @Published var selectedMarkerID: UUID?

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
        syncFromDocument()
    }

    // MARK: - Player bindings

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
        markers = timeline.markers
        fps = timeline.fps
        waveform = []

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

    // MARK: - Markers

    func addMarkerAtCurrentTime() {
        let marker = TimelineMarker(
            timeSeconds: currentTime,
            name: "Маркер \(markers.count + 1)"
        )

        var doc = document.wrappedValue
        doc.addMarker(timelineID: timelineID, marker: marker)
        document.wrappedValue = doc
        syncFromDocument()
    }

    func selectMarker(_ marker: TimelineMarker) {
        selectedMarkerID = marker.id
        seek(to: marker.timeSeconds)
    }

    func updateMarker(_ marker: TimelineMarker) {
        var doc = document.wrappedValue
        doc.updateMarker(timelineID: timelineID, marker: marker)
        document.wrappedValue = doc
        syncFromDocument()
    }

    func deleteMarker(id: UUID) {
        var doc = document.wrappedValue
        doc.removeMarker(timelineID: timelineID, markerID: id)
        document.wrappedValue = doc
        syncFromDocument()
    }

    // MARK: - Playback

    func seek(to seconds: Double) {
        player.seek(by: seconds - currentTime)
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

    func onDisappear() {
        player.stop()
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
