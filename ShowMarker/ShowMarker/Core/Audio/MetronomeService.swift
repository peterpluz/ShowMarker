import Foundation
import AVFoundation
import Combine

/// Сервис метронома на базе AVAudioEngine для минимальной latency
/// Использует тот же audio output что и основное аудио для синхронизации
@MainActor
class MetronomeService: ObservableObject {

    @Published private(set) var volume: Float = 0.5

    // AVAudioEngine для низкой latency
    private var audioEngine: AVAudioEngine?
    private var clickPlayerNode: AVAudioPlayerNode?
    private var accentPlayerNode: AVAudioPlayerNode?

    // Pre-buffered audio data
    private var clickBuffer: AVAudioPCMBuffer?
    private var accentBuffer: AVAudioPCMBuffer?

    init() {
        setupAudioEngine()
    }

    deinit {
        audioEngine?.stop()
    }

    // MARK: - Setup

    private func setupAudioEngine() {
        let engine = AVAudioEngine()

        // Create player nodes
        let clickNode = AVAudioPlayerNode()
        let accentNode = AVAudioPlayerNode()

        // Add nodes to engine
        engine.attach(clickNode)
        engine.attach(accentNode)

        // Create mixer for volume control
        let mixer = engine.mainMixerNode
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

        // Connect nodes to mixer
        engine.connect(clickNode, to: mixer, format: format)
        engine.connect(accentNode, to: mixer, format: format)

        // Generate click sounds
        clickBuffer = generateClickBuffer(frequency: 1000, duration: 0.05, format: format)
        accentBuffer = generateClickBuffer(frequency: 1500, duration: 0.05, format: format)

        // Store references
        self.audioEngine = engine
        self.clickPlayerNode = clickNode
        self.accentPlayerNode = accentNode

        // Start engine
        do {
            try engine.start()
            print("✅ MetronomeService: AVAudioEngine started")
        } catch {
            print("⚠️ MetronomeService: Failed to start AVAudioEngine: \(error)")
        }
    }

    /// Воспроизводит клик метронома с минимальной latency
    /// - Parameter isAccent: true для первого бита такта (более высокий тон)
    func playClick(isAccent: Bool) {
        guard let engine = audioEngine, engine.isRunning else {
            // Try to restart engine if not running
            try? audioEngine?.start()
            return
        }

        let node = isAccent ? accentPlayerNode : clickPlayerNode
        let buffer = isAccent ? accentBuffer : clickBuffer

        guard let node = node, let buffer = buffer else { return }

        // Stop any currently playing sound to prevent overlap
        node.stop()

        // Set volume on the node
        node.volume = volume

        // Schedule buffer for immediate playback
        // Using .interrupt to play immediately without waiting
        node.scheduleBuffer(buffer, at: nil, options: .interrupts) { }
        node.play()
    }

    /// Обновляет громкость
    func setVolume(_ newVolume: Float) {
        self.volume = max(0, min(1, newVolume))
        clickPlayerNode?.volume = self.volume
        accentPlayerNode?.volume = self.volume
    }

    // MARK: - Audio Generation

    /// Генерирует PCM буфер с кликом
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
