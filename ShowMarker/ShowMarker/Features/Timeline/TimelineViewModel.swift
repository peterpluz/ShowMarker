import Foundation
import AVFoundation
import Combine

@MainActor
final class TimelineViewModel: ObservableObject {

    private let repository: ProjectRepository
    private let timelineID: UUID

    private let audioPlayer = AudioPlayerService()

    // MARK: - Published State (Only ViewModel-specific data)

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    @Published var zoomScale: CGFloat = 1.0

    @Published private(set) var cachedWaveform: [Float] = []
    private var waveformMipmaps: [[Float]] = []
    private var waveformCacheKey: String?

    // MARK: - Marker Crossing Detection

    // Event stream for marker flash events
    // Using PassthroughSubject ensures EVERY event is delivered to ALL subscribers
    // Unlike @Published Dictionary which can batch/coalesce rapid updates
    struct MarkerFlashEvent: Equatable {
        let markerID: UUID
        let markerName: String
        let eventID: Int
        let timestamp: Date
    }

    let markerFlashPublisher = PassthroughSubject<MarkerFlashEvent, Never>()
    private var flashCounter: Int = 0
    private var previousFrame: Int = -1
    private var triggeredMarkers: Set<UUID> = []  // Track which markers have flashed in current playback session

    // MARK: - Marker Drag State

    // Tracks which marker is being dragged and its preview time
    @Published var draggedMarkerID: UUID?
    @Published var draggedMarkerPreviewTime: Double?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties (Single Source of Truth from Repository)

    var timeline: Timeline? {
        repository.project.timelines.first(where: { $0.id == timelineID })
    }

    var name: String {
        timeline?.name ?? ""
    }

    var fps: Int {
        timeline?.fps ?? 30
    }

    var audio: TimelineAudio? {
        timeline?.audio
    }

    var markers: [TimelineMarker] {
        (timeline?.markers ?? []).sorted { $0.timeSeconds < $1.timeSeconds }
    }
    
    // MARK: - Computed
    
    var visibleMarkers: [TimelineMarker] {
        markers
    }
    
    var visibleWaveform: [Float] {
        guard !waveformMipmaps.isEmpty else { return [] }

        // Use immediate zoom scale for visual synchronization (not debounced)
        let mipmapLevel = selectMipmapLevel(for: zoomScale)

        guard mipmapLevel < waveformMipmaps.count else {
            return waveformMipmaps.first ?? []
        }

        return waveformMipmaps[mipmapLevel]
    }

    private func selectMipmapLevel(for zoom: CGFloat) -> Int {
        // Choose mipmap level based on zoom:
        // Level 0: highest detail (zoom >= 10x)
        // Level 1: high detail (zoom >= 5x)
        // Level 2: medium detail (zoom >= 2x)
        // Level 3+: low detail (zoom < 2x)

        switch zoom {
        case 10...:
            return 0  // Maximum detail
        case 5..<10:
            return min(1, waveformMipmaps.count - 1)
        case 2..<5:
            return min(2, waveformMipmaps.count - 1)
        default:
            return min(3, waveformMipmaps.count - 1)  // Lowest detail
        }
    }
    
    // MARK: - Init

    init(repository: ProjectRepository, timelineID: UUID) {
        self.repository = repository
        self.timelineID = timelineID

        setupBindings()
        setupRepositoryObserver()

        // Load initial audio and duration from timeline
        if let timelineAudio = timeline?.audio, let docURL = repository.documentURL {
            self.duration = timelineAudio.duration

            // ✅ CRITICAL FIX: Load audio into player on initialization
            let audioURL = docURL.appendingPathComponent(timelineAudio.relativePath)
            audioPlayer.load(url: audioURL)
            print("✅ Audio loaded into player on init: \(audioURL)")

            loadWaveformCache(for: timelineAudio, documentURL: docURL)
        }
    }

    private func setupRepositoryObserver() {
        // Subscribe to repository changes to trigger UI updates
        repository.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    private func setupBindings() {
        audioPlayer.$isPlaying
            .assign(to: &$isPlaying)

        // ✅ ИСПРАВЛЕНИЕ: Убран throttle для устранения "слепых зон" в детекции маркеров
        // AVPlayer уже обновляется с интервалом ~33ms, throttle только создавал пропуски
        audioPlayer.$currentTime
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentTime)

        audioPlayer.$duration
            .sink { [weak self] d in
                if d > 0 {
                    self?.duration = d
                }
            }
            .store(in: &cancellables)
        
        // Reset triggered markers when playback stops
        audioPlayer.$isPlaying
            .sink { [weak self] isPlaying in
                guard let self = self else { return }
                if !isPlaying {
                    // When playback stops, clear all triggered markers
                    // This allows markers to flash again on next playback
                    let count = self.triggeredMarkers.count
                    self.triggeredMarkers.removeAll()
                    if count > 0 {
                        print("🛑 [Detection] Playback stopped, reset \(count) triggered marker(s)")
                    }
                } else {
                    // Playback started
                    let startFrame = Int(round(self.currentTime * Double(self.fps)))
                    print("▶️ [Detection] Playback started at frame \(startFrame)")
                }
            }
            .store(in: &cancellables)

        // MARK: - Marker Crossing Detection
        // ✅ STATE FLAGS PATTERN: Industry-standard approach for marker detection
        // Each marker tracks whether it has been triggered in the current playback session
        $currentTime
            .sink { [weak self] newTime in
                guard let self = self else { return }

                let currentFrame = Int(round(newTime * Double(self.fps)))
                
                // Handle backward movement (rewind/seek) - reset triggered state for passed markers
                if currentFrame < self.previousFrame {
                    // Clear triggered flags for markers we're rewinding past
                    let rewindedMarkers = self.markers.filter { marker in
                        let markerFrame = Int(round(marker.timeSeconds * Double(self.fps)))
                        return currentFrame <= markerFrame && markerFrame <= self.previousFrame
                    }
                    for marker in rewindedMarkers {
                        self.triggeredMarkers.remove(marker.id)
                        print("🔄 [Detection] Marker '\(marker.name)' reset (rewind from frame \(self.previousFrame) to \(currentFrame))")
                    }
                    self.previousFrame = currentFrame
                    return
                }
                
                // Handle pause/stop - no movement
                guard currentFrame > self.previousFrame else {
                    self.previousFrame = currentFrame
                    return
                }

                // Find all markers crossed in this frame interval
                let crossedMarkers = self.markers.filter { marker in
                    let markerFrame = Int(round(marker.timeSeconds * Double(self.fps)))
                    
                    // Bootstrap case: first update from -1 includes frame 0
                    if self.previousFrame == -1 {
                        return markerFrame <= currentFrame
                    }
                    
                    // Normal case: strict < on left prevents duplicate detections
                    // when AVPlayer sends multiple updates at same frame (N→N)
                    return self.previousFrame < markerFrame && markerFrame <= currentFrame
                }
                
                // Trigger flash events only for markers that haven't been triggered yet
                for marker in crossedMarkers {
                    let markerFrame = Int(round(marker.timeSeconds * Double(self.fps)))
                    
                    // Skip if already triggered in this playback session
                    if self.triggeredMarkers.contains(marker.id) {
                        print("⏭️  [Detection] Marker '\(marker.name)' at frame \(markerFrame) SKIPPED (already triggered in this session)")
                        continue
                    }
                    
                    // Mark as triggered
                    self.triggeredMarkers.insert(marker.id)
                    
                    // Send flash event
                    self.flashCounter += 1
                    let event = MarkerFlashEvent(
                        markerID: marker.id,
                        markerName: marker.name,
                        eventID: self.flashCounter,
                        timestamp: Date()
                    )
                    self.markerFlashPublisher.send(event)
                    print("✨ [Detection] Marker '\(marker.name)' EVENT SENT #\(self.flashCounter) at frame \(markerFrame) (interval: \(self.previousFrame)→\(currentFrame))")
                }

                self.previousFrame = currentFrame
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Frame Quantization
    
    /// Квантует время к ближайшему кадру на таймлайне
    /// Это критично для точной детекции маркеров, так как маркеры должны быть привязаны к кадрам
    private func quantizeToFrame(_ time: Double) -> Double {
        let frameNumber = round(time * Double(fps))
        return frameNumber / Double(fps)
    }
    
    // MARK: - Waveform Cache
    
    private func loadWaveformCache(for audio: TimelineAudio, documentURL: URL) {
        let cacheKey = "\(timelineID.uuidString)_\(audio.id.uuidString)"
        self.waveformCacheKey = cacheKey

        if let cached = WaveformCache.load(cacheKey: cacheKey) {
            // Load all mipmap levels for adaptive rendering
            self.waveformMipmaps = cached.mipmaps
            self.cachedWaveform = cached.mipmaps.first ?? []
            print("✅ Waveform loaded from cache: \(cached.mipmaps.count) mipmap levels")
            for (idx, level) in cached.mipmaps.enumerated() {
                print("   Level \(idx): \(level.count) samples")
            }
            return
        }

        print("🌊 No waveform cache found, will generate...")
        Task {
            await generateWaveformCache(audio: audio, documentURL: documentURL, cacheKey: cacheKey)
        }
    }

    private func generateWaveformCache(audio: TimelineAudio, documentURL: URL, cacheKey: String) async {
        print("🌊 generateWaveformCache started")
        do {
            let audioURL = documentURL.appendingPathComponent(audio.relativePath)
            print("🌊 Audio URL: \(audioURL)")

            let cached = try await WaveformCache.generateAndCache(
                audioURL: audioURL,
                cacheKey: cacheKey
            )
            print("✅ Waveform generated: \(cached.mipmaps.count) mipmap levels")

            await MainActor.run {
                // Store all mipmap levels for adaptive rendering
                self.waveformMipmaps = cached.mipmaps
                self.cachedWaveform = cached.mipmaps.first ?? []
                print("✅ Waveform cached with \(cached.mipmaps.count) mipmap levels:")
                for (idx, level) in cached.mipmaps.enumerated() {
                    print("   Level \(idx): \(level.count) samples")
                }
            }
        } catch {
            print("⚠️ Waveform generation failed:", error)
        }
    }
    
    // MARK: - Audio
    
    func addAudio(
        sourceData: Data,
        originalFileName: String,
        fileExtension: String,
        duration audioDuration: Double
    ) throws {
        print("🎵 addAudio called: \(originalFileName), duration: \(audioDuration)s")

        guard let docURL = repository.documentURL else {
            print("❌ documentURL is nil")
            throw NSError(domain: "Timeline", code: 1)
        }

        print("✅ documentURL: \(docURL)")

        let manager = AudioFileManager(documentURL: docURL)
        let fileName = "\(UUID().uuidString).\(fileExtension)"

        print("🎵 Adding audio file: \(fileName)")
        try manager.addAudioFile(sourceData: sourceData, fileName: fileName)
        print("✅ Audio file written")

        let relativePath = "Audio/\(fileName)"
        let newAudio = TimelineAudio(
            relativePath: relativePath,
            originalFileName: originalFileName,
            duration: audioDuration
        )

        print("🎵 Updating timeline audio...")

        if let idx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }) {
            repository.project.timelines[idx].audio = newAudio
            print("✅ Timeline audio updated in repository")
        } else {
            print("❌ Timeline not found in repository")
        }

        // Update ViewModel-specific state
        self.duration = audioDuration

        print("🎵 Loading audio into player...")
        let audioURL = docURL.appendingPathComponent(newAudio.relativePath)
        audioPlayer.load(url: audioURL)
        print("✅ Audio loaded into player: \(audioURL)")

        let cacheKey = "\(timelineID.uuidString)_\(newAudio.id.uuidString)"
        self.waveformCacheKey = cacheKey

        print("🎵 Starting waveform generation...")
        Task {
            await generateWaveformCache(audio: newAudio, documentURL: docURL, cacheKey: cacheKey)
            print("✅ Waveform generation task started")
        }
    }
    
    func removeAudio() {
        guard
            let audioFile = audio,
            let docURL = repository.documentURL
        else {
            print("⚠️ Cannot remove audio: audio or documentURL is nil")
            return
        }

        let manager = AudioFileManager(documentURL: docURL)

        do {
            try manager.deleteAudioFile(fileName: audioFile.relativePath)
            print("✅ Audio file deleted: \(audioFile.relativePath)")
        } catch {
            print("⚠️ Failed to delete audio file: \(error.localizedDescription)")
            // Continue with removing audio reference even if file deletion fails
        }

        if let idx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }) {
            repository.project.timelines[idx].audio = nil
            print("✅ Audio reference removed from timeline")
        }

        // Clear ViewModel-specific state
        self.duration = 0
        self.currentTime = 0
        self.cachedWaveform = []
        self.waveformMipmaps = []
        self.waveformCacheKey = nil

        audioPlayer.stop()
        print("✅ Audio player stopped and state cleared")
    }
    
    // MARK: - Playback
    
    func togglePlayPause() {
        audioPlayer.togglePlayPause()
    }
    
    func seek(to time: Double) {
        let clamped = max(0, min(time, duration))
        audioPlayer.seek(by: clamped - currentTime)
    }
    
    func seekBackward() {
        audioPlayer.seek(by: -5)
    }
    
    func seekForward() {
        audioPlayer.seek(by: 5)
    }
    
    // MARK: - Markers
    
    func addMarkerAtCurrentTime() {
        // ✅ ИСПРАВЛЕНИЕ: Квантуем время к ближайшему кадру
        // Это гарантирует, что маркеры всегда привязаны к кадрам таймлайна
        let quantizedTime = quantizeToFrame(currentTime)
        
        let marker = TimelineMarker(
            timeSeconds: quantizedTime,
            name: "Marker \(markers.count + 1)"
        )
        repository.addMarker(timelineID: timelineID, marker: marker)
        
        print("✅ Marker added at frame-aligned time: \(String(format: "%.6f", quantizedTime))s (from \(String(format: "%.6f", currentTime))s)")
    }

    func moveMarker(_ marker: TimelineMarker, to newTime: Double) {
        // ✅ ИСПРАВЛЕНИЕ: Квантуем время при перемещении маркера
        let quantizedTime = quantizeToFrame(newTime)
        
        var updatedMarker = marker
        updatedMarker.timeSeconds = quantizedTime
        repository.updateMarker(timelineID: timelineID, marker: updatedMarker)
        
        print("✅ Marker moved to frame-aligned time: \(String(format: "%.6f", quantizedTime))s (from \(String(format: "%.6f", newTime))s)")
    }

    func renameMarker(_ marker: TimelineMarker, to newName: String) {
        var updatedMarker = marker
        updatedMarker.name = newName
        repository.updateMarker(timelineID: timelineID, marker: updatedMarker)
    }

    func deleteMarker(_ marker: TimelineMarker) {
        repository.removeMarker(timelineID: timelineID, markerID: marker.id)
    }
    
    // MARK: - Timeline

    func renameTimeline(to newName: String) {
        repository.renameTimeline(id: timelineID, newName: newName)
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
        
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
}
