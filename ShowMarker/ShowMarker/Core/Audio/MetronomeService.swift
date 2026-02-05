import Foundation
import AVFoundation
import Combine

/// Сервис метронома на базе AVAudioEngine с sample-accurate scheduling.
/// Использует AVAudioTime(hostTime:) для планирования кликов с точностью до семпла,
/// аналогично профессиональным DAW (Logic Pro, Reaper).
class MetronomeService: ObservableObject {

    /// Volume exposed for SwiftUI bindings (updated on main queue)
    @Published private(set) var volume: Float = 0.5

    /// Dedicated high-priority queue for all audio operations.
    private let audioQueue = DispatchQueue(label: "com.showmarker.metronome", qos: .userInteractive)

    // Audio state — accessed ONLY from audioQueue after init
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var clickBuffer: AVAudioPCMBuffer?
    private var accentBuffer: AVAudioPCMBuffer?
    private var currentVolume: Float = 0.5

    /// Host time ticks per second — used for converting seconds to mach_absolute_time units
    static let hostTicksPerSecond: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.denom) / Double(info.numer) * 1_000_000_000
    }()

    init() {
        // Setup synchronously so engine is ready before any playback calls
        audioQueue.sync {
            self.setupAudioEngine()
        }
    }

    deinit {
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

    /// Воспроизводит клик немедленно (schedules at current host time).
    func playClick(isAccent: Bool) {
        let hostTime = mach_absolute_time()
        scheduleClickAtHostTime(hostTime, isAccent: isAccent)
    }

    /// Планирует клик в точный момент host time для sample-accurate воспроизведения.
    /// Использует AVAudioPlayerNode.scheduleBuffer(at:) — аудио-железо воспроизведёт
    /// буфер точно в указанный момент, независимо от задержек в очередях.
    func scheduleClickAtHostTime(_ hostTime: UInt64, isAccent: Bool) {
        let vol = currentVolume
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            self.ensureEngineRunning()
            guard let node = self.playerNode else { return }
            let buffer = isAccent ? self.accentBuffer : self.clickBuffer
            guard let buffer = buffer else { return }

            node.volume = vol
            let audioTime = AVAudioTime(hostTime: hostTime)
            // No .interrupts — multiple beats can be queued without cancelling each other
            node.scheduleBuffer(buffer, at: audioTime, options: [], completionHandler: nil)
        }
    }

    /// Конвертирует задержку в секундах в абсолютное значение host time
    static func hostTime(afterDelay delay: Double) -> UInt64 {
        mach_absolute_time() + UInt64(delay * hostTicksPerSecond)
    }

    /// Отменяет все запланированные клики (при seek/stop)
    func cancelAllScheduled() {
        audioQueue.async { [weak self] in
            guard let self = self, let node = self.playerNode else { return }
            node.stop()
            node.play()
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
