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

    private(set) var visibleTimeRange: ClosedRange<Double> = 0...0

    // MARK: - Derived

    var duration: Double {
        audio?.duration ?? 0
    }

    // MARK: - Internals

    private let player = AudioPlayerService()
    private var cancellables = Set<AnyCancellable>()

    // НОВОЕ: Repository вместо Binding<Document>
    private let repository: ProjectRepository
    private let timelineID: UUID

    private let baseSamples = 150
    private var cachedWaveform: WaveformCache.CachedWaveform?
    private var loadedAudioID: UUID?
    
    private var recalcTask: Task<Void, Never>?

    // MARK: - Init

    init(
        repository: ProjectRepository,
        timelineID: UUID
    ) {
        self.repository = repository
        self.timelineID = timelineID

        bindPlayer()
        bindRepository()
        syncTimelineState()
        syncAudioIfNeeded()
        recalcVisibleContent()
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
    
    // MARK: - Repository binding (НОВОЕ)
    
    private func bindRepository() {
        // Подписываемся на изменения проекта
        repository.$project
            .sink { [weak self] _ in
                self?.syncTimelineState()
            }
            .store(in: &cancellables)
    }

    // MARK: - Sync (Model → VM)

    private func syncTimelineState() {
        guard let timeline = repository.timeline(for: timelineID) else { return }

        name = timeline.name
        audio = timeline.audio
        fps = repository.project.fps
        markers = timeline.markers.sorted { $0.timeSeconds < $1.timeSeconds }

        recalcVisibleContent()
    }

    private func syncAudioIfNeeded() {
        guard let audio else { return }

        if loadedAudioID == audio.id { return }

        guard let docURL = repository.documentURL else { return }
        
        let fileName = URL(fileURLWithPath: audio.relativePath).lastPathComponent
        let manager = AudioFileManager(documentURL: docURL)
        
        let audioURL = manager.audioFileURL(fileName: fileName)
        
        guard manager.audioFileExists(fileName: fileName) else { return }
        
        player.load(url: audioURL)
        loadedAudioID = audio.id

        if let cached = WaveformCache.load(cacheKey: fileName) {
            cachedWaveform = cached
        } else {
            cachedWaveform = try? WaveformCache.generateAndCache(
                audioURL: audioURL,
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

    // MARK: - Timeline ops (НОВОЕ: прямые вызовы repository)

    func renameTimeline(to newName: String) {
        repository.renameTimeline(id: timelineID, newName: newName)
    }

    // MARK: - Marker ops (НОВОЕ: без копирования документа)

    func addMarkerAtCurrentTime() {
        guard audio != nil else { return }

        let marker = TimelineMarker(
            timeSeconds: currentTime,
            name: "Маркер \(markers.count + 1)"
        )

        // ⚡ КЛЮЧЕВОЕ ИЗМЕНЕНИЕ: прямая мутация без копирования
        repository.addMarker(timelineID: timelineID, marker: marker)
    }

    func renameMarker(_ marker: TimelineMarker, to newName: String) {
        var updated = marker
        updated.name = newName

        // ⚡ Прямая мутация
        repository.updateMarker(timelineID: timelineID, marker: updated)
    }

    func moveMarker(_ marker: TimelineMarker, to newTime: Double) {
        var updated = marker
        updated.timeSeconds = min(max(newTime, 0), duration)

        // ⚡ Прямая мутация
        repository.updateMarker(timelineID: timelineID, marker: updated)
    }

    func deleteMarker(_ marker: TimelineMarker) {
        // ⚡ Прямая мутация
        repository.removeMarker(timelineID: timelineID, markerID: marker.id)
    }

    // MARK: - Audio

    func addAudio(
        sourceData: Data,
        originalFileName: String,
        fileExtension: String,
        duration: Double
    ) throws {
        try repository.addAudioFile(
            timelineID: timelineID,
            sourceData: sourceData,
            originalFileName: originalFileName,
            fileExtension: fileExtension,
            duration: duration
        )

        loadedAudioID = nil
        syncTimelineState()
        syncAudioIfNeeded()
    }

    func removeAudio() {
        player.stop()

        try? repository.removeAudioFile(timelineID: timelineID)

        loadedAudioID = nil
        audio = nil
        visibleWaveform = []
        visibleMarkers = []
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

        return String(
            format: "%02d:%02d:%02d:%02d",
            hours, minutes, seconds, frames
        )
    }
}
