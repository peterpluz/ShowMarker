import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct TimelineScreen: View {

    @StateObject private var viewModel: TimelineViewModel
    @State private var isPickerPresented = false

    @State private var isRenamingTimeline = false
    @State private var renameText: String = ""

    @State private var renamingMarker: TimelineMarker?
    @State private var renameMarkerText: String = ""

    @State private var exportData: Data?
    @State private var isExportPresented = false

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

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.markers) { marker in
                        Button {
                            viewModel.seek(to: marker.timeSeconds)
                        } label: {
                            MarkerCard(marker: marker, fps: viewModel.fps)
                        }
                        .contextMenu {
                            Button {
                                renamingMarker = marker
                                renameMarkerText = marker.name
                            } label: {
                                Label("Переименовать", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                viewModel.deleteMarker(marker)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding()
            }

            Spacer(minLength: 0)
        }
        .navigationTitle(viewModel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {

                    Button {
                        isPickerPresented = true
                    } label: {
                        Label("Заменить аудиофайл", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Button(role: .destructive) {
                        viewModel.removeAudio()
                    } label: {
                        Label("Удалить аудиофайл", systemImage: "trash")
                    }

                    Divider()

                    Button {
                        renameText = viewModel.name
                        isRenamingTimeline = true
                    } label: {
                        Label("Переименовать таймлайн", systemImage: "pencil")
                    }

                    Divider()

                    Button {
                        prepareExport()
                    } label: {
                        Label("Export markers (Reaper CSV)", systemImage: "square.and.arrow.down")
                    }
                    .disabled(viewModel.markers.isEmpty)

                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 18) {

                TimelineBarView(
                    duration: viewModel.duration,
                    currentTime: viewModel.currentTime,
                    waveform: viewModel.waveform,
                    markers: viewModel.markers,
                    hasAudio: viewModel.audio != nil,
                    onAddAudio: { isPickerPresented = true },
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
                .disabled(viewModel.audio == nil)
                .opacity(viewModel.audio == nil ? 0.4 : 1)

                Button {
                    viewModel.addMarkerAtCurrentTime()
                } label: {
                    Label("Добавить маркер", systemImage: "bookmark.fill")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.audio == nil)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
            )
        }
        .alert("Переименовать таймлайн", isPresented: $isRenamingTimeline) {
            TextField("Название", text: $renameText)
            Button("Готово") { viewModel.renameTimeline(to: renameText) }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Переименовать маркер", isPresented: .constant(renamingMarker != nil)) {
            TextField("Название", text: $renameMarkerText)
            Button("Готово") {
                if let marker = renamingMarker {
                    viewModel.renameMarker(marker, to: renameMarkerText)
                }
                renamingMarker = nil
            }
            Button("Отмена", role: .cancel) {
                renamingMarker = nil
            }
        }
        .fileImporter(
            isPresented: $isPickerPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false,
            onCompletion: handleAudio
        )
        .fileExporter(
            isPresented: $isExportPresented,
            document: CSVDocument(data: exportData ?? Data()),
            contentType: .commaSeparatedText,
            defaultFilename: "\(viewModel.name)_Markers"
        ) { _ in }
        .onDisappear {
            viewModel.onDisappear()
        }
    }

    // MARK: - Export

    private func prepareExport() {
        let csv = MarkersCSVExporter.export(markers: viewModel.markers)
        exportData = csv.data(using: .utf8)
        isExportPresented = true
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

// MARK: - CSV FileDocument

struct CSVDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
