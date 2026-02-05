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

    // MARK: - Preroll Playback

    /// True while the playhead is advancing through the preroll zone (silence before audio)
    @Published private(set) var isInPreroll: Bool = false

    /// Timer that drives currentTime during preroll at ~60fps
    private var prerollTimer: Timer?

    /// Wall-clock reference for preroll timer
    private var prerollLastTickTime: CFTimeInterval = 0

    /// Host time when preroll started — used for sample-accurate beat scheduling during preroll
    private var prerollStartHostTime: UInt64 = 0

    /// currentTime value when preroll started
    private var prerollStartPosition: Double = 0

    /// Flag to prevent the $isPlaying sink from resetting beats when transitioning from preroll to audio
    private var skipNextPlaybackReset: Bool = false

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
        // During preroll, we manage isPlaying ourselves (audio player is paused but timeline is "playing")
        audioPlayer.$isPlaying
            .sink { [weak self] playing in
                guard let self = self else { return }
                if !self.isInPreroll {
                    self.isPlaying = playing
                }
            }
            .store(in: &cancellables)

        // During preroll, currentTime is driven by preroll timer, not audio player.
        // During scrubbing, currentTime is driven by the drag gesture.
        // Also guard against overwriting a manual preroll-zone position while paused:
        // audioPlayer.seekTo publishes currentTime=0 which would clobber our negative value.
        audioPlayer.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] t in
                guard let self = self, !self.isInPreroll else { return }
                // During scrubbing, position is driven by the drag gesture
                if self.isScrubbing { return }
                // Don't overwrite manually-set preroll position when paused
                if self.currentTime < 0 && !self.isPlaying {
                    return
                }
                self.currentTime = t
            }
            .store(in: &cancellables)

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

                    if self.skipNextPlaybackReset {
                        // Transitioning from preroll to audio — beats are already scheduled
                        self.skipNextPlaybackReset = false
                    } else {
                        // Normal playback start — reset and schedule beats
                        self.beatScheduleGeneration += 1
                        self.nextScheduledBeat = Int.min
                        self.lastPlayedBeat = Int.min
                        self.playFirstBeatAndScheduleNext(at: self.currentTime)
                    }
                } else {
                    // Playback stopped - cancel scheduled beats
                    self.previousFrame = -1
                    self.beatScheduleGeneration += 1
                    self.nextScheduledBeat = Int.min
                    self.lastPlayedBeat = Int.min
                    self.metronome.cancelAllScheduled()
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

    /// Called at playback start: plays the first beat immediately and pre-schedules the next 2.
    /// Scheduling 2 beats ahead ensures the first beat after seek is always sample-accurate,
    /// since both are calculated from the same host-time reference point.
    private func playFirstBeatAndScheduleNext(at time: Double) {
        guard isMetronomeUserEnabled, let bpm = bpm, bpm > 0 else { return }

        let beatInterval = 60.0 / bpm
        let timeFromOffset = time - beatGridOffset
        let currentBeatPosition = timeFromOffset / beatInterval
        let currentAbsoluteBeat = Int(floor(currentBeatPosition))
        let fractionalPart = currentBeatPosition - floor(currentBeatPosition)

        let tolerance = 0.020  // 20ms
        let timeSinceBeat = fractionalPart * beatInterval

        var firstScheduledBeat: Int

        if timeSinceBeat < tolerance {
            // We're right on a beat - play it now
            let beatInBar = calculateBeatInBar(absoluteBeat: currentAbsoluteBeat)
            metronome.playClick(isAccent: beatInBar == 0)
            lastPlayedBeat = currentAbsoluteBeat
            currentBeat = beatInBar
            firstScheduledBeat = currentAbsoluteBeat + 1
        } else {
            // We're between beats - start from the next upcoming beat
            firstScheduledBeat = currentAbsoluteBeat + 1
        }

        // Pre-schedule the next 2 beats for reliable timing after seek/start
        for i in 0..<2 {
            let beat = firstScheduledBeat + i
            let beatAudioTime = beatTime(forAbsoluteBeat: beat)
            let delay = beatAudioTime - time
            if delay > 0 && delay < beatInterval * 3 {
                scheduleSpecificBeat(beat, afterDelay: delay)
            }
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
                // Pre-schedule next beat immediately to avoid gap
                let nextBeat = floorBeat + 1
                let nextBeatDelay = beatTime(forAbsoluteBeat: nextBeat) - time
                if nextBeatDelay > 0 && nextBeatDelay < beatInterval * 3 {
                    scheduleSpecificBeat(nextBeat, afterDelay: nextBeatDelay)
                }
                return
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

        // Calculate exact host time for the beat.
        // Two reference sources depending on playback mode:
        // 1. During audio playback: anchor to time observer's (hostTime, audioTime) pair
        // 2. During preroll: anchor to preroll start (hostTime, position) pair
        let beatAudioTime = beatTime(forAbsoluteBeat: beat)

        let hostTime: UInt64
        if isInPreroll && prerollStartHostTime > 0 {
            // Preroll mode: calculate from preroll start reference
            let delayFromPrerollStart = beatAudioTime - prerollStartPosition
            if delayFromPrerollStart > 0 {
                hostTime = prerollStartHostTime + UInt64(delayFromPrerollStart * MetronomeService.hostTicksPerSecond)
            } else {
                hostTime = mach_absolute_time()
            }
        } else {
            let observerHostTime = audioPlayer.lastTimeObserverHostTime
            let observerAudioTime = audioPlayer.lastTimeObserverAudioTime
            if observerHostTime > 0 {
                let delayFromObserver = beatAudioTime - observerAudioTime
                if delayFromObserver > 0 {
                    hostTime = observerHostTime + UInt64(delayFromObserver * MetronomeService.hostTicksPerSecond)
                } else {
                    hostTime = mach_absolute_time()
                }
            } else {
                hostTime = MetronomeService.hostTime(afterDelay: delay)
            }
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
    
    // MARK: - Preroll Playback Control

    /// Starts preroll countdown. Drives currentTime from negative toward 0, then starts audio.
    private func startPreroll(from position: Double? = nil) {
        let startPos = position ?? currentTime
        guard startPos < 0 else { return }

        isInPreroll = true
        isPlaying = true
        prerollStartHostTime = mach_absolute_time()
        prerollStartPosition = startPos
        prerollLastTickTime = CFAbsoluteTimeGetCurrent()
        currentTime = startPos

        // Pre-seek audio player to time 0 now so it's ready for seamless
        // transition when preroll finishes (eliminates micro-pause at the boundary).
        // The isInPreroll guard in the binding prevents this from overwriting currentTime.
        audioPlayer.seekTo(time: 0)

        // Start beat scheduling for preroll zone
        beatScheduleGeneration += 1
        nextScheduledBeat = Int.min
        lastPlayedBeat = Int.min
        let startFrame = Int(round(startPos * Double(fps)))
        previousFrame = startFrame
        flashedMarkers.removeAll()
        playFirstBeatAndScheduleNext(at: startPos)

        // 60fps timer to advance currentTime through preroll
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isInPreroll else { return }
            let now = CFAbsoluteTimeGetCurrent()
            let elapsed = now - self.prerollLastTickTime
            self.prerollLastTickTime = now

            let newTime = self.currentTime + elapsed
            if newTime >= 0 {
                // Preroll finished — transition to audio playback
                self.currentTime = 0
                self.finishPreroll()
            } else {
                self.currentTime = newTime
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        prerollTimer = timer
    }

    /// Transitions from preroll to audio playback seamlessly
    private func finishPreroll() {
        prerollTimer?.invalidate()
        prerollTimer = nil
        isInPreroll = false
        // Don't reset beats — preroll already scheduled them through time 0
        skipNextPlaybackReset = true
        // Audio player was pre-seeked to time 0 in startPreroll() —
        // just start playback for a seamless, zero-gap transition.
        audioPlayer.play()
        // isPlaying will be confirmed by the audioPlayer binding
    }

    /// Stops preroll without transitioning to audio
    private func stopPreroll() {
        prerollTimer?.invalidate()
        prerollTimer = nil
        isInPreroll = false
        isPlaying = false
        beatScheduleGeneration += 1
        nextScheduledBeat = Int.min
        lastPlayedBeat = Int.min
        metronome.cancelAllScheduled()
    }

    // MARK: - Scrubbing (mute audio/metronome during drag)

    /// True while user is dragging the playhead or capsule
    private var isScrubbing: Bool = false
    /// Remembers whether playback was active before scrub started
    private var wasPlayingBeforeScrub: Bool = false

    func startScrubbing() {
        guard !isScrubbing else { return }
        isScrubbing = true
        wasPlayingBeforeScrub = isPlaying || isInPreroll
        // Mute audio output but keep player running so time updates continue
        audioPlayer.setMuted(true)
        // Stop preroll timer during scrub (position is driven by drag)
        if isInPreroll {
            prerollTimer?.invalidate()
            prerollTimer = nil
        }
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

        if wasPlayingBeforeScrub {
            if currentTime < 0 {
                // In preroll zone — pause audio player and start preroll timer
                audioPlayer.pause()
                isInPreroll = false // Reset so startPreroll can set it
                isPlaying = false
                startPreroll(from: currentTime)
            } else if isInPreroll {
                // Was in preroll but now in audio zone
                isInPreroll = false
                isPlaying = false
                skipNextPlaybackReset = true
                beatScheduleGeneration += 1
                nextScheduledBeat = Int.min
                lastPlayedBeat = Int.min
                playFirstBeatAndScheduleNext(at: currentTime)
                audioPlayer.seekTo(time: currentTime)
                audioPlayer.play()
            } else if isPlaying && isMetronomeUserEnabled {
                // Normal audio playback — re-schedule metronome
                beatScheduleGeneration += 1
                nextScheduledBeat = Int.min
                lastPlayedBeat = Int.min
                playFirstBeatAndScheduleNext(at: currentTime)
            }
        } else if isInPreroll {
            // Was paused in preroll — just stop preroll state
            stopPreroll()
        }
    }

    // MARK: - Playback

    func togglePlayPause() {
        // Already playing (including preroll) — stop
        if isPlaying || isInPreroll {
            if isInPreroll { stopPreroll() }
            audioPlayer.pause()
            isPlaying = false
            return
        }

        // Don't start playback if playhead is at the end of timeline
        if duration > 0 && currentTime >= duration - 0.01 {
            return
        }

        if currentTime < 0 {
            // Playhead is in preroll zone — start preroll countdown
            startPreroll()
        } else {
            // Playhead is in audio zone — start audio playback
            audioPlayer.play()
        }
    }

    func seek(to time: Double) {
        let minTime = prerollSeconds > 0 ? -prerollSeconds : 0
        let clamped = max(minTime, min(time, duration))

        // During scrubbing: just move playhead position.
        // Don't start/stop preroll or schedule beats — the drag gesture drives position.
        if isScrubbing {
            currentTime = clamped
            if clamped >= 0 {
                // In audio zone: also seek audio player for scrub preview
                audioPlayer.seekTo(time: clamped)
            }
            return
        }

        if clamped < 0 {
            // Seeking into preroll zone
            if isInPreroll {
                // Already in preroll — restart timer from new position
                stopPreroll()
                currentTime = clamped
                startPreroll(from: clamped)
            } else if isPlaying {
                // Was playing audio — pause audio and start preroll
                audioPlayer.pause()
                currentTime = clamped
                startPreroll(from: clamped)
            } else {
                // Not playing — just move playhead into preroll zone.
                // Don't seek audio player here — preroll will handle
                // the transition to audio time 0 when playback starts.
                currentTime = clamped
            }
        } else {
            // Seeking into audio zone
            if isInPreroll {
                // Was in preroll — stop it and resume audio from new position
                let wasPlaying = true // preroll means we were playing
                stopPreroll()
                isPlaying = false
                currentTime = clamped
                audioPlayer.seekTo(time: clamped)
                if wasPlaying {
                    skipNextPlaybackReset = true
                    beatScheduleGeneration += 1
                    nextScheduledBeat = Int.min
                    lastPlayedBeat = Int.min
                    playFirstBeatAndScheduleNext(at: clamped)
                    audioPlayer.play()
                }
            } else {
                // Set currentTime immediately to prevent binding race
                // (e.g. when transitioning from preroll zone where guard blocks updates)
                currentTime = clamped
                audioPlayer.seekTo(time: clamped)
            }
        }
    }

    func seekBackward() {
        seek(to: currentTime - 5)
    }

    func seekForward() {
        seek(to: currentTime + 5)
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
        // Display time is always positive: 0 = start of timeline (including preroll),
        // prerollSeconds = start of audio file.
        let displayTime = max(0, currentTime + prerollSeconds)
        let totalFrames = Int(displayTime * Double(fps))
        let frames = totalFrames % fps
        let totalSeconds = totalFrames / fps
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60

        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
}
