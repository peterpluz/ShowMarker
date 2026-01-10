import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct TimelineScreen: View {

    @StateObject private var viewModel: TimelineViewModel
    @State private var isPickerPresented = false

    init(
        document: Binding<ShowMarkerDocument>,
        timelineID: UUID
    ) {
        _viewModel = StateObject(
            wrappedValue: TimelineViewModel(
                document: document,
                timelineID: timelineID
            )
        )
    }

    var body: some View {
        VStack(spacing: 24) {

            TimelineBarView(
                duration: viewModel.duration,
                currentTime: viewModel.currentTime,
                waveform: viewModel.waveform,
                onSeek: { seconds in
                    viewModel.seek(to: seconds)
                }
            )

            Text(viewModel.timecode())
                .font(.system(.title2, design: .monospaced))

            HStack(spacing: 32) {
                Button { viewModel.seekBackward() } label: {
                    Image(systemName: "gobackward.5")
                }

                Button { viewModel.togglePlayPause() } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                }

                Button { viewModel.seekForward() } label: {
                    Image(systemName: "goforward.5")
                }
            }
            .font(.title2)

            Spacer()
        }
        .navigationTitle(viewModel.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            viewModel.onDisappear()
        }
        .safeAreaInset(edge: .bottom) {
            Button(viewModel.audio == nil ? "Добавить аудиофайл" : "Заменить аудиофайл") {
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
    }

    // MARK: - Audio import (Swift 6 safe)

    private func handleAudio(_ result: Result<[URL], Error>) {
        guard
            case .success(let urls) = result,
            let pickedURL = urls.first
        else { return }

        guard pickedURL.startAccessingSecurityScopedResource() else {
            return
        }

        defer {
            pickedURL.stopAccessingSecurityScopedResource()
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(pickedURL.lastPathComponent)

        do {
            let data = try Data(contentsOf: pickedURL)
            try data.write(to: tempURL, options: .atomic)

            let asset = AVURLAsset(url: tempURL)
            let duration = asset.duration.seconds   // ✅ синхронно

            try viewModel.addAudio(
                sourceURL: tempURL,
                duration: duration
            )
        } catch {
            print("Audio import failed:", error)
        }
    }
}
