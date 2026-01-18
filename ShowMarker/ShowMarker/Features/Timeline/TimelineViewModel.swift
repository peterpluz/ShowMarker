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
    
    // НОВОЕ: Кэш waveform
    @Published private(set) var cachedWaveform: [Float] = []
    private var waveformCacheKey: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed
    
    var visibleMarkers: [TimelineMarker] {
        markers
    }
    
    var visibleWaveform: [Float] {
        // ИСПРАВЛЕНО: используем кэшированную waveform
        guard !cachedWaveform.isEmpty else { return [] }
        
        // Выбираем оптимальный уровень детализации
        let targetSamples = Int(800 * 2) // ~800pt ширина экрана iPhone
        
        // При минимальном зуме используем более агрессивное сжатие
        let adjustedTarget = zoomScale < 2.0 ? targetSamples / 4 : targetSamples
        
        if cachedWaveform.count <= adjustedTarget * 2 {
            return cachedWaveform
        }
        
        // Downsampling для производительности
        let step = max(1, cachedWaveform.count / (adjustedTarget * 2))
        var result: [Float] = []
        result.reserveCapacity(adjustedTarget * 2)
        
        var i = 0
        while i < cachedWaveform.count - 1 {
            let end = min(i + step * 2, cachedWaveform.count)
            let slice = cachedWaveform[i..<end]
            
            if slice.count >= 2 {
                let minVal = slice.enumerated()
                    .filter { $0.offset % 2 == 0 }
                    .map { $0.element }
                    .min() ?? 0
                
                let maxVal = slice.enumerated()
                    .filter { $0.offset % 2 == 1 }
                    .map { $0.element }
                    .max() ?? 0
                
                result.append(minVal)
                result.append(maxVal)
            }
            
            i += step * 2
        }
        
        return result
    }
    
    // MARK: - Init
    
    init(repository: ProjectRepository, timelineID: UUID) {
        self.repository = repository
        self.timelineID = timelineID
        
        loadTimeline()
        setupBindings()
        
        // ИСПРАВЛЕНО: загружаем waveform из кэша при инициализации
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
        
        audioPlayer.$currentTime
            .assign(to: &$currentTime)
        
        audioPlayer.$duration
            .sink { [weak self] d in
                if d > 0 {
                    self?.duration = d
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Waveform Cache - НОВОЕ
    
    private func loadWaveformCache(for audio: TimelineAudio, documentURL: URL) {
        let cacheKey = "\(timelineID.uuidString)_\(audio.id.uuidString)"
        self.waveformCacheKey = cacheKey
        
        // Пробуем загрузить из кэша
        if let cached = WaveformCache.load(cacheKey: cacheKey) {
            // Используем самый детальный уровень
            self.cachedWaveform = cached.mipmaps.first ?? []
            print("✅ Waveform loaded from cache: \(self.cachedWaveform.count) samples")
            return
        }
        
        print("🌊 No waveform cache found, will generate...")
        // Если кэша нет - генерируем асинхронно
        Task {
            await generateWaveformCache(audio: audio, documentURL: documentURL, cacheKey: cacheKey)
        }
    }
    
    private func generateWaveformCache(audio: TimelineAudio, documentURL: URL, cacheKey: String) async {
        print("🌊 generateWaveformCache started")
        do {
            // ИСПРАВЛЕНО: используем relativePath напрямую
            let audioURL = documentURL.appendingPathComponent(audio.relativePath)
            print("🌊 Audio URL: \(audioURL)")
            
            let cached = try await WaveformCache.generateAndCache(
                audioURL: audioURL,
                cacheKey: cacheKey
            )
            print("✅ Waveform generated: \(cached.mipmaps.count) levels")
            
            await MainActor.run {
                self.cachedWaveform = cached.mipmaps.first ?? []
                print("✅ Waveform cached: \(self.cachedWaveform.count) samples")
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
        // ИСПРАВЛЕНО: убрали "Audio/" - AudioFileManager сам добавляет путь
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        
        print("🎵 Adding audio file: \(fileName)")
        try manager.addAudioFile(sourceData: sourceData, fileName: fileName)
        print("✅ Audio file written")
        
        // ИСПРАВЛЕНО: relativePath должен содержать "Audio/" для правильного пути в модели
        let relativePath = "Audio/\(fileName)"
        let newAudio = TimelineAudio(
            relativePath: relativePath,
            originalFileName: originalFileName,
            duration: duration
        )
        
        print("🎵 Updating timeline audio...")
        
        // ИСПРАВЛЕНО: прямое изменение через project
        if let idx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }) {
            repository.project.timelines[idx].audio = newAudio
            print("✅ Timeline audio updated in repository")
        } else {
            print("❌ Timeline not found in repository")
        }
        
        audio = newAudio
        self.duration = duration
        
        print("🎵 Loading audio into player...")
        // ИСПРАВЛЕНО: используем relativePath (уже содержит Audio/)
        let audioURL = docURL.appendingPathComponent(newAudio.relativePath)
        audioPlayer.load(url: audioURL)
        print("✅ Audio loaded into player: \(audioURL)")
        
        // ИСПРАВЛЕНО: генерируем waveform сразу при импорте
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
        
        // ИСПРАВЛЕНО: прямое изменение через project
        if let idx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }) {
            repository.project.timelines[idx].audio = nil
        }
        
        self.audio = nil
        self.duration = 0
        self.currentTime = 0
        
        // ИСПРАВЛЕНО: очищаем waveform кэш
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
        // ИСПРАВЛЕНО: прямое изменение через project
        if let timelineIdx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }),
           let markerIdx = repository.project.timelines[timelineIdx].markers.firstIndex(where: { $0.id == marker.id }) {
            repository.project.timelines[timelineIdx].markers[markerIdx].timeSeconds = newTime
        }
        
        if let idx = markers.firstIndex(where: { $0.id == marker.id }) {
            markers[idx].timeSeconds = newTime
        }
    }
    
    func renameMarker(_ marker: TimelineMarker, to newName: String) {
        // ИСПРАВЛЕНО: прямое изменение через project
        if let timelineIdx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }),
           let markerIdx = repository.project.timelines[timelineIdx].markers.firstIndex(where: { $0.id == marker.id }) {
            repository.project.timelines[timelineIdx].markers[markerIdx].name = newName
        }
        
        if let idx = markers.firstIndex(where: { $0.id == marker.id }) {
            markers[idx].name = newName
        }
    }
    
    func deleteMarker(_ marker: TimelineMarker) {
        // ИСПРАВЛЕНО: прямое изменение через project
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
