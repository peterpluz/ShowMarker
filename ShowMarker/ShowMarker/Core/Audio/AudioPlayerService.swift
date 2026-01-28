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
        let newPlayer = AVPlayer(playerItem: item)

        // Disable automatic buffering wait to start playback immediately
        newPlayer.automaticallyWaitsToMinimizeStalling = false

        player = newPlayer

        Task {
            let d = try? await item.asset.load(.duration)
            duration = d?.seconds ?? 0

            // Preroll player for immediate playback when play() is called
            await prerollPlayer()
        }

        addTimeObserver()
    }

    /// Prerolls the player to minimize delay when play() is called
    private func prerollPlayer() async {
        guard let player else { return }

        do {
            let ready = try await player.preroll(atRate: 1.0)
            if ready {
                print("✅ Player prerolled and ready for immediate playback")
            }
        } catch {
            print("⚠️ Player preroll failed: \(error)")
        }
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

    /// Seek to absolute time position - more responsive for drag operations
    func seekTo(time: Double) {
        guard let player else { return }
        let target = max(0, min(time, duration))
        let cmTime = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        // Update currentTime immediately for responsive UI
        currentTime = target
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()

        do {
            // ✅ ИСПРАВЛЕНО: минимальная конфигурация без проблемных опций
            try session.setCategory(.playback, mode: .default)
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
