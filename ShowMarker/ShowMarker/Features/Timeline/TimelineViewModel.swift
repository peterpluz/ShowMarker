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

    init(document: Binding<ShowMarkerDocument>, timelineID: UUID) {
        self.document = document
        self.timelineID = timelineID
        bindPlayer()
        syncAll()
    }

    private func bindPlayer() {
        player.$currentTime
            .assign(to: \.currentTime, on: self)
            .store(in: &cancellables)

        player.$isPlaying
            .assign(to: \.isPlaying, on: self)
            .store(in: &cancellables)
    }

    private func syncAll() {
        guard let timeline = document.wrappedValue
            .file.project.timelines.first(where: { $0.id == timelineID })
        else { return }

        name = timeline.name
        audio = timeline.audio

        // fps берем из глобального проекта (при этом timeline.fps обновляется при смене проекта)
        fps = document.wrappedValue.file.project.fps

        // сортируем по timeSeconds (в секундах), как раньше
        markers = timeline.markers.sorted { $0.timeSeconds < $1.timeSeconds }

        syncAudioIfNeeded()
    }

    private func syncAudioIfNeeded() {
        guard let audio else { return }

        let fileName = URL(fileURLWithPath: audio.relativePath).lastPathComponent
        guard let bytes = document.wrappedValue.audioFiles[fileName] else { return }

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
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

    // MARK: - FPS

    func setFPS(_ newFPS: Int) {
        guard [25, 30, 50, 60, 100].contains(newFPS) else { return }

        // Выполняем проектную смену FPS через документ (миграция маркеров)
        var doc = document.wrappedValue
        doc.setProjectFPS(newFPS)
        document.wrappedValue = doc

        // Обновляем локальный fps и синхронизируем список маркеров/имён
        fps = newFPS
        syncAll()
    }

    // MARK: - Timeline

    func renameTimeline(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        var doc = document.wrappedValue
        guard let idx = doc.file.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }

        doc.file.project.timelines[idx].name = trimmed
        document.wrappedValue = doc
        name = trimmed
    }

    // MARK: - Markers

    func addMarkerAtCurrentTime() {
        guard audio != nil else { return }

        let marker = TimelineMarker(
            timeSeconds: currentTime,
            name: "Маркер \(markers.count + 1)"
        )

        var doc = document.wrappedValue
        doc.addMarker(timelineID: timelineID, marker: marker)
        normalizeMarkers(&doc)
        document.wrappedValue = doc
        syncAll()
    }

    func renameMarker(_ marker: TimelineMarker, to newName: String) {
        var updated = marker
        updated.name = newName

        var doc = document.wrappedValue
        doc.updateMarker(timelineID: timelineID, marker: updated)
        normalizeMarkers(&doc)
        document.wrappedValue = doc
        syncAll()
    }

    func moveMarker(_ marker: TimelineMarker, to newTime: Double) {
        var updated = marker
        updated.timeSeconds = min(max(newTime, 0), duration)

        var doc = document.wrappedValue
        doc.updateMarker(timelineID: timelineID, marker: updated)
        normalizeMarkers(&doc)
        document.wrappedValue = doc
        syncAll()
    }

    func deleteMarker(_ marker: TimelineMarker) {
        var doc = document.wrappedValue
        doc.removeMarker(timelineID: timelineID, markerID: marker.id)
        normalizeMarkers(&doc)
        document.wrappedValue = doc
        syncAll()
    }

    private func normalizeMarkers(_ doc: inout ShowMarkerDocument) {
        guard let idx = doc.file.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        let sorted = doc.file.project.timelines[idx].markers.sorted { $0.timeSeconds < $1.timeSeconds }
        doc.file.project.timelines[idx].markers = sorted
        markers = sorted
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

    // MARK: - Audio

    func addAudio(
        sourceData: Data,
        originalFileName: String,
        fileExtension: String,
        duration: Double
    ) throws {
        var doc = document.wrappedValue

        guard let idx = doc.file.project.timelines.firstIndex(where: { $0.id == timelineID }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let fileName = UUID().uuidString + "." + fileExtension
        doc.audioFiles[fileName] = sourceData

        doc.file.project.timelines[idx].audio = TimelineAudio(
            relativePath: "Audio/\(fileName)",
            originalFileName: originalFileName,
            duration: duration
        )

        document.wrappedValue = doc
        syncAll()
    }

    func removeAudio() {
        player.stop()

        var doc = document.wrappedValue
        guard let idx = doc.file.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }

        if let audio {
            let fileName = URL(fileURLWithPath: audio.relativePath).lastPathComponent
            doc.audioFiles.removeValue(forKey: fileName)
        }

        doc.file.project.timelines[idx].audio = nil
        document.wrappedValue = doc

        audio = nil
        waveform = []
        currentTime = 0
        isPlaying = false
    }

    // MARK: - Timecode

    func timecode() -> String {
        let totalFrames = Int(currentTime * Double(fps))
        let frames = totalFrames % fps
        let seconds = (totalFrames / fps) % 60
        let minutes = (totalFrames / fps / 60) % 60
        let hours = totalFrames / fps / 3600

        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
}
