import Foundation
import AVFoundation
import Combine

/// Сервис метронома на базе AVAudioEngine
/// Поддерживает как мгновенное воспроизведение, так и pre-scheduling
@MainActor
class MetronomeService: ObservableObject {

    @Published private(set) var volume: Float = 0.5

    // AVAudioEngine для низкой latency
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    // Pre-buffered audio data
    private var clickBuffer: AVAudioPCMBuffer?
    private var accentBuffer: AVAudioPCMBuffer?

    // Pre-scheduling timer
    private var scheduleTimer: DispatchSourceTimer?

    init() {
        setupAudioEngine()
    }

    deinit {
        scheduleTimer?.cancel()
        audioEngine?.stop()
    }

    // MARK: - Setup

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

    /// Ensures the audio engine is running
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

    /// Воспроизводит клик немедленно (для первого бита при старте)
    func playClick(isAccent: Bool) {
        ensureEngineRunning()
        guard let node = playerNode else { return }

        let buffer = isAccent ? accentBuffer : clickBuffer
        guard let buffer = buffer else { return }

        node.volume = volume
        node.scheduleBuffer(buffer, at: nil, options: .interrupts) { }
    }

    /// Планирует клик через указанную задержку (в секундах)
    /// Использует DispatchSourceTimer для точности ~1ms
    func scheduleClick(afterDelay delay: Double, isAccent: Bool) {
        scheduleTimer?.cancel()

        guard delay > 0.001 else {
            // Delay too small, play immediately
            playClick(isAccent: isAccent)
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + delay,
            leeway: .microseconds(500)  // 0.5ms precision
        )
        timer.setEventHandler { [weak self] in
            self?.playClick(isAccent: isAccent)
        }
        timer.resume()
        scheduleTimer = timer
    }

    /// Отменяет запланированный клик
    func cancelScheduled() {
        scheduleTimer?.cancel()
        scheduleTimer = nil
    }

    /// Обновляет громкость
    func setVolume(_ newVolume: Float) {
        self.volume = max(0, min(1, newVolume))
        playerNode?.volume = self.volume
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
