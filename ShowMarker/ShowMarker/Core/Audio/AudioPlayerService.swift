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
        if let player, let obs = timeObserver {
            player.removeTimeObserver(obs)
        }

        player?.pause()
        player = nil
        timeObserver = nil

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
            try session.setCategory(
                .playback,
                mode: .default,
                options: [
                    .defaultToSpeaker,
                    .allowBluetoothHFP,
                    .allowAirPlay
                ]
            )
            try session.setActive(true)
        } catch {
            print("AudioSession error:", error)
        }
    }

    // MARK: - Time observer (ИСПРАВЛЕНО)

    private func addTimeObserver() {
        guard let player else { return }

        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)

        // ИСПРАВЛЕНИЕ: правильная работа с MainActor
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
}
