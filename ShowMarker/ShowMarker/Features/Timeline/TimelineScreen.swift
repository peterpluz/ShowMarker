import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct TimelineScreen: View {

    @StateObject private var viewModel: TimelineViewModel
    @State private var isPickerPresented = false
    @Environment(\.colorScheme) private var colorScheme

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
        GeometryReader { geo in
            VStack {
                Spacer()
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 18) {

                    TimelineBarView(
                        duration: viewModel.duration,
                        currentTime: viewModel.currentTime,
                        waveform: viewModel.waveform,
                        onSeek: { viewModel.seek(to: $0) }
                    )
                    .frame(height: geo.size.height * 0.33)

                    // TIME CODE
                    Text(viewModel.timecode())
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.primary)

                    // CONTROLS
                    HStack(spacing: 44) {

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
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.regularMaterial)
                )
            }
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
            .tint(.accentColor)
            .padding()
        }
        .fileImporter(
            isPresented: $isPickerPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false,
            onCompletion: handleAudio
        )
    }

    private func handleAudio(_ result: Result<[URL], Error>) {
        guard
            case .success(let urls) = result,
            let url = urls.first
        else { return }

        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        Task {
            let asset = AVURLAsset(url: url)
            let duration = try? await asset.load(.duration)

            try? viewModel.addAudio(
                sourceURL: url,
                duration: duration?.seconds ?? 0
            )
        }
    }
}
