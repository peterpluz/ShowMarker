import Foundation
import AVFoundation
import Combine

/// Сервис метронома на базе AVAudioEngine
/// Использует выделенную high-priority очередь для таймеров и воспроизведения,
/// чтобы UI-нагрузка на main queue не влияла на точность кликов.
class MetronomeService: ObservableObject {

    /// Volume exposed for SwiftUI bindings (updated on main queue)
    @Published private(set) var volume: Float = 0.5

    /// Dedicated high-priority queue for all audio operations and timers.
    /// Keeps click timing independent of main queue UI load.
    private let audioQueue = DispatchQueue(label: "com.showmarker.metronome", qos: .userInteractive)

    // Audio state — accessed ONLY from audioQueue after init
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var clickBuffer: AVAudioPCMBuffer?
    private var accentBuffer: AVAudioPCMBuffer?
    private var scheduleTimer: DispatchSourceTimer?
    private var currentVolume: Float = 0.5

    init() {
        // Setup synchronously so engine is ready before any playback calls
        audioQueue.sync {
            self.setupAudioEngine()
        }
    }

    deinit {
        scheduleTimer?.cancel()
        audioEngine?.stop()
    }

    // MARK: - Setup

    /// Must be called on audioQueue
    private func setupAudioEngine() {
        let engine = AVAudioEngine()

        let node = AVAudioPlayerNode()
        engine.attach(node)

        let mixer = engine.mainMixerNode
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

        engine.connect(node, to: mixer, format: format)

        // Generate click sounds with different tones
        clickBuffer = generateClickBuffer(frequency: 1000, duration: 0.05, format: format)
        accentBuffer = generateClickBuffer(frequency: 1500, duration: 0.05, format: format)

        self.audioEngine = engine
        self.playerNode = node

        do {
            try engine.start()
            node.play()  // Start node - it will wait for scheduled buffers
            print("✅ MetronomeService: AVAudioEngine started")
        } catch {
            print("⚠️ MetronomeService: Failed to start AVAudioEngine: \(error)")
        }
    }

    /// Ensures the audio engine is running. Must be called on audioQueue.
    private func ensureEngineRunning() {
        guard let engine = audioEngine else { return }
        if !engine.isRunning {
            do {
                try engine.start()
                playerNode?.play()
            } catch {
                print("⚠️ MetronomeService: Failed to restart engine: \(error)")
            }
        }
    }

    // MARK: - Playback

    /// Воспроизводит клик немедленно (для первого бита при старте).
    /// Dispatches to audioQueue so main queue load doesn't delay playback.
    func playClick(isAccent: Bool) {
        let vol = currentVolume
        audioQueue.async { [weak self] in
            self?.playClickOnQueue(isAccent: isAccent, volume: vol)
        }
    }

    /// Планирует клик через указанную задержку (в секундах).
    /// Timer fires on audioQueue for precise timing independent of main queue.
    func scheduleClick(afterDelay delay: Double, isAccent: Bool) {
        let vol = currentVolume
        audioQueue.async { [weak self] in
            guard let self = self else { return }

            self.scheduleTimer?.cancel()

            guard delay > 0.001 else {
                // Delay too small, play immediately
                self.playClickOnQueue(isAccent: isAccent, volume: vol)
                return
            }

            let timer = DispatchSource.makeTimerSource(queue: self.audioQueue)
            timer.schedule(
                deadline: .now() + delay,
                leeway: .microseconds(500)  // 0.5ms precision
            )
            timer.setEventHandler { [weak self] in
                self?.playClickOnQueue(isAccent: isAccent, volume: vol)
            }
            timer.resume()
            self.scheduleTimer = timer
        }
    }

    /// Отменяет запланированный клик
    func cancelScheduled() {
        audioQueue.async { [weak self] in
            self?.scheduleTimer?.cancel()
            self?.scheduleTimer = nil
        }
    }

    /// Обновляет громкость
    func setVolume(_ newVolume: Float) {
        let clamped = max(0, min(1, newVolume))
        currentVolume = clamped
        // Update @Published on main for SwiftUI
        DispatchQueue.main.async {
            self.volume = clamped
        }
        audioQueue.async { [weak self] in
            self?.playerNode?.volume = clamped
        }
    }

    // MARK: - Internal Playback (audioQueue only)

    /// Plays a click buffer immediately. Must be called on audioQueue.
    private func playClickOnQueue(isAccent: Bool, volume: Float) {
        ensureEngineRunning()
        guard let node = playerNode else { return }

        let buffer = isAccent ? accentBuffer : clickBuffer
        guard let buffer = buffer else { return }

        node.volume = volume
        node.scheduleBuffer(buffer, at: nil, options: .interrupts) { }
    }

    // MARK: - Audio Generation

    private func generateClickBuffer(
        frequency: Float,
        duration: Double,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else {
            return nil
        }

        let amplitude: Float = 0.5
        let omega = 2.0 * Float.pi * frequency / Float(sampleRate)

        for i in 0..<Int(frameCount) {
            let phase = omega * Float(i)
            let sineValue = sin(phase)

            // Apply exponential decay envelope for crisp click
            let envelope = exp(-Float(i) / Float(frameCount) * 5.0)

            channelData[i] = amplitude * sineValue * envelope
        }

        return buffer
    }
}
