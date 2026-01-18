import Foundation
import AVFoundation
import Combine

@MainActor
final class TimelineViewModel: ObservableObject {

    private let repository: ProjectRepository
    private let timelineID: UUID
    
    private let audioPlayer = AudioPlayerService()
    
    @Published private(set) var name: String = ""
    @Published private(set) var fps: Int = 30
    @Published private(set) var audio: TimelineAudio?
    @Published private(set) var markers: [TimelineMarker] = []
    
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    
    @Published var zoomScale: CGFloat = 1.0
    
    @Published private(set) var cachedWaveform: [Float] = []
    private var waveformCacheKey: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    // ✅ НОВОЕ: Throttle для currentTime
    private var currentTimeSubject = PassthroughSubject<Double, Never>()
    
    // MARK: - Computed
    
    var visibleMarkers: [TimelineMarker] {
        markers
    }
    
    var visibleWaveform: [Float] {
        guard !cachedWaveform.isEmpty else { return [] }
        
        // ✅ КРИТИЧНО: Агрессивный downsample
        let targetSamples = zoomScale < 2.0 ? 400 : 800
        let adjustedTarget = targetSamples * 2 // min/max пары
        
        if cachedWaveform.count <= adjustedTarget {
            return cachedWaveform
        }
        
        // ✅ Простой decimation вместо сложного алгоритма
        let step = cachedWaveform.count / adjustedTarget
        var result: [Float] = []
        result.reserveCapacity(adjustedTarget)
        
        for i in stride(from: 0, to: cachedWaveform.count, by: step) {
            if i < cachedWaveform.count {
                result.append(cachedWaveform[i])
            }
            if result.count >= adjustedTarget {
                break
            }
        }
        
        return result
    }
    
    // MARK: - Init
    
    init(repository: ProjectRepository, timelineID: UUID) {
        self.repository = repository
        self.timelineID = timelineID
        
        loadTimeline()
        setupBindings()
        
        if let audio = audio, let docURL = repository.documentURL {
            loadWaveformCache(for: audio, documentURL: docURL)
        }
    }
    
    private func loadTimeline() {
        guard let timeline = repository.project.timelines.first(where: { $0.id == timelineID }) else {
            return
        }
        
        name = timeline.name
        fps = timeline.fps
        audio = timeline.audio
        markers = timeline.markers
        duration = timeline.audio?.duration ?? 0
    }
    
    private func setupBindings() {
        audioPlayer.$isPlaying
            .assign(to: &$isPlaying)
        
        // ✅ КРИТИЧНО: Throttle currentTime updates
        audioPlayer.$currentTime
            .throttle(for: .milliseconds(32), scheduler: RunLoop.main, latest: true)
            .assign(to: &$currentTime)
        
        audioPlayer.$duration
            .sink { [weak self] d in
                if d > 0 {
                    self?.duration = d
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Waveform Cache
    
    private func loadWaveformCache(for audio: TimelineAudio, documentURL: URL) {
        let cacheKey = "\(timelineID.uuidString)_\(audio.id.uuidString)"
        self.waveformCacheKey = cacheKey
        
        if let cached = WaveformCache.load(cacheKey: cacheKey) {
            // ✅ Выбираем средний уровень детализации для баланса
            let levelIndex = min(2, cached.mipmaps.count - 1)
            self.cachedWaveform = cached.mipmaps[levelIndex]
            print("✅ Waveform loaded from cache: \(self.cachedWaveform.count) samples (level \(levelIndex))")
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
            print("✅ Waveform generated: \(cached.mipmaps.count) levels")
            
            await MainActor.run {
                let levelIndex = min(2, cached.mipmaps.count - 1)
                self.cachedWaveform = cached.mipmaps[levelIndex]
                print("✅ Waveform cached: \(self.cachedWaveform.count) samples (level \(levelIndex))")
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
        duration: Double
    ) throws {
        print("🎵 addAudio called: \(originalFileName), duration: \(duration)s")
        
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
            duration: duration
        )
        
        print("🎵 Updating timeline audio...")
        
        if let idx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }) {
            repository.project.timelines[idx].audio = newAudio
            print("✅ Timeline audio updated in repository")
        } else {
            print("❌ Timeline not found in repository")
        }
        
        audio = newAudio
        self.duration = duration
        
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
            let audio = audio,
            let docURL = repository.documentURL
        else { return }
        
        let manager = AudioFileManager(documentURL: docURL)
        try? manager.deleteAudioFile(fileName: audio.relativePath)
        
        if let idx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }) {
            repository.project.timelines[idx].audio = nil
        }
        
        self.audio = nil
        self.duration = 0
        self.currentTime = 0
        
        self.cachedWaveform = []
        self.waveformCacheKey = nil
        
        audioPlayer.stop()
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
        let marker = TimelineMarker(
            timeSeconds: currentTime,
            name: "Marker \(markers.count + 1)"
        )
        
        repository.addMarker(timelineID: timelineID, marker: marker)
        markers.append(marker)
    }
    
    func moveMarker(_ marker: TimelineMarker, to newTime: Double) {
        if let timelineIdx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }),
           let markerIdx = repository.project.timelines[timelineIdx].markers.firstIndex(where: { $0.id == marker.id }) {
            repository.project.timelines[timelineIdx].markers[markerIdx].timeSeconds = newTime
        }
        
        if let idx = markers.firstIndex(where: { $0.id == marker.id }) {
            markers[idx].timeSeconds = newTime
        }
    }
    
    func renameMarker(_ marker: TimelineMarker, to newName: String) {
        if let timelineIdx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }),
           let markerIdx = repository.project.timelines[timelineIdx].markers.firstIndex(where: { $0.id == marker.id }) {
            repository.project.timelines[timelineIdx].markers[markerIdx].name = newName
        }
        
        if let idx = markers.firstIndex(where: { $0.id == marker.id }) {
            markers[idx].name = newName
        }
    }
    
    func deleteMarker(_ marker: TimelineMarker) {
        if let timelineIdx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }) {
            repository.project.timelines[timelineIdx].markers.removeAll { $0.id == marker.id }
        }
        
        markers.removeAll { $0.id == marker.id }
    }
    
    // MARK: - Timeline
    
    func renameTimeline(to newName: String) {
        repository.renameTimeline(id: timelineID, newName: newName)
        name = newName
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
