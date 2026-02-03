import Foundation
import AVFoundation
import Combine

@MainActor
final class TimelineViewModel: ObservableObject {

    private let repository: ProjectRepository
    private let timelineID: UUID

    private let audioPlayer = AudioPlayerService()
    private let metronome = MetronomeService()

    // MARK: - Published State (Only ViewModel-specific data)

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    @Published var zoomScale: CGFloat = 1.0

    @Published private(set) var cachedWaveform: [Float] = []
    private var waveformMipmaps: [[Float]] = []
    private var waveformCacheKey: String?

    /// Indicates whether the timeline is still loading (waveform, audio, etc.)
    @Published private(set) var isLoading: Bool = true

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

    // MARK: - Beat Scheduling (Metronome)

    /// Current beat number in bar (0-based), computed from playhead position
    @Published private(set) var currentBeat: Int = 0

    /// The absolute beat number that is next scheduled to play
    /// Int.min means nothing is scheduled
    private var nextScheduledBeat: Int = Int.min

    /// Tracks the last beat we actually played (for visual updates on reactive path)
    private var lastPlayedBeat: Int = Int.min

    /// Generation counter to invalidate stale asyncAfter callbacks after seek/reset
    private var beatScheduleGeneration: Int = 0

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

    var isMarkerHapticFeedbackEnabled: Bool {
        repository.project.isMarkerHapticFeedbackEnabled
    }

    var bpm: Double? {
        timeline?.bpm
    }

    var isBeatGridEnabled: Bool {
        timeline?.isBeatGridEnabled ?? false
    }

    var isSnapToGridEnabled: Bool {
        timeline?.isSnapToGridEnabled ?? false
    }

    var isMetronomeUserEnabled: Bool {
        timeline?.isMetronomeEnabled ?? false
    }

    /// Metronome is actively playing when user enabled it AND playback is active
    var isMetronomeEnabled: Bool {
        isMetronomeUserEnabled && isPlaying
    }

    var metronomeVolume: Float {
        metronome.volume
    }

    var beatGridOffset: Double {
        timeline?.beatGridOffset ?? 0
    }

    var prerollSeconds: Double {
        timeline?.prerollSeconds ?? 0
    }

    var timeSignature: TimeSignature {
        timeline?.timeSignature ?? .fourFour
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

        // Load audio and waveform asynchronously to prevent UI freeze
        Task { @MainActor in
            await loadTimelineDataAsync()
        }
    }

    /// Loads timeline data (audio, waveform) asynchronously
    /// Sets isLoading = false when complete
    private func loadTimelineDataAsync() async {
        defer {
            isLoading = false
            print("✅ Timeline loading complete")
        }

        guard let timelineAudio = timeline?.audio else {
            print("ℹ️ No audio in timeline, loading complete")
            return
        }

        self.duration = timelineAudio.duration

        // Load audio into player
        let audioURL = repository.audioPlaybackURL(relativePath: timelineAudio.relativePath)
        audioPlayer.load(url: audioURL)
        print("✅ Audio loaded into player: \(audioURL)")

        // Load or generate waveform cache
        let cacheKey = "\(timelineID.uuidString)_\(timelineAudio.id.uuidString)"
        self.waveformCacheKey = cacheKey

        if let cached = WaveformCache.load(cacheKey: cacheKey) {
            // Waveform found in cache
            self.waveformMipmaps = cached.mipmaps
            self.cachedWaveform = cached.mipmaps.first ?? []
            print("✅ Waveform loaded from cache: \(cached.mipmaps.count) mipmap levels")
        } else {
            // Generate waveform in background
            print("🌊 No waveform cache found, generating...")
            await generateWaveformCache(
                audio: timelineAudio,
                documentURL: repository.audioTempDirectory,
                cacheKey: cacheKey
            )
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

                    // Reset beat scheduling and play first beat immediately
                    self.beatScheduleGeneration += 1
                    self.nextScheduledBeat = Int.min
                    self.lastPlayedBeat = Int.min
                    self.playFirstBeatAndScheduleNext(at: self.currentTime)

                    print("▶️ [Detection] Playback started at frame \(startFrame)")
                } else {
                    // Playback stopped - cancel scheduled beats
                    self.previousFrame = -1
                    self.beatScheduleGeneration += 1
                    self.nextScheduledBeat = Int.min
                    self.lastPlayedBeat = Int.min
                    self.metronome.cancelAllScheduled()
                    print("🛑 [Detection] Playback stopped, tracking reset")
                }
            }
            .store(in: &cancellables)

        // MARK: - Marker Crossing & Beat Scheduling
        $currentTime
            .sink { [weak self] newTime in
                guard let self = self else { return }

                // ✅ Update next marker for auto-scroll (always)
                self.updateNextMarker(for: newTime)

                // Update visual beat indicator only when NOT playing;
                // during playback, currentBeat is updated by beat scheduling events
                // to avoid rapid flickering during rewind/scrub
                if !self.isPlaying {
                    self.updateCurrentBeat(at: newTime)
                }

                // ✅ CRITICAL: Only detect crossings during active playback
                guard self.isPlaying else { return }

                let currentFrame = Int(round(newTime * Double(self.fps)))

                // ✅ Handle backward movement (rewind during playback)
                if currentFrame < self.previousFrame {
                    let rewindedMarkers = self.markers.filter { marker in
                        let markerFrame = Int(round(marker.timeSeconds * Double(self.fps)))
                        return markerFrame > currentFrame
                    }
                    for marker in rewindedMarkers {
                        self.flashedMarkers.remove(marker.id)
                    }

                    // Cancel current beat schedule; don't reschedule immediately —
                    // the next forward-moving time update will schedule the correct beat,
                    // naturally debouncing rapid scroll/seek operations
                    if self.isMetronomeUserEnabled {
                        self.beatScheduleGeneration += 1
                        self.metronome.cancelAllScheduled()
                        self.nextScheduledBeat = Int.min
                        self.lastPlayedBeat = Int.min
                    }

                    self.previousFrame = currentFrame
                    return
                }

                // Skip if no movement
                guard currentFrame > self.previousFrame else { return }

                // === MARKER CROSSING DETECTION ===
                let crossedMarkers = self.markers.filter { marker in
                    let markerFrame = Int(round(marker.timeSeconds * Double(self.fps)))
                    if self.previousFrame == -1 {
                        return markerFrame >= 0 && markerFrame <= currentFrame
                    }
                    return self.previousFrame < markerFrame && markerFrame <= currentFrame
                }

                for marker in crossedMarkers {
                    guard !self.flashedMarkers.contains(marker.id) else { continue }
                    self.flashedMarkers.insert(marker.id)
                    self.flashCounter += 1
                    let event = MarkerFlashEvent(
                        markerID: marker.id,
                        markerName: marker.name,
                        eventID: self.flashCounter,
                        timestamp: Date()
                    )
                    self.markerFlashPublisher.send(event)
                }

                // === BEAT PRE-SCHEDULING ===
                // On each time update, ensure the next beat is scheduled
                // Skip during scrubbing — metronome is muted
                if self.isMetronomeUserEnabled, !self.isScrubbing, let _ = self.bpm {
                    self.scheduleNextBeat(at: newTime)
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

    // MARK: - Beat Calculation (Metronome)

    /// Calculates the absolute beat number at a given time
    /// Pure function: beat = f(time, bpm, offset)
    private func calculateAbsoluteBeat(at time: Double) -> Int {
        guard let bpm = bpm, bpm > 0 else { return 0 }
        let beatInterval = 60.0 / bpm
        let timeFromOffset = time - beatGridOffset
        return Int(floor(timeFromOffset / beatInterval))
    }

    /// Calculates beat position within bar (0-based)
    private func calculateBeatInBar(absoluteBeat: Int) -> Int {
        let beatsPerBar = timeSignature.beatsPerBar
        return ((absoluteBeat % beatsPerBar) + beatsPerBar) % beatsPerBar
    }

    /// Calculates the exact audio time of a given absolute beat
    private func beatTime(forAbsoluteBeat beat: Int) -> Double {
        guard let bpm = bpm, bpm > 0 else { return 0 }
        let beatInterval = 60.0 / bpm
        return beatGridOffset + Double(beat) * beatInterval
    }

    /// Updates the visual beat indicator
    private func updateCurrentBeat(at time: Double) {
        guard let _ = bpm else {
            currentBeat = 0
            return
        }
        let absoluteBeat = calculateAbsoluteBeat(at: time)
        let beatInBar = calculateBeatInBar(absoluteBeat: absoluteBeat)
        if currentBeat != beatInBar {
            currentBeat = beatInBar
        }
    }

    // MARK: - Beat Pre-Scheduling (Host-Time Accurate)
    //
    // Uses AVAudioTime(hostTime:) for sample-accurate beat placement.
    // The key insight: we anchor beat scheduling to the time observer's
    // (hostTime, audioTime) pair, making the calculation self-correcting
    // regardless of any processing pipeline delays.

    /// Called at playback start: plays the first beat immediately and schedules the next
    private func playFirstBeatAndScheduleNext(at time: Double) {
        guard isMetronomeUserEnabled, let bpm = bpm, bpm > 0 else { return }

        let beatInterval = 60.0 / bpm
        let timeFromOffset = time - beatGridOffset
        let currentBeatPosition = timeFromOffset / beatInterval
        let currentAbsoluteBeat = Int(floor(currentBeatPosition))
        let fractionalPart = currentBeatPosition - floor(currentBeatPosition)

        let tolerance = 0.020  // 20ms
        let timeSinceBeat = fractionalPart * beatInterval

        if timeSinceBeat < tolerance {
            // We're right on a beat - play it now
            let beatInBar = calculateBeatInBar(absoluteBeat: currentAbsoluteBeat)
            metronome.playClick(isAccent: beatInBar == 0)
            lastPlayedBeat = currentAbsoluteBeat
            currentBeat = beatInBar

            // Schedule the NEXT beat
            let nextBeat = currentAbsoluteBeat + 1
            let nextBeatAudioTime = beatTime(forAbsoluteBeat: nextBeat)
            let delay = max(0.001, nextBeatAudioTime - time)
            scheduleSpecificBeat(nextBeat, afterDelay: delay)
        } else {
            // We're between beats - schedule the next upcoming beat
            let nextBeat = currentAbsoluteBeat + 1
            let nextBeatAudioTime = beatTime(forAbsoluteBeat: nextBeat)
            let delay = max(0.001, nextBeatAudioTime - time)
            scheduleSpecificBeat(nextBeat, afterDelay: delay)
        }
    }

    /// Pre-schedules the next beat click based on current position.
    /// Called on every time observer update during playback.
    private func scheduleNextBeat(at time: Double) {
        guard isMetronomeUserEnabled, let bpm = bpm, bpm > 0 else { return }

        let beatInterval = 60.0 / bpm
        let timeFromOffset = time - beatGridOffset
        let currentBeatPosition = timeFromOffset / beatInterval

        // After a reset (seek/rewind), check if we just passed a beat
        if nextScheduledBeat == Int.min {
            let floorBeat = Int(floor(currentBeatPosition))
            let floorBeatTime = beatTime(forAbsoluteBeat: floorBeat)
            let timeSinceFloorBeat = time - floorBeatTime
            if timeSinceFloorBeat >= 0 && timeSinceFloorBeat < 0.030 {
                let beatInBar = calculateBeatInBar(absoluteBeat: floorBeat)
                if floorBeat > lastPlayedBeat {
                    metronome.playClick(isAccent: beatInBar == 0)
                    lastPlayedBeat = floorBeat
                    currentBeat = beatInBar
                }
                nextScheduledBeat = floorBeat
            }
        }

        let nextBeat = Int(ceil(currentBeatPosition))
        guard nextBeat > nextScheduledBeat else { return }

        let nextBeatAudioTime = beatTime(forAbsoluteBeat: nextBeat)
        let delay = nextBeatAudioTime - time
        guard delay > -0.010 && delay < beatInterval * 2 else { return }

        if delay <= 0.002 {
            // Beat is essentially NOW - play immediately
            let beatInBar = calculateBeatInBar(absoluteBeat: nextBeat)
            if nextBeat > lastPlayedBeat {
                metronome.playClick(isAccent: beatInBar == 0)
                lastPlayedBeat = nextBeat
                currentBeat = beatInBar
            }
            nextScheduledBeat = nextBeat

            // Schedule the one after
            let afterNext = nextBeat + 1
            let afterNextDelay = max(0.001, beatTime(forAbsoluteBeat: afterNext) - time)
            scheduleSpecificBeat(afterNext, afterDelay: afterNextDelay)
        } else {
            scheduleSpecificBeat(nextBeat, afterDelay: delay)
        }
    }

    /// Schedules a specific beat using host-time-anchored calculation.
    /// Self-correcting: uses the time observer's (hostTime, audioTime) pair
    /// to calculate the exact host time for the beat, eliminating pipeline latency.
    private func scheduleSpecificBeat(_ beat: Int, afterDelay delay: Double) {
        guard delay > 0 else { return }

        nextScheduledBeat = beat
        let beatInBar = calculateBeatInBar(absoluteBeat: beat)
        let isAccent = (beatInBar == 0)

        // Calculate exact host time for this beat anchored to the time observer's
        // reference point. This self-corrects for any processing pipeline delays:
        // even if main queue adds 50ms of latency, the host time is calculated
        // relative to when the time observer actually fired, not relative to "now".
        let beatAudioTime = beatTime(forAbsoluteBeat: beat)
        let observerHostTime = audioPlayer.lastTimeObserverHostTime
        let observerAudioTime = audioPlayer.lastTimeObserverAudioTime

        let hostTime: UInt64
        if observerHostTime > 0 {
            let delayFromObserver = beatAudioTime - observerAudioTime
            if delayFromObserver > 0 {
                hostTime = observerHostTime + UInt64(delayFromObserver * MetronomeService.hostTicksPerSecond)
            } else {
                // Beat time already passed relative to observer — play now
                hostTime = mach_absolute_time()
            }
        } else {
            // Fallback before first observer update
            hostTime = MetronomeService.hostTime(afterDelay: delay)
        }

        metronome.scheduleClickAtHostTime(hostTime, isAccent: isAccent)

        // Update visual state when the beat fires
        let gen = self.beatScheduleGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self,
                  self.isPlaying,
                  self.beatScheduleGeneration == gen else { return }

            if beat > self.lastPlayedBeat {
                self.lastPlayedBeat = beat
                self.currentBeat = beatInBar
            }
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
    
    // MARK: - Scrubbing (mute audio/metronome during drag)

    /// True while user is dragging the playhead or capsule
    private var isScrubbing: Bool = false
    /// Remembers whether playback was active before scrub started
    private var wasPlayingBeforeScrub: Bool = false

    func startScrubbing() {
        guard !isScrubbing else { return }
        isScrubbing = true
        wasPlayingBeforeScrub = isPlaying
        // Mute audio output but keep player running so time updates continue
        audioPlayer.setMuted(true)
        // Cancel metronome beats during scrub
        metronome.cancelAllScheduled()
        beatScheduleGeneration += 1
        nextScheduledBeat = Int.min
        lastPlayedBeat = Int.min
    }

    func stopScrubbing() {
        guard isScrubbing else { return }
        isScrubbing = false
        audioPlayer.setMuted(false)
        // Re-schedule metronome if still playing
        if isPlaying && isMetronomeUserEnabled {
            beatScheduleGeneration += 1
            nextScheduledBeat = Int.min
            lastPlayedBeat = Int.min
            playFirstBeatAndScheduleNext(at: currentTime)
        }
    }

    // MARK: - Playback

    func togglePlayPause() {
        // Don't start playback if playhead is at the end of timeline
        if !isPlaying && duration > 0 && currentTime >= duration - 0.01 {
            return
        }
        audioPlayer.togglePlayPause()
    }
    
    func seek(to time: Double) {
        let clamped = max(0, min(time, duration))
        // Use direct absolute positioning for more responsive micro-movements
        audioPlayer.seekTo(time: clamped)
    }
    
    func seekBackward() {
        audioPlayer.seek(by: -5)
    }
    
    func seekForward() {
        audioPlayer.seek(by: 5)
    }
    
    // MARK: - Markers

    func addMarker(name: String, tagId: UUID, at time: Double) {
        // Применяем привязку к сетке битов, если включена
        var adjustedTime = snapToBeatGrid(time)
        // ✅ Квантуем время к ближайшему кадру
        adjustedTime = quantizeToFrame(adjustedTime)

        let marker = TimelineMarker(
            timeSeconds: adjustedTime,
            name: name,
            tagId: tagId
        )

        // Use undo manager for this action
        let action = AddMarkerAction(marker: marker)
        undoManager.performAction(action)

        print("✅ Marker '\(name)' added at time: \(String(format: "%.6f", adjustedTime))s with tagId: \(tagId)")
    }

    func pausePlayback() {
        audioPlayer.pause()
    }

    func resumePlayback() {
        audioPlayer.play()
    }

    func moveMarker(_ marker: TimelineMarker, to newTime: Double) {
        // Применяем привязку к сетке битов, если включена
        var adjustedTime = snapToBeatGrid(newTime)
        // ✅ Квантуем время при перемещении маркера
        adjustedTime = quantizeToFrame(adjustedTime)

        // Use undo manager for this action
        let action = ChangeMarkerTimeAction(
            markerID: marker.id,
            oldTime: marker.timeSeconds,
            newTime: adjustedTime
        )
        undoManager.performAction(action)

        print("✅ Marker moved to time: \(String(format: "%.6f", adjustedTime))s (from \(String(format: "%.6f", newTime))s)")
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

    // MARK: - CSV Import/Export

    func importMarkersFromCSV(_ csvContent: String) {
        let importedMarkers = MarkersCSVImporter.importFromCSV(csvContent, fps: fps)

        for marker in importedMarkers {
            // Use add action for undo/redo
            let action = AddMarkerAction(marker: marker)
            undoManager.performAction(action)
        }

        print("✅ Imported \(importedMarkers.count) markers from CSV")
    }

    // MARK: - Timeline

    func renameTimeline(to newName: String) {
        repository.renameTimeline(id: timelineID, newName: newName)
    }

    // MARK: - BPM and Beat Grid

    func setBPM(_ bpm: Double?) {
        guard let idx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        repository.project.timelines[idx].bpm = bpm
        objectWillChange.send()
    }

    func toggleBeatGrid() {
        guard let idx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        repository.project.timelines[idx].isBeatGridEnabled.toggle()
        objectWillChange.send()
    }

    func toggleSnapToGrid() {
        guard let idx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        repository.project.timelines[idx].isSnapToGridEnabled.toggle()
        objectWillChange.send()
    }

    func toggleMetronome() {
        guard let idx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        repository.project.timelines[idx].isMetronomeEnabled.toggle()

        // Reset beat scheduling when toggling metronome
        if repository.project.timelines[idx].isMetronomeEnabled && isPlaying {
            // Enabled during playback - start scheduling from current position
            beatScheduleGeneration += 1
            nextScheduledBeat = Int.min
            lastPlayedBeat = Int.min
            playFirstBeatAndScheduleNext(at: currentTime)
            print("🥁 [Metronome] Enabled during playback, scheduling from current position")
        } else if !repository.project.timelines[idx].isMetronomeEnabled {
            // Disabled - cancel any scheduled beats and invalidate pending callbacks
            metronome.cancelAllScheduled()
            beatScheduleGeneration += 1
            nextScheduledBeat = Int.min
            lastPlayedBeat = Int.min
            print("🥁 [Metronome] Disabled, cancelled scheduled beats")
        }

        objectWillChange.send()
    }

    func setBeatGridOffset(_ offset: Double) {
        guard let idx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        repository.project.timelines[idx].beatGridOffset = offset
        objectWillChange.send()
    }

    func commitBeatGridOffsetChange(oldOffset: Double, newOffset: Double) {
        // Register the change in undo system
        let action = ChangeBeatGridOffsetAction(oldOffset: oldOffset, newOffset: newOffset)
        // Note: The action won't re-execute since the value is already set
        // We just need to add it to the undo stack
        undoManager.performAction(action)
        print("✅ Beat grid offset change committed: \(oldOffset) → \(newOffset)")
    }

    func setPrerollSeconds(_ seconds: Double) {
        guard let idx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        repository.project.timelines[idx].prerollSeconds = max(0, seconds)
        objectWillChange.send()
    }

    func setTimeSignature(_ signature: TimeSignature) {
        guard let idx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        repository.project.timelines[idx].timeSignature = signature
        objectWillChange.send()
    }

    /// Квантует время к ближайшему биту, если включена привязка к сетке
    private func snapToBeatGrid(_ time: Double) -> Double {
        guard isSnapToGridEnabled, let bpm = bpm, bpm > 0 else {
            return time
        }

        let beatInterval = 60.0 / bpm  // seconds per beat
        let beatNumber = round(time / beatInterval)
        return beatNumber * beatInterval
    }

    // MARK: - Metronome

    func setMetronomeVolume(_ volume: Float) {
        metronome.setVolume(volume)
        objectWillChange.send()
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
