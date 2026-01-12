import Foundation
import SwiftUI
import Combine

@MainActor
final class TimelineViewModel: ObservableObject {

    // MARK: - Published state (Model → View)

    @Published private(set) var audio: TimelineAudio?
    @Published private(set) var name: String = ""
    @Published private(set) var markers: [TimelineMarker] = []
    @Published private(set) var fps: Int = 30

    @Published var currentTime: Double = 0
    @Published var isPlaying: Bool = false

    // Waveform (VISIBLE ONLY)
    @Published private(set) var visibleWaveform: [Float] = []
    @Published private(set) var visibleMarkers: [TimelineMarker] = []

    // MARK: - Zoom (VIEW STATE ONLY)

    @Published private(set) var zoomScale: CGFloat = 1.0

    let minZoom: CGFloat = 1.0
    let maxZoom: CGFloat = 10.0

    var zoomIndicatorText: String {
        String(format: "×%.2f", zoomScale)
    }

    // Видимый диапазон времени
    private(set) var visibleTimeRange: ClosedRange<Double> = 0...0

    // MARK: - Derived

    var duration: Double {
        audio?.duration ?? 0
    }

    // MARK: - Internals

    private let player = AudioPlayerService()
    private var cancellables = Set<AnyCancellable>()

    private var document: Binding<ShowMarkerDocument>
    private let timelineID: UUID

    private let baseSamples = 150
    private var cachedWaveform: WaveformCache.CachedWaveform?
    private var loadedAudioID: UUID?
    
    private var recalcTask: Task<Void, Never>?
    private var temporaryAudioURL: URL?

    // MARK: - Init

    init(
        document: Binding<ShowMarkerDocument>,
        timelineID: UUID
    ) {
        self.document = document
        self.timelineID = timelineID

        bindPlayer()
        syncTimelineState()
        syncAudioIfNeeded()
        recalcVisibleContent()
    }
    
    deinit {
        if let tmpURL = temporaryAudioURL {
            try? FileManager.default.removeItem(at: tmpURL)
        }
    }

    // MARK: - Player binding

    private func bindPlayer() {
        player.$currentTime
            .assign(to: \.currentTime, on: self)
            .store(in: &cancellables)

        player.$isPlaying
            .assign(to: \.isPlaying, on: self)
            .store(in: &cancellables)
    }

    // MARK: - Sync (Model → VM)

    private func syncTimelineState() {
        guard let timeline = document.wrappedValue.project.timelines.first(where: { $0.id == timelineID })
        else { return }

        name = timeline.name
        audio = timeline.audio
        fps = document.wrappedValue.project.fps
        markers = timeline.markers.sorted { $0.timeSeconds < $1.timeSeconds }

        recalcVisibleContent()
    }

    private func syncAudioIfNeeded() {
        guard let audio else { return }

        if loadedAudioID == audio.id { return }

        let fileName = URL(fileURLWithPath: audio.relativePath).lastPathComponent
        guard let bytes = document.wrappedValue.audioFiles[fileName] else { return }

        let tmpURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(fileName)

        try? bytes.write(to: tmpURL, options: .atomic)
        
        temporaryAudioURL = tmpURL
        
        player.load(url: tmpURL)
        loadedAudioID = audio.id

        if let cached = WaveformCache.load(cacheKey: fileName) {
            cachedWaveform = cached
        } else {
            cachedWaveform = try? WaveformCache.generateAndCache(
                audioURL: tmpURL,
                cacheKey: fileName
            )
        }

        recalcVisibleContent()
    }

    // MARK: - Zoom API

    func applyPinchZoom(delta: CGFloat) {
        let newZoom = clampZoom(zoomScale * delta)
        guard newZoom != zoomScale else { return }

        zoomScale = newZoom
        recalcVisibleContent()
    }

    private func clampZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, minZoom), maxZoom)
    }

    // MARK: - Visible range + slicing

    private func recalcVisibleContent() {
        recalcTask?.cancel()
        recalcTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, let self else { return }
            
            self.performRecalc()
        }
    }
    
    private func performRecalc() {
        guard duration > 0 else {
            visibleWaveform = []
            visibleMarkers = []
            visibleTimeRange = 0...0
            return
        }

        let visibleDuration = duration / Double(zoomScale)

        let center = currentTime
        let start = max(0, center - visibleDuration / 2)
        let end = min(duration, start + visibleDuration)

        visibleTimeRange = start...end

        sliceWaveform()
        sliceMarkers()
    }

    private func sliceWaveform() {
        guard
            let cachedWaveform,
            duration > 0
        else {
            visibleWaveform = []
            return
        }

        let targetSamples = Int(CGFloat(baseSamples) * zoomScale)
        let level = WaveformCache.bestLevel(
            from: cachedWaveform,
            targetSamples: targetSamples
        )

        guard !level.isEmpty else {
            visibleWaveform = []
            return
        }

        let startRatio = visibleTimeRange.lowerBound / duration
        let endRatio = visibleTimeRange.upperBound / duration

        let startIndex = Int(startRatio * Double(level.count))
        let endIndex = Int(endRatio * Double(level.count))

        let safeStart = max(0, min(level.count - 1, startIndex))
        let safeEnd = max(safeStart, min(level.count, endIndex))

        visibleWaveform = Array(level[safeStart..<safeEnd])
    }

    private func sliceMarkers() {
        visibleMarkers = markers.filter {
            visibleTimeRange.contains($0.timeSeconds)
        }
    }

    // MARK: - Playback

    func seek(to seconds: Double) {
        player.seek(by: seconds - currentTime)
        recalcVisibleContent()
    }

    func togglePlayPause() {
        player.togglePlayPause()
    }

    func seekBackward() {
        player.seek(by: -5)
        recalcVisibleContent()
    }

    func seekForward() {
        player.seek(by: 5)
        recalcVisibleContent()
    }

    // MARK: - Timeline ops

    func renameTimeline(to newName: String) {
        var doc = document.wrappedValue
        guard let idx = doc.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        
        doc.project.timelines[idx].name = newName
        document.wrappedValue = doc
        
        syncTimelineState()
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
        normalizeMarkers(&doc)
        document.wrappedValue = doc

        syncTimelineState()
    }

    func renameMarker(_ marker: TimelineMarker, to newName: String) {
        var updated = marker
        updated.name = newName

        var doc = document.wrappedValue
        doc.updateMarker(timelineID: timelineID, marker: updated)
        normalizeMarkers(&doc)
        document.wrappedValue = doc

        syncTimelineState()
    }

    func moveMarker(_ marker: TimelineMarker, to newTime: Double) {
        var updated = marker
        updated.timeSeconds = min(max(newTime, 0), duration)

        var doc = document.wrappedValue
        doc.updateMarker(timelineID: timelineID, marker: updated)
        normalizeMarkers(&doc)
        document.wrappedValue = doc

        syncTimelineState()
    }

    func deleteMarker(_ marker: TimelineMarker) {
        var doc = document.wrappedValue
        doc.removeMarker(timelineID: timelineID, markerID: marker.id)
        normalizeMarkers(&doc)
        document.wrappedValue = doc

        syncTimelineState()
    }

    private func normalizeMarkers(_ doc: inout ShowMarkerDocument) {
        guard let idx = doc.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        let sorted = doc.project.timelines[idx]
            .markers
            .sorted { $0.timeSeconds < $1.timeSeconds }
        doc.project.timelines[idx].markers = sorted
        markers = sorted
    }

    // MARK: - Audio

    func addAudio(
        sourceData: Data,
        originalFileName: String,
        fileExtension: String,
        duration: Double
    ) throws {
        var doc = document.wrappedValue

        guard let idx = doc.project.timelines.firstIndex(where: { $0.id == timelineID }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let fileName = UUID().uuidString + "." + fileExtension
        doc.audioFiles[fileName] = sourceData

        doc.project.timelines[idx].audio = TimelineAudio(
            relativePath: "Audio/\(fileName)",
            originalFileName: originalFileName,
            duration: duration
        )

        document.wrappedValue = doc

        loadedAudioID = nil
        syncTimelineState()
        syncAudioIfNeeded()
    }

    func removeAudio() {
        player.stop()

        var doc = document.wrappedValue
        guard let idx = doc.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }

        if let audio {
            let fileName = URL(fileURLWithPath: audio.relativePath).lastPathComponent
            doc.audioFiles.removeValue(forKey: fileName)
        }

        doc.project.timelines[idx].audio = nil
        document.wrappedValue = doc

        loadedAudioID = nil
        audio = nil
        visibleWaveform = []
        visibleMarkers = []
        currentTime = 0
        isPlaying = false
        
        if let tmpURL = temporaryAudioURL {
            try? FileManager.default.removeItem(at: tmpURL)
            temporaryAudioURL = nil
        }
    }

    // MARK: - Timecode

    func timecode() -> String {
        let totalFrames = Int(currentTime * Double(fps))
        let frames = totalFrames % fps
        let seconds = (totalFrames / fps) % 60
        let minutes = (totalFrames / fps / 60) % 60
        let hours = totalFrames / fps / 3600

        return String(
            format: "%02d:%02d:%02d:%02d",
            hours, minutes, seconds, frames
        )
    }
}
