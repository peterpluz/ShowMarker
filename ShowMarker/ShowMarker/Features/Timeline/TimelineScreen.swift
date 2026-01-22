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

    // Marker creation popup state
    @State private var isMarkerNamePopupPresented = false
    @State private var markerCreationTime: Double = 0
    @State private var wasPlayingBeforePopup = false

    // Marker tag editing state
    @State private var editingTagMarker: TimelineMarker?

    // Tag filter state
    @State private var isTagFilterPresented = false

    // ✅ FIX: Force timeline redraw during List scroll
    @State private var timelineRedrawTrigger: Bool = false

    // Delete all markers confirmation
    @State private var showDeleteAllMarkersConfirmation = false

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
    
    // НОВОЕ: проверка наличия аудио
    private var hasAudio: Bool {
        viewModel.audio != nil
    }

    // Check if filter is active (not all tags selected)
    private var hasActiveFilter: Bool {
        !viewModel.selectedTagIds.isEmpty && viewModel.selectedTagIds.count < viewModel.tags.count
    }

    var body: some View {
        ZStack {
            mainContent
                .onChange(of: viewModel.currentTime) { oldValue, newValue in
                    // ✅ FIX: Toggle trigger on every currentTime update to force timeline redraw
                    timelineRedrawTrigger.toggle()
                }
                .sheet(item: $timePickerMarker) { marker in
                    timecodePickerSheet(for: marker)
                }
                .sheet(item: $editingTagMarker) { marker in
                    tagPickerSheet(for: marker)
                }
                .sheet(isPresented: $isTagFilterPresented) {
                    tagFilterSheet
                }

            // Marker name popup overlay
            if isMarkerNamePopupPresented {
                markerNamePopupOverlay
            }
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
            .alert("Удалить все маркеры?", isPresented: $showDeleteAllMarkersConfirmation) {
                Button("Удалить", role: .destructive) {
                    viewModel.deleteAllMarkers()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Вы уверены, что хотите удалить все маркеры этого таймлайна?")
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
        ScrollViewReader { proxy in
            List {
                Section {
                    ForEach(viewModel.visibleMarkers) { marker in
                        markerRow(marker)
                            .id(marker.id)  // ✅ Required for ScrollViewReader
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(viewModel.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { bottomPanel }
            .onChange(of: viewModel.nextMarkerID) { oldValue, nextID in
                // ✅ Auto-scroll to next marker if enabled
                guard viewModel.isAutoScrollEnabled, let nextID = nextID else { return }
                
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(nextID, anchor: .center)
                }
            }
        }
    }

    // MARK: - Marker Row

    private func markerRow(_ marker: TimelineMarker) -> some View {
        MarkerCard(
            marker: marker,
            tag: viewModel.tags.first(where: { $0.id == marker.tagId }),
            fps: viewModel.fps,
            markerFlashPublisher: viewModel.markerFlashPublisher,
            draggedMarkerID: viewModel.draggedMarkerID,
            draggedMarkerPreviewTime: viewModel.draggedMarkerPreviewTime,
            onTagEdit: {
                editingTagMarker = marker
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // ИСПРАВЛЕНО: seek только если есть аудио
            guard hasAudio else { return }
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

        Button {
            editingTagMarker = marker
        } label: {
            Label("Изменить тег", systemImage: "tag")
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

    private func tagPickerSheet(for marker: TimelineMarker) -> some View {
        TagPickerView(
            tags: viewModel.tags,
            selectedTagId: marker.tagId,
            onSelect: { newTagId in
                viewModel.changeMarkerTag(marker, to: newTagId)
                editingTagMarker = nil
            },
            onCancel: {
                editingTagMarker = nil
            }
        )
    }

    private var tagFilterSheet: some View {
        TagFilterView(
            tags: viewModel.tags,
            selectedTagIds: $viewModel.selectedTagIds,
            onClose: {
                isTagFilterPresented = false
            }
        )
        .presentationDetents([.medium])
    }

    private var markerNamePopupOverlay: some View {
        MarkerNamePopup(
            defaultName: "Маркер \(viewModel.markers.count + 1)",
            tags: viewModel.tags,
            defaultTagId: viewModel.defaultTag?.id ?? UUID(),
            onSave: { markerName, tagId in
                viewModel.addMarker(name: markerName, tagId: tagId, at: markerCreationTime)
                isMarkerNamePopupPresented = false
                resumePlaybackIfNeeded()
            },
            onCancel: {
                isMarkerNamePopupPresented = false
                resumePlaybackIfNeeded()
            }
        )
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isMarkerNamePopupPresented)
    }

    private func resumePlaybackIfNeeded() {
        // Always resume playback after popup closes if it was playing before
        if wasPlayingBeforePopup {
            viewModel.resumePlayback()
            wasPlayingBeforePopup = false
        }
    }

    private var renameMarkerBinding: Binding<Bool> {
        Binding(
            get: { renamingMarker != nil },
            set: { if !$0 { renamingMarker = nil } }
        )
    }

    // MARK: - Toolbar

    private var toolbarContent: some ToolbarContent {
        Group {
            // Undo button (leading)
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    viewModel.undoManager.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 20, weight: .semibold))
                }
                .disabled(!viewModel.undoManager.canUndo)
            }

            // Redo button (leading)
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    viewModel.undoManager.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 20, weight: .semibold))
                }
                .disabled(!viewModel.undoManager.canRedo)
            }

            // Tag filter button
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isTagFilterPresented = true
                } label: {
                    Image(systemName: hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 20, weight: .semibold))
                }
            }

            // Settings menu
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // ✅ Auto-scroll toggle (moved to menu)
                    Toggle(isOn: $viewModel.isAutoScrollEnabled) {
                        Label("Автоскролл маркеров", systemImage: "arrow.down.circle")
                    }

                    // Pause on marker creation toggle
                    Toggle(isOn: $viewModel.shouldPauseOnMarkerCreation) {
                        Label("Останавливать воспроизведение", systemImage: "pause.circle")
                    }

                    // Show marker popup toggle
                    Toggle(isOn: $viewModel.shouldShowMarkerPopup) {
                        Label("Показывать окно создания маркера", systemImage: "square.and.pencil")
                    }

                    Divider()
                
                // ИСПРАВЛЕНО: показываем опции аудио только если оно есть
                if hasAudio {
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
                }

                Button {
                    renameText = viewModel.name
                    isRenamingTimeline = true
                } label: {
                    Label("Переименовать таймлайн", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    showDeleteAllMarkersConfirmation = true
                } label: {
                    Label("Удалить все маркеры", systemImage: "trash.fill")
                }
                .disabled(viewModel.markers.isEmpty)

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
    }

    // MARK: - Bottom Panel

    private var bottomPanel: some View {
        VStack(spacing: 16) {
            timelineBar

            // ИСПРАВЛЕНО: тайм и контролы видимы только с аудио
            if hasAudio {
                timecode
                playbackControls
            }

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
            tags: viewModel.tags,
            hasAudio: hasAudio,
            onAddAudio: { isPickerPresented = true },
            onSeek: { viewModel.seek(to: $0) },
            onPreviewMoveMarker: { _, _ in },
            onCommitMoveMarker: { id, time in
                if let marker = viewModel.markers.first(where: { $0.id == id }) {
                    viewModel.moveMarker(marker, to: time)
                }
            },
            zoomScale: $viewModel.zoomScale,
            draggedMarkerID: $viewModel.draggedMarkerID,
            draggedMarkerPreviewTime: $viewModel.draggedMarkerPreviewTime
        )
        .opacity(timelineRedrawTrigger ? 0.9999 : 1.0)  // ✅ FIX: Force redraw on trigger toggle
    }

    private var timecode: some View {
        Text(viewModel.timecode())
            .font(.system(size: 32, weight: .bold))
            .opacity(timelineRedrawTrigger ? 0.9999 : 1.0)  // ✅ FIX: Force redraw on trigger toggle
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
            // Save current time for marker creation
            markerCreationTime = viewModel.currentTime

            if viewModel.shouldShowMarkerPopup {
                // Save playback state and pause if needed
                wasPlayingBeforePopup = viewModel.isPlaying
                if viewModel.shouldPauseOnMarkerCreation && wasPlayingBeforePopup {
                    viewModel.pausePlayback()
                }

                // Show marker name popup
                isMarkerNamePopupPresented = true
            } else {
                // Create marker directly with default values
                let markerNumber = viewModel.markers.count + 1
                let defaultName = "Marker \(markerNumber)"
                let defaultTag = viewModel.defaultTag ?? viewModel.tags.first!

                viewModel.addMarker(
                    name: defaultName,
                    tagId: defaultTag.id,
                    at: markerCreationTime
                )
            }
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
        .disabled(!hasAudio)
        .opacity(hasAudio ? 1 : 0.4)
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

        guard url.startAccessingSecurityScopedResource() else {
            print("❌ Failed to access security scoped resource")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            print("✅ Audio data loaded: \(data.count) bytes")

            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension)

            try data.write(to: tmpURL, options: .atomic)
            print("✅ Wrote to temp: \(tmpURL)")

            let vm = viewModel

            Task { @MainActor in
                do {
                    let asset = AVURLAsset(url: tmpURL)
                    let d = try await asset.load(.duration)
                    print("✅ Audio duration: \(d.seconds)s")

                    try vm.addAudio(
                        sourceData: data,
                        originalFileName: url.lastPathComponent,
                        fileExtension: url.pathExtension,
                        duration: d.seconds
                    )
                    print("✅ Audio added successfully")

                    try? FileManager.default.removeItem(at: tmpURL)
                } catch {
                    print("❌ Audio import error: \(error)")
                }
            }
        } catch {
            print("❌ Audio file reading error: \(error)")
        }
    }
}
