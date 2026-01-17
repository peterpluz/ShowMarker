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
    
    // Zoom state
    @Published var zoomScale: CGFloat = 1.0

    // MARK: - Derived

    var duration: Double {
        audio?.duration ?? 0
    }

    // MARK: - Internals

    private let player = AudioPlayerService()
    private var cancellables = Set<AnyCancellable>()

    private let repository: ProjectRepository
    private let timelineID: UUID

    private let baseSamples = 800  // УВЕЛИЧЕНО: больше баров = выше детализация!
    private var cachedWaveform: WaveformCache.CachedWaveform?
    private var loadedAudioID: UUID?

    // MARK: - Init

    init(
        repository: ProjectRepository,
        timelineID: UUID
    ) {
        self.repository = repository
        self.timelineID = timelineID

        bindPlayer()
        bindRepository()
        bindZoom()
        syncTimelineState()
        syncAudioIfNeeded()
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
    
    // MARK: - Repository binding
    
    private func bindRepository() {
        repository.$project
            .sink { [weak self] _ in
                self?.syncTimelineState()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Zoom binding
    
    private func bindZoom() {
        $zoomScale
            .removeDuplicates()
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateVisibleContent()
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

        updateVisibleContent()
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

        // Загружаем или генерируем детализированную waveform
        if let cached = WaveformCache.load(cacheKey: fileName) {
            cachedWaveform = cached
        } else {
            Task {
                cachedWaveform = try? WaveformCache.generateAndCache(
                    audioURL: audioURL,
                    cacheKey: fileName
                )
                updateVisibleContent()
            }
        }

        updateVisibleContent()
    }

    // MARK: - Visible content

    private func updateVisibleContent() {
        guard duration > 0 else {
            visibleWaveform = []
            visibleMarkers = []
            return
        }

        updateWaveform()
        updateMarkers()
    }

    private func updateWaveform() {
        guard
            let cachedWaveform,
            duration > 0
        else {
            visibleWaveform = []
            return
        }

        // Выбираем уровень детализации на основе зума
        let level = WaveformCache.bestLevel(
            from: cachedWaveform,
            targetSamples: baseSamples,
            zoomScale: zoomScale
        )

        visibleWaveform = level
    }

    private func updateMarkers() {
        visibleMarkers = markers
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

    // MARK: - Timeline ops

    func renameTimeline(to newName: String) {
        repository.renameTimeline(id: timelineID, newName: newName)
    }

    // MARK: - Marker ops

    func addMarkerAtCurrentTime() {
        guard audio != nil else { return }

        let marker = TimelineMarker(
            timeSeconds: currentTime,
            name: "Маркер \(markers.count + 1)"
        )

        repository.addMarker(timelineID: timelineID, marker: marker)
    }

    func renameMarker(_ marker: TimelineMarker, to newName: String) {
        var updated = marker
        updated.name = newName

        repository.updateMarker(timelineID: timelineID, marker: updated)
    }

    func moveMarker(_ marker: TimelineMarker, to newTime: Double) {
        var updated = marker
        updated.timeSeconds = min(max(newTime, 0), duration)

        repository.updateMarker(timelineID: timelineID, marker: updated)
    }

    func deleteMarker(_ marker: TimelineMarker) {
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
        cachedWaveform = nil
        syncTimelineState()
        syncAudioIfNeeded()
    }

    func removeAudio() {
        player.stop()

        try? repository.removeAudioFile(timelineID: timelineID)

        loadedAudioID = nil
        cachedWaveform = nil
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
