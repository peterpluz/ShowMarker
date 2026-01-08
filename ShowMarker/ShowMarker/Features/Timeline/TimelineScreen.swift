import SwiftUI
import AVFoundation

struct TimelineScreen: View {

    @Binding var document: ShowMarkerDocument
    let timelineID: UUID

    @StateObject private var player = AudioPlayer()
    @State private var isPickerPresented = false
    @State private var waveform: [Float] = []

    private var timeline: Timeline? {
        document.file.project.timelines.first { $0.id == timelineID }
    }

    var body: some View {
        VStack(spacing: 16) {

            WaveformView(samples: waveform)
                .overlay(playhead, alignment: .leading)

            if let audio = timeline?.audio {
                Text(audio.originalFileName)
                    .font(.callout)

                Text(
                    "Время: \(format(player.currentTime)) / \(format(player.duration))"
                )
                .foregroundColor(.secondary)

                Button(player.isPlaying ? "Pause" : "Play") {
                    player.isPlaying ? player.pause() : player.play()
                }
            } else {
                emptyState
            }
        }
        .padding()
        .navigationTitle(timeline?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(timeline?.audio == nil ? "Добавить аудиофайл" : "Заменить аудиофайл") {
                isPickerPresented = true
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .fileImporter(
            isPresented: $isPickerPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false,
            onCompletion: handleAudio
        )
        .task {
            await loadWaveform()
            loadAudioIfNeeded()
        }
        .onChange(of: timeline?.audio?.relativePath) {
            Task {
                await loadWaveform()
                loadAudioIfNeeded()
            }
        }
    }

    // MARK: - Playhead

    private var playhead: some View {
        GeometryReader { geo in
            let progress = player.duration > 0
                ? player.currentTime / player.duration
                : 0

            Rectangle()
                .fill(Color.red)
                .frame(width: 2)
                .offset(x: geo.size.width * CGFloat(progress))
        }
    }

    // MARK: - Audio

    private func handleAudio(_ result: Result<[URL], Error>) {
        guard
            case .success(let urls) = result,
            let url = urls.first
        else { return }

        Task {
            let asset = AVURLAsset(url: url)
            let duration = try? await asset.load(.duration)

            do {
                try document.addAudio(
                    to: timelineID,
                    sourceURL: url,
                    duration: duration?.seconds ?? 0
                )
            } catch {
                print("Audio copy failed:", error)
            }
        }
    }

    private func loadAudioIfNeeded() {
        guard
            let audio = timeline?.audio
        else { return }

        let url = AudioStorage.url(for: audio.relativePath)
        try? player.load(url: url)
    }

    // MARK: - Waveform

    private func loadWaveform() async {
        guard let audio = timeline?.audio else {
            waveform = []
            return
        }

        let url = AudioStorage.url(for: audio.relativePath)
        waveform = (try? await WaveformLoader.loadSamples(from: url)) ?? []
    }

    // MARK: - UI

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Нет аудиофайла")
                .foregroundColor(.secondary)
            Text("Добавьте аудио для работы с таймлайном")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func format(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
