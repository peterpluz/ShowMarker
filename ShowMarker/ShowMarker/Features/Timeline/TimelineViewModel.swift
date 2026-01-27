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

    // MARK: - Auto-scroll state

    @Published var isAutoScrollEnabled: Bool = true  // Enabled by default

    /// ID of the next marker after current playhead position
    /// Used for auto-scrolling the marker list
    @Published private(set) var nextMarkerID: UUID?

    // MARK: - Marker creation settings

    @Published var shouldPauseOnMarkerCreation: Bool = false
    @Published var shouldShowMarkerPopup: Bool = true  // Toggle for marker creation popup

    // MARK: - Undo/Redo System

    @Published private(set) var undoManager: MarkerUndoManager

    // MARK: - Tag filtering

    @Published var selectedTagIds: Set<UUID> = []

    // MARK: - Marker Crossing Detection

    // Event stream for marker flash events
    // Using PassthroughSubject ensures EVERY event is delivered to ALL subscribers
    struct MarkerFlashEvent: Equatable {
        let markerID: UUID
        let markerName: String
        let eventID: Int
        let timestamp: Date
    }

    let markerFlashPublisher = PassthroughSubject<MarkerFlashEvent, Never>()
    private var flashCounter: Int = 0
    private var previousFrame: Int = -1
    
    // ✅ NEW: Track already-flashed markers during current playback session
    private var flashedMarkers: Set<UUID> = []

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

    var tags: [Tag] {
        repository.project.tags
    }

    var defaultTag: Tag? {
        repository.getDefaultTag()
    }

    var projectFPS: Int {
        repository.project.fps
    }

    // MARK: - Computed

    var visibleMarkers: [TimelineMarker] {
        // If no tags selected or all tags selected, show all markers
        if selectedTagIds.isEmpty || selectedTagIds.count == tags.count {
            return markers
        }

        // Filter markers by selected tags
        return markers.filter { marker in
            selectedTagIds.contains(marker.tagId)
        }
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
        self.undoManager = MarkerUndoManager(repository: repository, timelineID: timelineID)

        // Initialize selectedTagIds with all tags (show all by default)
        self.selectedTagIds = Set(repository.project.tags.map(\.id))

        setupBindings()
        setupRepositoryObserver()

        // Load initial audio and duration from timeline
        // Используем временную директорию для воспроизведения (аудио извлекается туда при открытии документа)
        if let timelineAudio = timeline?.audio {
            self.duration = timelineAudio.duration

            // ✅ CRITICAL FIX: Load audio into player on initialization
            let audioURL = repository.audioPlaybackURL(relativePath: timelineAudio.relativePath)
            audioPlayer.load(url: audioURL)
            print("✅ Audio loaded into player on init: \(audioURL)")

            loadWaveformCache(for: timelineAudio, documentURL: repository.audioTempDirectory)
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

        // ✅ Direct assignment without throttle - AVPlayer already updates at ~33ms intervals
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
        
        // ✅ Reset frame tracking when playback state changes
        audioPlayer.$isPlaying
            .sink { [weak self] isPlaying in
                guard let self = self else { return }
                if isPlaying {
                    // Playback started - reset frame tracking and flashed markers
                    let startFrame = Int(round(self.currentTime * Double(self.fps)))
                    self.previousFrame = startFrame
                    self.flashedMarkers.removeAll()
                    print("▶️ [Detection] Playback started at frame \(startFrame), reset flashed markers")
                } else {
                    // Playback stopped - reset to initial state
                    self.previousFrame = -1
                    print("🛑 [Detection] Playback stopped, frame tracking reset")
                }
            }
            .store(in: &cancellables)

        // MARK: - Marker Crossing Detection
        // ✅ SIMPLIFIED: Only detect during active playback
        $currentTime
            .sink { [weak self] newTime in
                guard let self = self else { return }
                
                // ✅ Update next marker for auto-scroll (always, regardless of playback state)
                self.updateNextMarker(for: newTime)
                
                // ✅ CRITICAL: Only detect markers during active playback
                guard self.isPlaying else {
                    return
                }

                let currentFrame = Int(round(newTime * Double(self.fps)))
                
                // ✅ FIX: Handle backward movement (rewind during playback)
                if currentFrame < self.previousFrame {
                    // User rewound during playback - clear flashed markers that are now ahead
                    let rewindedMarkers = self.markers.filter { marker in
                        let markerFrame = Int(round(marker.timeSeconds * Double(self.fps)))
                        return markerFrame > currentFrame
                    }
                    for marker in rewindedMarkers {
                        self.flashedMarkers.remove(marker.id)
                    }
                    self.previousFrame = currentFrame
                    print("⏪ [Detection] Rewound to frame \(currentFrame), cleared \(rewindedMarkers.count) flashed markers")
                    return
                }
                
                // Skip if no movement (can happen with multiple rapid updates)
                guard currentFrame > self.previousFrame else {
                    return
                }

                // Find all markers crossed in this frame interval
                let crossedMarkers = self.markers.filter { marker in
                    let markerFrame = Int(round(marker.timeSeconds * Double(self.fps)))
                    
                    // ✅ FIX: Include frame 0 in bootstrap case
                    if self.previousFrame == -1 {
                        return markerFrame >= 0 && markerFrame <= currentFrame
                    }
                    
                    // Normal case: check if marker is in the interval (previous, current]
                    // Using strict < on left boundary prevents duplicate detections
                    return self.previousFrame < markerFrame && markerFrame <= currentFrame
                }
                
                // Send flash events only for markers that haven't flashed yet
                for marker in crossedMarkers {
                    // ✅ Skip if already flashed in this session
                    guard !self.flashedMarkers.contains(marker.id) else {
                        print("⏭️  [Detection] Marker '\(marker.name)' already flashed, skipping")
                        continue
                    }
                    
                    let markerFrame = Int(round(marker.timeSeconds * Double(self.fps)))
                    
                    // Mark as flashed
                    self.flashedMarkers.insert(marker.id)
                    
                    self.flashCounter += 1
                    let event = MarkerFlashEvent(
                        markerID: marker.id,
                        markerName: marker.name,
                        eventID: self.flashCounter,
                        timestamp: Date()
                    )
                    self.markerFlashPublisher.send(event)
                    print("✨ [Detection] Marker '\(marker.name)' FLASH #\(self.flashCounter) at frame \(markerFrame) (interval: \(self.previousFrame)→\(currentFrame))")
                }

                self.previousFrame = currentFrame
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Auto-scroll
    
    /// Updates the next marker ID based on current playhead position
    /// This is used for auto-scrolling the marker list
    private func updateNextMarker(for time: Double) {
        // Find the first marker that comes after the current time
        let next = markers.first { marker in
            marker.timeSeconds > time
        }
        
        // Only update if changed to avoid unnecessary UI updates
        if nextMarkerID != next?.id {
            nextMarkerID = next?.id
        }
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

        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let relativePath = "Audio/\(fileName)"

        // 1. Сохраняем во временную директорию для воспроизведения
        let manager = AudioFileManager(tempDirectory: repository.audioTempDirectory)
        print("🎵 Saving audio to temp directory: \(repository.audioTempDirectory)")
        try manager.saveAudioToTemp(sourceData: sourceData, relativePath: relativePath)

        // 2. Сохраняем данные в pending для включения в FileWrapper при сохранении документа
        repository.pendingAudioFiles[relativePath] = sourceData
        print("✅ Audio added to pending files for document save")

        // 3. Создаём модель аудио
        let newAudio = TimelineAudio(
            relativePath: relativePath,
            originalFileName: originalFileName,
            duration: audioDuration
        )

        // 4. Обновляем таймлайн
        print("🎵 Updating timeline audio...")
        if let idx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }) {
            repository.project.timelines[idx].audio = newAudio
            print("✅ Timeline audio updated in repository")
        } else {
            print("❌ Timeline not found in repository")
        }

        // 5. Обновляем состояние ViewModel
        self.duration = audioDuration

        // 6. Загружаем аудио в плеер из временной директории
        print("🎵 Loading audio into player...")
        let audioURL = repository.audioPlaybackURL(relativePath: relativePath)
        audioPlayer.load(url: audioURL)
        print("✅ Audio loaded into player: \(audioURL)")

        // 7. Генерируем waveform
        let cacheKey = "\(timelineID.uuidString)_\(newAudio.id.uuidString)"
        self.waveformCacheKey = cacheKey

        print("🎵 Starting waveform generation...")
        let tempDir = repository.audioTempDirectory
        Task {
            await generateWaveformCache(audio: newAudio, documentURL: tempDir, cacheKey: cacheKey)
            print("✅ Waveform generation task started")
        }
    }
    
    func removeAudio() {
        guard let audioFile = audio else {
            print("⚠️ Cannot remove audio: audio is nil")
            return
        }

        // Удаляем из временной директории
        let manager = AudioFileManager(tempDirectory: repository.audioTempDirectory)
        do {
            try manager.deleteAudioFile(relativePath: audioFile.relativePath)
            print("✅ Audio file deleted from temp: \(audioFile.relativePath)")
        } catch {
            print("⚠️ Failed to delete audio file: \(error.localizedDescription)")
            // Continue with removing audio reference even if file deletion fails
        }

        // Удаляем из pending (если было добавлено, но ещё не сохранено)
        repository.pendingAudioFiles.removeValue(forKey: audioFile.relativePath)

        // Удаляем ссылку из таймлайна
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

    func addMarker(name: String, tagId: UUID, at time: Double) {
        // ✅ Квантуем время к ближайшему кадру
        let quantizedTime = quantizeToFrame(time)

        let marker = TimelineMarker(
            timeSeconds: quantizedTime,
            name: name,
            tagId: tagId
        )

        // Use undo manager for this action
        let action = AddMarkerAction(marker: marker)
        undoManager.performAction(action)

        print("✅ Marker '\(name)' added at frame-aligned time: \(String(format: "%.6f", quantizedTime))s with tagId: \(tagId)")
    }

    func pausePlayback() {
        audioPlayer.pause()
    }

    func resumePlayback() {
        audioPlayer.play()
    }

    func moveMarker(_ marker: TimelineMarker, to newTime: Double) {
        // ✅ Квантуем время при перемещении маркера
        let quantizedTime = quantizeToFrame(newTime)

        // Use undo manager for this action
        let action = ChangeMarkerTimeAction(
            markerID: marker.id,
            oldTime: marker.timeSeconds,
            newTime: quantizedTime
        )
        undoManager.performAction(action)

        print("✅ Marker moved to frame-aligned time: \(String(format: "%.6f", quantizedTime))s (from \(String(format: "%.6f", newTime))s)")
    }

    func renameMarker(_ marker: TimelineMarker, to newName: String, oldName: String? = nil) {
        // Use undo manager for this action
        let action = RenameMarkerAction(
            markerID: marker.id,
            oldName: oldName ?? marker.name,
            newName: newName
        )
        undoManager.performAction(action)
    }

    func updateMarker(_ marker: TimelineMarker) {
        repository.updateMarker(timelineID: timelineID, marker: marker)
    }

    func changeMarkerTag(_ marker: TimelineMarker, to newTagId: UUID) {
        // Use undo manager for this action
        let action = ChangeMarkerTagAction(
            markerID: marker.id,
            oldTagId: marker.tagId,
            newTagId: newTagId
        )
        undoManager.performAction(action)
    }

    func deleteMarker(_ marker: TimelineMarker) {
        // Use undo manager for this action
        let action = DeleteMarkerAction(marker: marker)
        undoManager.performAction(action)
    }

    func deleteAllMarkers() {
        // Use undo manager for this action
        let action = DeleteAllMarkersAction(markers: markers)
        undoManager.performAction(action)
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
