import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct TimelineScreen: View {

    @StateObject private var viewModel: TimelineViewModel

    @State private var isPickerPresented = false
    @State private var isRenamingTimeline = false
    @State private var renameText = ""

    @State private var renamingMarker: TimelineMarker?
    @State private var timePickerMarker: TimelineMarker?

    @State private var exportData: Data?
    @State private var isExportPresented = false

    private static func makeViewModel(
        repository: ProjectRepository,
        timelineID: UUID
    ) -> TimelineViewModel {
        TimelineViewModel(repository: repository, timelineID: timelineID)
    }

    init(
        repository: ProjectRepository,
        timelineID: UUID
    ) {
        _viewModel = StateObject(
            wrappedValue: Self.makeViewModel(repository: repository, timelineID: timelineID)
        )
    }

    var body: some View {
        mainContent
            .sheet(item: $timePickerMarker) { marker in
                timecodePickerSheet(for: marker)
            }
            .alert("Переименовать таймлайн", isPresented: $isRenamingTimeline) {
                TextField("Название", text: $renameText)
                Button("Готово") {
                    viewModel.renameTimeline(to: renameText)
                }
                Button("Отмена", role: .cancel) {}
            }
            .alert("Переименовать маркер", isPresented: renameMarkerBinding) {
                TextField(
                    "Название",
                    text: Binding(
                        get: { renamingMarker?.name ?? "" },
                        set: { renamingMarker?.name = $0 }
                    )
                )
                Button("Готово") {
                    if let marker = renamingMarker {
                        viewModel.renameMarker(marker, to: marker.name)
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
                document: SimpleCSVDocument(data: exportData ?? Data()),
                contentType: .commaSeparatedText,
                defaultFilename: "\(viewModel.name)_Markers",
                onCompletion: { _ in }
            )
    }

    // MARK: - Main Content

    private var mainContent: some View {
        List {
            Section {
                ForEach(viewModel.markers) { marker in
                    markerRow(marker)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(viewModel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) { bottomPanel }
    }

    // MARK: - Marker Row

    private func markerRow(_ marker: TimelineMarker) -> some View {
        MarkerCard(marker: marker, fps: viewModel.fps)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.seek(to: marker.timeSeconds)
            }
            .contextMenu {
                markerContextMenu(for: marker)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                markerSwipeActions(for: marker)
            }
    }

    @ViewBuilder
    private func markerContextMenu(for marker: TimelineMarker) -> some View {
        Button {
            renamingMarker = marker
        } label: {
            Label("Переименовать", systemImage: "pencil")
        }

        Button {
            timePickerMarker = marker
        } label: {
            Label("Изменить время маркера", systemImage: "clock")
        }

        Divider()

        Button(role: .destructive) {
            viewModel.deleteMarker(marker)
        } label: {
            Label("Удалить", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func markerSwipeActions(for marker: TimelineMarker) -> some View {
        Button(role: .destructive) {
            viewModel.deleteMarker(marker)
        } label: {
            Label("Удалить", systemImage: "trash")
        }

        Button {
            renamingMarker = marker
        } label: {
            Label("Переименовать", systemImage: "pencil")
        }
        .tint(.blue)
    }

    // MARK: - Sheets

    private func timecodePickerSheet(for marker: TimelineMarker) -> some View {
        TimecodePickerView(
            seconds: marker.timeSeconds,
            fps: viewModel.fps,
            onCancel: { timePickerMarker = nil },
            onDone: { newSeconds in
                viewModel.moveMarker(marker, to: newSeconds)
                timePickerMarker = nil
            }
        )
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }

    private var renameMarkerBinding: Binding<Bool> {
        Binding(
            get: { renamingMarker != nil },
            set: { if !$0 { renamingMarker = nil } }
        )
    }

    // MARK: - Toolbar

    private var toolbarContent: some ToolbarContent {
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
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
            }
        }
    }

    // MARK: - Bottom Panel

    private var bottomPanel: some View {
        VStack(spacing: 16) {
            timelineBar
            timecode
            playbackControls
            addMarkerButton
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
        )
    }

    private var timelineBar: some View {
        TimelineBarView(
            duration: viewModel.duration,
            currentTime: viewModel.currentTime,
            waveform: viewModel.visibleWaveform,
            markers: viewModel.visibleMarkers,
            hasAudio: viewModel.audio != nil,
            onAddAudio: { isPickerPresented = true },
            onSeek: { viewModel.seek(to: $0) },
            onPreviewMoveMarker: { _, _ in
                // Preview теперь внутри TimelineBarView
            },
            onCommitMoveMarker: { id, time in
                if let marker = viewModel.markers.first(where: { $0.id == id }) {
                    viewModel.moveMarker(marker, to: time)
                }
            }
        )
    }

    private var timecode: some View {
        Text(viewModel.timecode())
            .font(.system(size: 32, weight: .bold))
    }

    private var playbackControls: some View {
        HStack(spacing: 40) {
            Button { viewModel.seekBackward() } label: {
                Image(systemName: "gobackward.5")
                    .font(.system(size: 22))
            }

            Button { viewModel.togglePlayPause() } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28))
            }

            Button { viewModel.seekForward() } label: {
                Image(systemName: "goforward.5")
                    .font(.system(size: 22))
            }
        }
        .foregroundColor(.primary)
    }

    private var addMarkerButton: some View {
        Button {
            viewModel.addMarkerAtCurrentTime()
        } label: {
            Text("ДОБАВИТЬ МАРКЕР")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Capsule().fill(Color.accentColor)
                )
        }
        .disabled(viewModel.audio == nil)
        .opacity(viewModel.audio == nil ? 0.4 : 1)
    }

    // MARK: - Helpers

    private func prepareExport() {
        let csv = MarkersCSVExporter.export(markers: viewModel.markers)
        exportData = csv.data(using: .utf8)
        isExportPresented = true
    }

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

            let vm = viewModel

            Task { @MainActor in
                let asset = AVURLAsset(url: tmpURL)
                let d = try? await asset.load(.duration)

                try? vm.addAudio(
                    sourceData: data,
                    originalFileName: url.lastPathComponent,
                    fileExtension: url.pathExtension,
                    duration: d?.seconds ?? 0
                )

                try? FileManager.default.removeItem(at: tmpURL)
            }
        } catch {
            print("Audio import failed:", error)
        }
    }
}

// MARK: - CSV Document

private struct SimpleCSVDocument: FileDocument {
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
