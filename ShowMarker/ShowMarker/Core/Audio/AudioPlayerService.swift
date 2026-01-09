import Foundation
import AVFoundation
import Combine
import QuartzCore

@MainActor
final class AudioPlayerService: ObservableObject {

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    private var player: AVPlayer?
    private var timeObserver: Any?

    // MARK: - Load

    /// Загружает аудио по URL (локальный файл URL).
    func load(url: URL) {
        cleanup()

        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)

        // duration может быть неопределённым до загрузки asset; при необходимости можно слушать статус
        let seconds = item.asset.duration.seconds
        duration = seconds.isFinite ? seconds : 0

        addTimeObserver()
    }

    // MARK: - Playback

    func play() {
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
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

    // MARK: - Time observer (MainActor-safe)

    private func addTimeObserver() {
        guard let player else { return }

        // 30 FPS interval
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)

        // remove previous if present
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }

        // The closure provided to AVPlayer is @Sendable; it must not directly mutate MainActor-isolated properties.
        // Therefore, update MainActor state inside Task { @MainActor in ... }.
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            Task { @MainActor in
                self.currentTime = time.seconds
            }
        }
    }

    // MARK: - Cleanup

    private func cleanup() {
        if let player = player, let obs = timeObserver {
            player.removeTimeObserver(obs)
        }
        timeObserver = nil
        player = nil
        currentTime = 0
        duration = 0
        isPlaying = false
    }
}
