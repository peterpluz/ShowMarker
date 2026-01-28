import Foundation
import AVFoundation
import Combine

/// Сервис метронома для воспроизведения кликов в такт
@MainActor
class MetronomeService: ObservableObject {

    @Published var isPlaying: Bool = false
    @Published var volume: Float = 0.5
    @Published var currentBeat: Int = 0  // 0-3 for 4/4 time

    private var timer: Timer?
    private var audioPlayers: [AVAudioPlayer] = []
    private var bpm: Double = 120

    // Звуки метронома (синтезированные)
    private var clickSound: AVAudioPlayer?
    private var accentSound: AVAudioPlayer?

    init() {
        setupAudioSounds()
    }

    private func setupAudioSounds() {
        // Создаём простые звуковые сигналы
        // Используем системные звуки или генерируем простые тоны
        do {
            // Простой тон для обычного клика
            if let clickData = generateClickSound(frequency: 1000, duration: 0.05) {
                clickSound = try AVAudioPlayer(data: clickData)
                clickSound?.prepareToPlay()
                clickSound?.volume = volume
            }

            // Более высокий тон для акцента (первый бит)
            if let accentData = generateClickSound(frequency: 1500, duration: 0.05) {
                accentSound = try AVAudioPlayer(data: accentData)
                accentSound?.prepareToPlay()
                accentSound?.volume = volume
            }
        } catch {
            print("⚠️ Failed to setup metronome sounds: \(error)")
        }
    }

    /// Генерирует простой звуковой клик
    private func generateClickSound(frequency: Float, duration: Double) -> Data? {
        let sampleRate: Double = 44100
        let amplitude: Float = 0.5
        let sampleCount = Int(sampleRate * duration)

        var samples: [Float] = []
        for i in 0..<sampleCount {
            let time = Double(i) / sampleRate
            let phase = 2.0 * Double.pi * Double(frequency) * time
            let sineValue = sin(phase)
            let value = amplitude * Float(sineValue)

            // Применяем envelope для сглаживания
            let envelopeValue = 1.0 - (Double(i) / Double(sampleCount))
            let envelope = Float(envelopeValue)
            samples.append(value * envelope)
        }

        // Конвертируем в Data
        let data = samples.withUnsafeBytes { Data($0) }
        return createWAVData(samples: samples, sampleRate: Int(sampleRate))
    }

    /// Создает WAV данные из массива сэмплов
    private func createWAVData(samples: [Float], sampleRate: Int) -> Data? {
        var data = Data()

        // WAV header
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * 2)  // 2 bytes per sample for 16-bit

        // RIFF header
        data.append("RIFF".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: (36 + dataSize).littleEndian) { Data($0) })
        data.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        data.append("fmt ".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })  // PCM
        data.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })

        // data chunk
        data.append("data".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })

        // Convert float samples to 16-bit PCM
        for sample in samples {
            let intSample = Int16(sample * Float(Int16.max))
            data.append(withUnsafeBytes(of: intSample.littleEndian) { Data($0) })
        }

        return data
    }

    /// Запускает метроном
    func start(bpm: Double) {
        stop()  // Останавливаем предыдущий, если был

        self.bpm = bpm
        self.isPlaying = true
        self.currentBeat = 0

        let interval = 60.0 / bpm  // Интервал между кликами в секундах

        // Первый клик сразу
        playClick()

        // Запускаем таймер
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.playClick()
        }

        print("🥁 Metronome started at \(bpm) BPM")
    }

    /// Останавливает метроном
    func stop() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
        currentBeat = 0
        print("🥁 Metronome stopped")
    }

    /// Переключает состояние метронома
    func toggle(bpm: Double?) {
        if isPlaying {
            stop()
        } else if let bpm = bpm {
            start(bpm: bpm)
        }
    }

    /// Воспроизводит клик
    private func playClick() {
        currentBeat = (currentBeat + 1) % 4

        // Первый бит каждого такта - акцент
        let player = (currentBeat == 1) ? accentSound : clickSound
        player?.volume = volume
        player?.currentTime = 0
        player?.play()
    }

    /// Обновляет громкость
    func setVolume(_ volume: Float) {
        self.volume = max(0, min(1, volume))
        clickSound?.volume = self.volume
        accentSound?.volume = self.volume
    }
}
