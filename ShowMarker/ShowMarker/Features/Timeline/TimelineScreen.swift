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
        VStack(spacing: 0) {

            // MARK: - MARKER LIST (TOP)
            ScrollView {
                LazyVStack(spacing: 0) {   // ⬅️ НЕТ расстояния между карточками
                    ForEach(viewModel.markers) { marker in
                        Button {
                            viewModel.seek(to: marker.timeSeconds)
                        } label: {
                            MarkerCard(marker: marker, fps: viewModel.fps)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)
        }
        .navigationTitle(viewModel.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {

            // MARK: - TIMELINE PANEL (BOTTOM)
            VStack(spacing: 18) {

                TimelineBarView(
                    duration: viewModel.duration,
                    currentTime: viewModel.currentTime,
                    waveform: viewModel.waveform,
                    markers: viewModel.markers,
                    onSeek: { viewModel.seek(to: $0) }
                )
                .frame(height: 180)

                Text(viewModel.timecode())
                    .font(.system(size: 30, weight: .bold))

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

                Button {
                    viewModel.addMarkerAtCurrentTime()
                } label: {
                    Label("Добавить маркер", systemImage: "bookmark.fill")
                }
                .buttonStyle(.bordered)

                Button(viewModel.audio == nil ? "Добавить аудиофайл" : "Заменить аудиофайл") {
                    isPickerPresented = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
            )
        }
        .fileImporter(
            isPresented: $isPickerPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false,
            onCompletion: handleAudio
        )
        .onDisappear {
            viewModel.onDisappear()
        }
    }

    // MARK: - Audio import

    private func handleAudio(_ result: Result<[URL], Error>) {
        guard
            case .success(let urls) = result,
            let url = urls.first
        else { return }

        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)

            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension)

            try data.write(to: tmpURL, options: .atomic)

            Task { @MainActor in
                let asset = AVURLAsset(url: tmpURL)
                let d = try? await asset.load(.duration)
                let durationSeconds = d?.seconds ?? 0

                try? viewModel.addAudio(
                    sourceData: data,
                    originalFileName: url.lastPathComponent,
                    fileExtension: url.pathExtension,
                    duration: durationSeconds
                )

                try? FileManager.default.removeItem(at: tmpURL)
            }
        } catch {
            print("Audio import failed:", error)
        }
    }
}
