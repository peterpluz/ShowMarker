import Foundation
import AVFoundation
import Combine

@MainActor
final class AudioPlayerService: ObservableObject {

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    private var player: AVPlayer?
    private var timeObserver: Any?

    deinit {
        // Очистка происходит в stop()
    }

    // MARK: - Load

    func load(url: URL) {
        stop()
        configureAudioSession()

        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)

        Task {
            let d = try? await item.asset.load(.duration)
            duration = d?.seconds ?? 0
        }

        addTimeObserver()
    }

    // MARK: - Playback

    func play() {
        configureAudioSession()
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        cleanupObserver()

        player?.pause()
        player = nil

        currentTime = 0
        duration = 0
        isPlaying = false
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(by delta: Double) {
        guard let player else { return }
        let target = max(0, currentTime + delta)
        let cmTime = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()

        do {
            // ✅ ИСПРАВЛЕНО: убран .defaultToSpeaker для .playback
            // .defaultToSpeaker работает только с .playAndRecord
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetoothA2DP, .allowAirPlay]
            )
            try session.setActive(true)
        } catch {
            print("⚠️ AudioSession error:", error)
        }
    }

    // MARK: - Time observer

    private func addTimeObserver() {
        guard let player else { return }

        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = time.seconds
            }
        }
    }
    
    private func cleanupObserver() {
        if let player, let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }
    }
}
