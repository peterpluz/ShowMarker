import Foundation
import AVFoundation
import Combine

@MainActor
final class AudioPlayer: ObservableObject {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?

    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0

    private var displayLink: CADisplayLink?

    init() {
        setupAudioSession()

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)

        do {
            try engine.start()
        } catch {
            print("AudioEngine start failed:", error)
        }
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("AudioSession setup failed:", error)
        }
    }

    func load(url: URL) throws {
        audioFile = try AVAudioFile(forReading: url)

        duration =
            Double(audioFile?.length ?? 0) /
            (audioFile?.processingFormat.sampleRate ?? 1)

        currentTime = 0
    }

    func play() {
        guard let file = audioFile else { return }

        player.stop()
        player.scheduleFile(file, at: nil)
        player.play()

        isPlaying = true
        startTracking()
    }

    func pause() {
        player.pause()
        isPlaying = false
        stopTracking()
    }

    func stop() {
        player.stop()
        isPlaying = false
        currentTime = 0
        stopTracking()
    }

    private func startTracking() {
        stopTracking()
        displayLink = CADisplayLink(target: self, selector: #selector(updateTime))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopTracking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateTime() {
        guard
            let nodeTime = player.lastRenderTime,
            let time = player.playerTime(forNodeTime: nodeTime)
        else { return }

        currentTime = Double(time.sampleTime) / time.sampleRate

        if currentTime >= duration {
            stop()
        }
    }
}
