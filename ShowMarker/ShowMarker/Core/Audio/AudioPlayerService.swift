import Foundation
import AVFoundation
import Combine

@MainActor
final class AudioPlayerService: ObservableObject {

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    /// Host time and audio time captured simultaneously in the time observer callback.
    /// Used by beat scheduler for precise host-time-anchored calculations.
    private(set) var lastTimeObserverHostTime: UInt64 = 0
    private(set) var lastTimeObserverAudioTime: Double = 0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    /// Serial queue for time observer - more responsive than main queue
    private let timeObserverQueue = DispatchQueue(label: "com.showmarker.timeObserver", qos: .userInteractive)

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
        addEndObserver(item: item)
    }

    /// Prerolls the player to minimize delay when play() is called
    private func prerollPlayer() async {
        guard let player else { return }

        let ready = await player.preroll(atRate: 1.0)
        if ready {
            print("✅ Player prerolled and ready for immediate playback")
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

    /// Mutes/unmutes the audio player without affecting playback state
    func setMuted(_ muted: Bool) {
        player?.isMuted = muted
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
            // Use playback category with low-latency options
            try session.setCategory(.playback, mode: .default, options: [])

            // Request lower I/O buffer duration for reduced latency
            // 0.005 = 5ms buffer (minimum supported on most devices)
            try session.setPreferredIOBufferDuration(0.005)

            try session.setActive(true)

            let actualBuffer = session.ioBufferDuration
            print("✅ AudioSession configured: buffer=\(String(format: "%.1f", actualBuffer * 1000))ms")
        } catch {
            print("⚠️ AudioSession error:", error)
        }
    }

    // MARK: - Time observer

    private func addTimeObserver() {
        guard let player else { return }

        // Higher frequency updates (60fps) for more accurate beat detection
        let interval = CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: timeObserverQueue  // Use dedicated queue for responsiveness
        ) { [weak self] time in
            guard let self else { return }
            // Capture host time simultaneously with audio time —
            // this pair serves as a reference point for sample-accurate beat scheduling
            let hostTime = mach_absolute_time()
            let seconds = time.seconds
            // Dispatch to main for @Published property
            DispatchQueue.main.async {
                self.lastTimeObserverHostTime = hostTime
                self.lastTimeObserverAudioTime = seconds
                self.currentTime = seconds
            }
        }
    }

    private func addEndObserver(item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isPlaying = false
            }
        }
    }

    private func cleanupObserver() {
        if let player, let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
    }
}
