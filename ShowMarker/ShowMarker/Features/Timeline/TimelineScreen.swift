import SwiftUI
import AVFoundation

struct TimelineScreen: View {

    @Binding var document: ShowMarkerDocument
    let timelineID: UUID

    @StateObject private var player = AudioPlayer()
    @State private var isPickerPresented = false
    @State private var waveform: [Float] = []

    private var timelineIndex: Int? {
        document.file.project.timelines.firstIndex { $0.id == timelineID }
    }

    private var timeline: Timeline? {
        guard let index = timelineIndex else { return nil }
        return document.file.project.timelines[index]
    }

    var body: some View {
        VStack(spacing: 16) {

            WaveformView(samples: waveform)
                .overlay(playhead, alignment: .leading)

            if let audio = timeline?.audio {
                Text(audio.originalFileName)
                    .font(.callout)

                Text("Время: \(format(player.currentTime)) / \(format(player.duration))")
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
            Button {
                isPickerPresented = true
            } label: {
                Text(timeline?.audio == nil ? "Добавить аудиофайл" : "Заменить аудиофайл")
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
        .onDisappear {
            // ВАЖНО: через MainActor
            Task { @MainActor in
                player.stop()
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

    // MARK: - Audio import

    private func handleAudio(_ result: Result<[URL], Error>) {
        guard
            case .success(let urls) = result,
            let url = urls.first,
            let index = timelineIndex
        else { return }

        Task {
            let asset = AVURLAsset(url: url)
            let duration = try? await asset.load(.duration)

            do {
                let relativePath = try AudioStorage.copyToProject(from: url)

                document.file.project.timelines[index].audio = TimelineAudio(
                    relativePath: relativePath,
                    originalFileName: url.lastPathComponent,
                    duration: duration?.seconds ?? 0
                )
            } catch {
                print("Audio copy failed:", error)
            }
        }
    }

    private func loadAudioIfNeeded() {
        guard let audio = timeline?.audio else { return }
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
