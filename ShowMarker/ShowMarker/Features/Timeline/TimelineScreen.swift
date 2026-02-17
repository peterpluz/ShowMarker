import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Player Sheet Detent

enum PlayerSheetDetent: Equatable {
    case compact
    case medium
    case expanded
}

struct TimelineScreen: View {

    @StateObject private var viewModel: TimelineViewModel

    @State private var isPickerPresented = false
    @State private var isRenamingTimeline = false
    @State private var renameText = ""

    @State private var renamingMarker: TimelineMarker?
    @State private var renamingMarkerOldName: String = ""
    @State private var timePickerMarker: TimelineMarker?

    @State private var exportData: Data?
    @State private var isExportPresented = false

    // CSV import state
    @State private var isCSVImportPresented = false
    @State private var csvImportError: String?
    @State private var showCSVImportError = false

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

    // History menu states
    @State private var showUndoHistory = false
    @State private var showRedoHistory = false

    // Play button animation states
    @State private var playButtonScale: CGFloat = 1.0
    @State private var rippleRadius: CGFloat = 0
    @State private var rippleOpacity: Double = 1.0

    // Timeline settings sheet state
    @State private var isTimelineSettingsPresented = false

    // Player sheet state
    @State private var sheetDetent: PlayerSheetDetent = .medium
    @State private var sheetDragOffset: CGFloat = 0
    @State private var currentSheetHeight: CGFloat = 500  // Absolute height tracking (medium = 500)
    @State private var dragStartHeight: CGFloat?  // Initial height when drag starts (nil = not dragging)

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
            if viewModel.isLoading {
                // Loading screen while timeline data is being prepared
                loadingView
            } else {
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
                    .sheet(isPresented: $isTimelineSettingsPresented) {
                        TimelineSettingsSheet(
                            viewModel: viewModel,
                            onReplaceAudio: {
                                isTimelineSettingsPresented = false
                                isPickerPresented = true
                            },
                            onDeleteAudio: {
                                isTimelineSettingsPresented = false
                                viewModel.removeAudio()
                            },
                            onDeleteAllMarkers: {
                                isTimelineSettingsPresented = false
                                showDeleteAllMarkersConfirmation = true
                            }
                        )
                    }

                // Marker name popup overlay
                if isMarkerNamePopupPresented {
                    markerNamePopupOverlay
                }
            }
        }
        .sheet(isPresented: $isPickerPresented) {
            AudioDocumentPicker(
                onPick: { url in
                    print("🎵 [AudioPicker] File picked: \(url)")
                    isPickerPresented = false
                    handleAudioURL(url)
                },
                onCancel: {
                    print("🎵 [AudioPicker] Cancelled")
                    isPickerPresented = false
                }
            )
        }
        .onChange(of: isPickerPresented) { oldValue, newValue in
            print("🎵 [AudioPicker] isPickerPresented changed: \(oldValue) -> \(newValue)")
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
                        viewModel.renameMarker(marker, to: marker.name, oldName: renamingMarkerOldName)
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
            .fileExporter(
                isPresented: $isExportPresented,
                document: SimpleCSVDocument(data: exportData ?? Data()),
                contentType: .commaSeparatedText,
                defaultFilename: "\(viewModel.name)_Markers",
                onCompletion: { _ in }
            )
            .fileImporter(
                isPresented: $isCSVImportPresented,
                allowedContentTypes: [.commaSeparatedText],
                allowsMultipleSelection: false,
                onCompletion: handleCSVImport
            )
            .alert("Ошибка импорта", isPresented: $showCSVImportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(csvImportError ?? "Неизвестная ошибка")
            }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Загрузка...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
        .navigationTitle(viewModel.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            if isLandscape {
                landscapeContent(geometry: geometry)
            } else {
                portraitContent(geometry: geometry)
            }
        }
        .navigationTitle(viewModel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbarContent
        }
    }

    // MARK: - Portrait Layout

    private func portraitContent(geometry: GeometryProxy) -> some View {
        let screenHeight = geometry.size.height
        let stableInsetHeight = sheetHeight(for: sheetDetent, screenHeight: screenHeight)

        return ZStack(alignment: .bottom) {
            markerListView(bottomInset: stableInsetHeight + 8)

            // Dimming overlay — fades in continuously as sheet approaches expanded height
            let dimmingOpacity = dimmingOverlayOpacity(screenHeight: screenHeight)
            if dimmingOpacity > 0.001 {
                Color.black
                    .opacity(dimmingOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Player sheet
            playerSheet(screenHeight: screenHeight)
        }
    }

    // MARK: - Landscape Layout

    private func landscapeContent(geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // Left 1/3 — marker list
            markerListView(bottomInset: 8)
                .frame(width: geometry.size.width / 3)

            Divider()

            // Right 2/3 — full player with timeline + keyframes
            fullPlayerContent(isLandscape: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }

    // MARK: - Shared Marker List

    private func markerListView(bottomInset: CGFloat) -> some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    ForEach(Array(viewModel.visibleMarkers.enumerated()), id: \.element.id) { index, marker in
                        markerRow(marker, index: index + 1)
                            .id(marker.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                removal: .opacity
                            ))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .animation(.easeInOut(duration: 0.3), value: viewModel.visibleMarkers.map(\.id))
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: bottomInset)
            }
            .onChange(of: viewModel.nextMarkerID) { oldValue, nextID in
                guard viewModel.isAutoScrollEnabled, let nextID = nextID else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(nextID, anchor: .center)
                }
            }
        }
    }

    // MARK: - Marker Row

    private func markerRow(_ marker: TimelineMarker, index: Int = 1) -> some View {
        MarkerCard(
            marker: marker,
            tag: viewModel.tags.first(where: { $0.id == marker.tagId }),
            fps: viewModel.fps,
            markerFlashPublisher: viewModel.markerFlashPublisher,
            draggedMarkerID: viewModel.draggedMarkerID,
            draggedMarkerPreviewTime: viewModel.draggedMarkerPreviewTime,
            currentTime: viewModel.currentTime,
            markerIndex: index,
            isHapticFeedbackEnabled: viewModel.isMarkerHapticFeedbackEnabled,
            prerollSeconds: viewModel.prerollSeconds,
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
            Button(role: .destructive) {
                viewModel.deleteMarker(marker)
            } label: {
                Label("Удалить", systemImage: "trash")
            }

            Button {
                renamingMarker = marker
                renamingMarkerOldName = marker.name
            } label: {
                Label("Переименовать", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                editingTagMarker = marker
            } label: {
                Label("Тег", systemImage: "tag")
            }
            .tint(.orange)
        }
    }

    @ViewBuilder
    private func markerContextMenu(for marker: TimelineMarker) -> some View {
        Button {
            renamingMarker = marker
            renamingMarkerOldName = marker.name
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
        MarkerTagPopup(
            tags: viewModel.tags,
            selectedTagId: marker.tagId,
            onTagSelected: { tagId in
                viewModel.changeMarkerTag(marker, to: tagId)
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

    // MARK: - Custom Navigation Title

    private var customNavigationTitle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let bpm = viewModel.bpm {
                    Text("\(Int(bpm)) BPM")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Toolbar

    private var toolbarContent: some ToolbarContent {
        Group {
            // Timeline settings button (always visible)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isTimelineSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .regular))
                }
            }

            // Settings menu (only import/export and rename)
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // Audio file info
                    if let audio = viewModel.audio {
                        Section {
                            Label(audio.originalFileName, systemImage: "info.circle")
                        }
                    }

                    Button {
                        renameText = viewModel.name
                        isRenamingTimeline = true
                    } label: {
                        Label("Переименовать таймлайн", systemImage: "pencil")
                    }

                    Divider()

                    Button {
                        isCSVImportPresented = true
                    } label: {
                        Label("Import markers (CSV)", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        prepareExport()
                    } label: {
                        Label("Export markers (Reaper CSV)", systemImage: "square.and.arrow.down")
                    }
                    .disabled(viewModel.markers.isEmpty)

                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .regular))
                }
            }
        }
    }

    // MARK: - Full Player Content (Medium / Expanded)

    /// Whether keyframe tracks should be shown (expanded mode or landscape, has audio & markers)
    private func showKeyframeTracks(isLandscape: Bool) -> Bool {
        (isLandscape || sheetDetent == .expanded) && hasAudio && !viewModel.visibleMarkers.isEmpty
    }

    /// Estimated height of keyframe tracks based on active tags with markers
    private var keyframeTracksEstimatedHeight: CGFloat {
        let markerTagIds = Set(viewModel.visibleMarkers.map(\.tagId))
        let activeTagCount = viewModel.tags.filter { markerTagIds.contains($0.id) }.count
        guard activeTagCount > 0 else { return 0 }
        return CGFloat(activeTagCount) * 22 + 8  // trackHeight(22) * count + vertical padding(8)
    }

    private func fullPlayerContent(isLandscape: Bool = false) -> some View {
        VStack(spacing: isLandscape ? 4 : 16) {
            if isLandscape {
                // MARK: Landscape — compact control bar above timeline
                landscapeControlBar
            } else {
                // MARK: Portrait — standard toolbar buttons
                portraitToolbarButtons
                    .padding(.bottom, 8)
            }

            // MARK: Flexible middle — Unified Timeline Container
            GeometryReader { geo in
                let available = geo.size.height
                let showKF = showKeyframeTracks(isLandscape: isLandscape)
                let kfHeight: CGFloat = showKF ? keyframeTracksEstimatedHeight : 0
                let kfSpacing: CGFloat = showKF ? 8 : 0
                let timelineOverhead: CGFloat = hasAudio ? 46 : 0
                let wfHeight = max(60, available - kfHeight - kfSpacing - timelineOverhead)
                let centerX = geo.size.width / 2

                ZStack(alignment: .topLeading) {
                    VStack(spacing: 8) {
                        timelineBar(waveformHeight: wfHeight)

                        if showKF {
                            KeyframeTracksView(
                                duration: viewModel.duration,
                                currentTime: viewModel.currentTime,
                                markers: viewModel.visibleMarkers,
                                tags: viewModel.tags,
                                prerollSeconds: viewModel.prerollSeconds,
                                zoomScale: $viewModel.zoomScale,
                                effectiveDisplayTime: viewModel.currentTime + viewModel.prerollSeconds,
                                markerFlashPublisher: viewModel.markerFlashPublisher,
                                onSeek: { viewModel.seek(to: $0) },
                                onScrubStart: { viewModel.startScrubbing() },
                                onScrubEnd: { viewModel.stopScrubbing() }
                            )
                        }
                    }

                    if hasAudio {
                        let playheadHeight = wfHeight + (showKF ? kfSpacing + kfHeight : 0)

                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2, height: playheadHeight)
                            .offset(x: centerX - 1, y: timelineOverhead)
                            .allowsHitTesting(false)
                    }
                }
            }

            if !isLandscape {
                // MARK: Portrait bottom — Timecode, controls, marker button
                if hasAudio {
                    timecode
                    playbackControls
                }
                addMarkerButton
            }
        }
        .padding(.horizontal, isLandscape ? 8 : 24)
        .padding(.bottom, isLandscape ? 4 : 24)
        .padding(.top, 4)
    }

    // MARK: - Landscape Compact Control Bar

    /// Single horizontal row: timecode | rewind | play | forward | add marker
    /// All elements compact to leave maximum vertical space for timeline.
    private var landscapeControlBar: some View {
        HStack(spacing: 12) {
            // Tag filter
            Button {
                isTagFilterPresented = true
            } label: {
                Image(systemName: hasActiveFilter ? "line.horizontal.3.decrease.circle.fill" : "line.horizontal.3.decrease")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(hasActiveFilter ? .accentColor : .primary)
                    .frame(height: 28)
                    .padding(.horizontal, 8)
            }
            .glassEffect(.regular.interactive(), in: .capsule)

            // Metronome
            if viewModel.bpm != nil {
                Button {
                    viewModel.toggleMetronome()
                } label: {
                    MetronomeIcon(
                        isPlaying: viewModel.isMetronomeEnabled,
                        currentBeat: viewModel.currentBeat,
                        isEnabled: viewModel.isMetronomeUserEnabled
                    )
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(viewModel.isMetronomeUserEnabled ? .accentColor : .primary)
                    .frame(height: 28)
                    .padding(.horizontal, 8)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
            }

            Spacer()

            if hasAudio {
                // Compact timecode
                Text(viewModel.timecode())
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(viewModel.isPlaying ? .green : .primary)
                    .opacity(timelineRedrawTrigger ? 0.9999 : 1.0)

                // Compact playback controls
                HStack(spacing: 16) {
                    Button { viewModel.seekBackward() } label: {
                        Image(systemName: "gobackward.5")
                            .font(.system(size: 18, weight: .medium))
                    }
                    .frame(width: 28, height: 28)

                    Button { playButtonAction() } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .medium))
                    }
                    .frame(width: 32, height: 32)
                    .scaleEffect(playButtonScale)

                    Button { viewModel.seekForward() } label: {
                        Image(systemName: "goforward.5")
                            .font(.system(size: 18, weight: .medium))
                    }
                    .frame(width: 28, height: 28)
                }
                .foregroundColor(.primary)
            }

            Spacer()

            // Undo/Redo
            HStack(spacing: 0) {
                Menu {
                    ForEach(Array(viewModel.undoManager.getUndoHistory(limit: 10).enumerated()), id: \.offset) { offset, item in
                        Button {
                            viewModel.undoManager.undoToIndex(offset)
                        } label: {
                            Text(item.description)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(viewModel.undoManager.canUndo ? .primary : .secondary)
                        .frame(width: 28, height: 28)
                } primaryAction: {
                    viewModel.undoManager.undo()
                }
                .disabled(!viewModel.undoManager.canUndo)

                Divider().frame(height: 16)

                Menu {
                    ForEach(Array(viewModel.undoManager.getRedoHistory(limit: 10).enumerated()), id: \.offset) { offset, item in
                        Button {
                            viewModel.undoManager.redoToIndex(offset)
                        } label: {
                            Text(item.description)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(viewModel.undoManager.canRedo ? .primary : .secondary)
                        .frame(width: 28, height: 28)
                } primaryAction: {
                    viewModel.undoManager.redo()
                }
                .disabled(!viewModel.undoManager.canRedo)
            }
            .glassEffect(.regular.interactive(), in: .capsule)

            // Compact add marker button
            Button {
                markerCreationTime = viewModel.currentTime
                if viewModel.shouldShowMarkerPopup {
                    wasPlayingBeforePopup = viewModel.isPlaying
                    if viewModel.shouldPauseOnMarkerCreation && wasPlayingBeforePopup {
                        viewModel.pausePlayback()
                    }
                    isMarkerNamePopupPresented = true
                } else {
                    let markerNumber = viewModel.markers.count + 1
                    let defaultName = "Marker \(markerNumber)"
                    let defaultTag = viewModel.defaultTag ?? viewModel.tags.first!
                    viewModel.addMarker(name: defaultName, tagId: defaultTag.id, at: markerCreationTime)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.accentColor.gradient))
            }
            .buttonStyle(.plain)
            .disabled(!hasAudio)
            .opacity(hasAudio ? 1 : 0.5)
        }
        .frame(height: 36)
    }

    // MARK: - Portrait Toolbar Buttons

    private var portraitToolbarButtons: some View {
        HStack(spacing: 8) {
            // Tag filter button
            Button {
                isTagFilterPresented = true
            } label: {
                Image(systemName: hasActiveFilter ? "line.horizontal.3.decrease.circle.fill" : "line.horizontal.3.decrease")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(hasActiveFilter ? .accentColor : .primary)
                    .frame(height: 36)
                    .padding(.horizontal, 14)
            }
            .glassEffect(.regular.interactive(), in: .capsule)

            // Metronome indicator (only if BPM is set)
            if viewModel.bpm != nil {
                Button {
                    viewModel.toggleMetronome()
                } label: {
                    MetronomeIcon(
                        isPlaying: viewModel.isMetronomeEnabled,
                        currentBeat: viewModel.currentBeat,
                        isEnabled: viewModel.isMetronomeUserEnabled
                    )
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(viewModel.isMetronomeUserEnabled ? .accentColor : .primary)
                    .frame(height: 36)
                    .padding(.horizontal, 14)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
            }

            Spacer()

            // Undo/Redo buttons
            HStack(spacing: 0) {
                Menu {
                    ForEach(Array(viewModel.undoManager.getUndoHistory(limit: 10).enumerated()), id: \.offset) { offset, item in
                        Button {
                            viewModel.undoManager.undoToIndex(offset)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.description)
                                    .font(.system(size: 15, weight: .regular))
                                Text(item.timeAgo)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(viewModel.undoManager.canUndo ? .primary : .secondary)
                        .frame(width: 40, height: 36)
                } primaryAction: {
                    viewModel.undoManager.undo()
                }
                .disabled(!viewModel.undoManager.canUndo)

                Divider()
                    .frame(height: 20)

                Menu {
                    ForEach(Array(viewModel.undoManager.getRedoHistory(limit: 10).enumerated()), id: \.offset) { offset, item in
                        Button {
                            viewModel.undoManager.redoToIndex(offset)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.description)
                                    .font(.system(size: 15, weight: .regular))
                                Text(item.timeAgo)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(viewModel.undoManager.canRedo ? .primary : .secondary)
                        .frame(width: 40, height: 36)
                } primaryAction: {
                    viewModel.undoManager.redo()
                }
                .disabled(!viewModel.undoManager.canRedo)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    private func timelineBar(waveformHeight: CGFloat = 140) -> some View {
        TimelineBarView(
            duration: viewModel.duration,
            currentTime: viewModel.currentTime,
            waveform: viewModel.visibleWaveform,
            waveform2: nil,  // TODO: Add multi-channel support
            markers: viewModel.visibleMarkers,
            tags: viewModel.tags,
            fps: viewModel.fps,
            bpm: viewModel.bpm,
            isBeatGridEnabled: viewModel.isBeatGridEnabled,
            isSnapToGridEnabled: viewModel.isSnapToGridEnabled,
            beatGridOffset: viewModel.beatGridOffset,
            onBeatGridOffsetChange: { offset in
                viewModel.setBeatGridOffset(offset)
            },
            onBeatGridOffsetCommit: { oldOffset, newOffset in
                viewModel.commitBeatGridOffsetChange(oldOffset: oldOffset, newOffset: newOffset)
            },
            timeSignature: viewModel.timeSignature,
            prerollSeconds: viewModel.prerollSeconds,
            hasAudio: hasAudio,
            barHeight: waveformHeight,
            onAddAudio: {
                print("🎵 [TimelineScreen] onAddAudio called, setting isPickerPresented = true")
                isPickerPresented = true
                print("🎵 [TimelineScreen] isPickerPresented is now: \(isPickerPresented)")
            },
            onSeek: { viewModel.seek(to: $0) },
            onScrubStart: { viewModel.startScrubbing() },
            onScrubEnd: { viewModel.stopScrubbing() },
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
            .monospacedDigit()
            .foregroundColor(viewModel.isPlaying ? .green : .primary)
            .opacity(timelineRedrawTrigger ? 0.9999 : 1.0)  // ✅ FIX: Force redraw on trigger toggle
            .frame(minWidth: 140, alignment: .center)
    }

    private var playbackControls: some View {
        HStack(spacing: 48) {
            Button { viewModel.seekBackward() } label: {
                Image(systemName: "gobackward.5")
                    .font(.system(size: 32, weight: .medium))
            }
            .frame(width: 44, height: 44)

            // Play/Pause button with animation
            Button { playButtonAction() } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 40, weight: .medium))
            }
            .frame(width: 64, height: 64)
            .scaleEffect(playButtonScale)
            .background(
                // Ripple effect circle - fixed size container
                Circle()
                    .stroke(Color.accentColor.opacity(rippleOpacity), lineWidth: 1.5)
                    .scaleEffect(rippleRadius / 32)  // Scale from center instead of changing frame
                    .opacity(rippleOpacity)
            )

            Button { viewModel.seekForward() } label: {
                Image(systemName: "goforward.5")
                    .font(.system(size: 32, weight: .medium))
            }
            .frame(width: 44, height: 44)
        }
        .foregroundColor(.primary)
    }

    private func playButtonAction() {
        // Trigger scale animation (120-180ms)
        withAnimation(.easeOut(duration: 0.15)) {
            playButtonScale = 0.97
        }

        // Reset scale after brief delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)  // 150ms
            withAnimation(.easeOut(duration: 0.1)) {
                playButtonScale = 1.0
            }
        }

        // Trigger ripple effect
        withAnimation(.linear(duration: 0.6)) {
            rippleRadius = 32
            rippleOpacity = 0
        }

        // Reset ripple for next press
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)  // 600ms
            playButtonScale = 1.0
            rippleRadius = 0
            rippleOpacity = 1.0
        }

        // Toggle playback
        viewModel.togglePlayPause()
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
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    Capsule()
                        .fill(Color.accentColor.gradient)
                )
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .hoverEffect(.highlight)
        .disabled(!hasAudio)
        .opacity(hasAudio ? 1 : 0.5)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: isMarkerNamePopupPresented)
    }

    // MARK: - Player Sheet

    private let compactSheetHeight: CGFloat = 220
    private let mediumSheetHeight: CGFloat = 500

    private func expandedSheetHeight(screenHeight: CGFloat) -> CGFloat {
        max(mediumSheetHeight + 100, screenHeight - 20)
    }

    private func sheetHeight(for detent: PlayerSheetDetent, screenHeight: CGFloat) -> CGFloat {
        switch detent {
        case .compact: return compactSheetHeight
        case .medium: return mediumSheetHeight
        case .expanded: return expandedSheetHeight(screenHeight: screenHeight)
        }
    }

    @ViewBuilder
    private func playerSheet(screenHeight: CGFloat) -> some View {
        // Sheet grows upward from bottom — use continuous height for smooth 1:1 tracking
        let dragHeight = sheetDragHeight(screenHeight: screenHeight)
        let isCompact = sheetDetent == .compact && dragStartHeight == nil  // Only compact when not dragging

        VStack(spacing: 0) {
            // Grab handle
            sheetGrabHandle(screenHeight: screenHeight)

            // Content — switches only on committed detent, never mid-gesture
            if isCompact {
                compactPlayerContent
            } else {
                fullPlayerContent()
            }
        }
        .frame(height: dragHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 8, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// Continuous dimming opacity based on current sheet height — fades in as height exceeds medium
    private func dimmingOverlayOpacity(screenHeight: CGFloat) -> Double {
        let medium = mediumSheetHeight
        let expanded = expandedSheetHeight(screenHeight: screenHeight)
        let current = currentSheetHeight
        guard current > medium else { return 0 }
        let progress = Double((current - medium) / (expanded - medium))
        return min(0.3, 0.3 * progress)
    }

    /// Continuous sheet height during drag — uses absolute height tracking for 1:1 correspondence
    private func sheetDragHeight(screenHeight: CGFloat) -> CGFloat {
        let maxH = expandedSheetHeight(screenHeight: screenHeight)
        // Use currentSheetHeight directly for smooth 1:1 drag without lag
        // Clamp between min and max to prevent over-dragging
        return max(compactSheetHeight, min(maxH, currentSheetHeight))
    }

    private func sheetGrabHandle(screenHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .contentShape(Rectangle())
        .gesture(sheetHandleDragGesture(screenHeight: screenHeight))
    }

    private func sheetHandleDragGesture(screenHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                // Initialize drag start height on first change
                if dragStartHeight == nil {
                    dragStartHeight = currentSheetHeight
                }

                guard let startHeight = dragStartHeight else { return }

                // 1:1 correspondence: translate drag directly to height change
                // Using .global coordinate space so the translation is not affected
                // by the view's own movement — this ensures true 1:1 finger tracking.
                let maxH = expandedSheetHeight(screenHeight: screenHeight)
                let newHeight = startHeight - value.translation.height

                currentSheetHeight = max(compactSheetHeight, min(maxH, newHeight))
                sheetDragOffset = value.translation.height
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.height - value.translation.height

                let newDetent = resolveDetent(
                    currentHeight: currentSheetHeight,
                    velocity: velocity,
                    screenHeight: screenHeight
                )

                let targetHeight = sheetHeight(for: newDetent, screenHeight: screenHeight)

                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    currentSheetHeight = targetHeight
                    sheetDetent = newDetent
                    sheetDragOffset = 0
                    dragStartHeight = nil
                }
            }
    }

    private func resolveDetent(
        currentHeight: CGFloat,
        velocity: CGFloat,
        screenHeight: CGFloat
    ) -> PlayerSheetDetent {
        let compact = compactSheetHeight
        let medium = mediumSheetHeight
        let expanded = expandedSheetHeight(screenHeight: screenHeight)

        // Strong velocity overrides position
        if velocity > 500 {
            // Swipe down → shrink
            switch sheetDetent {
            case .expanded: return .medium
            case .medium: return .compact
            case .compact: return .compact
            }
        } else if velocity < -500 {
            // Swipe up → grow
            switch sheetDetent {
            case .compact: return .medium
            case .medium: return .expanded
            case .expanded: return .expanded
            }
        }

        // Snap to nearest detent
        let options: [(PlayerSheetDetent, CGFloat)] = [
            (.compact, abs(currentHeight - compact)),
            (.medium, abs(currentHeight - medium)),
            (.expanded, abs(currentHeight - expanded))
        ]
        return options.min(by: { $0.1 < $1.1 })?.0 ?? .medium
    }

    // MARK: - Compact Player Content

    private var compactPlayerContent: some View {
        VStack(spacing: 12) {
            if hasAudio {
                compactProgressBar

                HStack(spacing: 40) {
                    Button { viewModel.seekBackward() } label: {
                        Image(systemName: "gobackward.5")
                            .font(.system(size: 24, weight: .medium))
                    }
                    .frame(width: 44, height: 44)

                    Button { playButtonAction() } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 32, weight: .medium))
                    }
                    .frame(width: 56, height: 56)

                    Button { viewModel.seekForward() } label: {
                        Image(systemName: "goforward.5")
                            .font(.system(size: 24, weight: .medium))
                    }
                    .frame(width: 44, height: 44)
                }
                .foregroundColor(.primary)
            }

            addMarkerButton
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, 4)
    }

    private var compactProgressBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let progress = viewModel.duration > 0
                    ? CGFloat(viewModel.currentTime / viewModel.duration)
                    : 0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))

                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(2, geo.size.width * min(1, progress)))
                }
                .frame(height: 6)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let ratio = max(0, min(1, value.location.x / geo.size.width))
                            viewModel.seek(to: viewModel.duration * Double(ratio))
                        }
                )
            }
            .frame(height: 6)

            HStack {
                Text(formatCompactTime(viewModel.currentTime))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                Spacer()
                Text("-\(formatCompactTime(max(0, viewModel.duration - viewModel.currentTime)))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formatCompactTime(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Helpers

    private func prepareExport() {
        let csv = MarkersCSVExporter.export(
            markers: viewModel.markers,
            frameRate: Double(viewModel.projectFPS)
        )
        exportData = csv.data(using: .utf8)
        isExportPresented = true
    }

    /// Handle audio URL from UIDocumentPicker (already copied, no security scope needed)
    private func handleAudioURL(_ url: URL) {
        print("🎵 [handleAudioURL] Processing: \(url)")

        do {
            let data = try Data(contentsOf: url)
            print("✅ Audio data loaded: \(data.count) bytes")

            let vm = viewModel

            Task { @MainActor in
                do {
                    let asset = AVURLAsset(url: url)
                    let d = try await asset.load(.duration)
                    print("✅ Audio duration: \(d.seconds)s")

                    try vm.addAudio(
                        sourceData: data,
                        originalFileName: url.lastPathComponent,
                        fileExtension: url.pathExtension,
                        duration: d.seconds
                    )
                    print("✅ Audio added successfully")

                    // Clean up temp file
                    try? FileManager.default.removeItem(at: url)
                } catch {
                    print("❌ Audio import error: \(error)")
                }
            }
        } catch {
            print("❌ Audio file reading error: \(error)")
        }
    }

    /// Handle audio from .fileImporter (legacy, requires security scope)
    private func handleAudio(_ result: Result<[URL], Error>) {
        print("🎵 [handleAudio] Called with result: \(result)")

        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result {
                print("🎵 [handleAudio] Failure - Error: \(error)")
            }
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            print("❌ Failed to access security scoped resource for: \(url)")
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

    private func handleCSVImport(_ result: Result<[URL], Error>) {
        guard
            case .success(let urls) = result,
            let url = urls.first
        else { return }

        guard url.startAccessingSecurityScopedResource() else {
            csvImportError = "Не удалось получить доступ к файлу"
            showCSVImportError = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            guard let csvContent = String(data: data, encoding: .utf8) else {
                csvImportError = "Не удалось декодировать файл как текст"
                showCSVImportError = true
                return
            }

            viewModel.importMarkersFromCSV(csvContent)
            print("✅ CSV import completed")
        } catch {
            csvImportError = "Ошибка при чтении файла: \(error.localizedDescription)"
            showCSVImportError = true
            print("❌ CSV import error: \(error)")
        }
    }

}
