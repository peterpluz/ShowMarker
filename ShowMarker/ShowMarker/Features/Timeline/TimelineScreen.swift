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

    // Add marker button interaction
    @State private var isAddMarkerButtonPressed = false

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

                // Tag picker menu overlay
                if let marker = editingTagMarker {
                    tagPickerMenuOverlay(for: marker)
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
            let screenHeight = geometry.size.height
            let effHeight = effectiveSheetHeight(screenHeight: screenHeight)

            ZStack(alignment: .bottom) {
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
                        Color.clear.frame(height: effHeight + 8)
                    }
                    .onChange(of: viewModel.nextMarkerID) { oldValue, nextID in
                        guard viewModel.isAutoScrollEnabled, let nextID = nextID else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(nextID, anchor: .center)
                        }
                    }
                }

                // Dimming overlay — progressive, proportional to sheet expansion
                Color.black
                    .opacity(sheetDimmingOpacity(screenHeight: screenHeight))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // Player sheet
                playerSheet(screenHeight: screenHeight)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    customNavigationTitle
                }
                toolbarContent
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            markerSwipeActions(for: marker)
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

    @ViewBuilder
    private func markerSwipeActions(for marker: TimelineMarker) -> some View {
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

    private func tagPickerMenuOverlay(for marker: TimelineMarker) -> some View {
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
        VStack(spacing: 2) {
            Text(viewModel.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)

            HStack(spacing: 8) {
                if let audio = viewModel.audio {
                    Text(audio.originalFileName)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)

                    if viewModel.bpm != nil {
                        Text("•")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }

                if let bpm = viewModel.bpm {
                    Text("\(Int(bpm)) BPM")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                } else if viewModel.audio != nil {
                    Text("Tap to set BPM")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .onTapGesture {
                // Open timeline settings for BPM editing
                isTimelineSettingsPresented = true
            }
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

    private func fullPlayerContent(waveformHeight: CGFloat) -> some View {
        VStack(spacing: 16) {
            // Undo/Redo and Tag Filter buttons above timeline
            HStack {
                // Tag filter button (left side, separate)
                Button {
                    isTagFilterPresented = true
                } label: {
                    Image(systemName: hasActiveFilter ? "line.horizontal.3.decrease.circle.fill" : "line.horizontal.3.decrease")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(hasActiveFilter ? .accentColor : .secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                )

                Spacer()

                // Metronome indicator (center, only if BPM is set)
                if viewModel.bpm != nil {
                    MetronomeIndicator(
                        isPlaying: viewModel.isMetronomeEnabled,
                        currentBeat: viewModel.currentBeat,
                        bpm: viewModel.bpm,
                        isEnabled: viewModel.isMetronomeUserEnabled,
                        onToggle: {
                            viewModel.toggleMetronome()
                        }
                    )

                    Spacer()
                }

                // Undo/Redo buttons (right side)
                HStack(spacing: 12) {
                    // Undo button with long press menu
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
                        Button {
                            viewModel.undoManager.undo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                        .disabled(!viewModel.undoManager.canUndo)
                    }
                    .disabled(!viewModel.undoManager.canUndo)

                    // Redo button with long press menu
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
                        Button {
                            viewModel.undoManager.redo()
                        } label: {
                            Image(systemName: "arrow.uturn.forward")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                        .disabled(!viewModel.undoManager.canRedo)
                    }
                    .disabled(!viewModel.undoManager.canRedo)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                )
            }
            .padding(.bottom, 8)

            timelineBar(waveformHeight: waveformHeight)

            // ИСПРАВЛЕНО: тайм и контролы видимы только с аудио
            if hasAudio {
                timecode
                playbackControls
            }

            addMarkerButton
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, 4)
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
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    Capsule()
                        .fill(Color.accentColor)
                )
        }
        .disabled(!hasAudio)
        .opacity(hasAudio ? 1 : 0.5)
        .scaleEffect(isAddMarkerButtonPressed ? 0.95 : 1.0)
        .brightness(isAddMarkerButtonPressed ? -0.05 : 0)
        .gesture(
            DragGesture()
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isAddMarkerButtonPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isAddMarkerButtonPressed = false
                    }
                }
        )
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

    private func effectiveSheetHeight(screenHeight: CGFloat) -> CGFloat {
        let base = sheetHeight(for: sheetDetent, screenHeight: screenHeight)
        let raw = base - sheetDragOffset
        let minH = compactSheetHeight
        let maxH = expandedSheetHeight(screenHeight: screenHeight)

        if raw < minH {
            // Rubber band below compact (dragging down past limit)
            let overscroll = minH - raw
            return minH - rubberBand(overscroll, dimension: minH)
        } else if raw > maxH {
            // Rubber band above expanded (dragging up past limit)
            let overscroll = raw - maxH
            return maxH + rubberBand(overscroll, dimension: maxH)
        }
        return raw
    }

    /// Standard iOS rubber-band formula (same as UIScrollView)
    private func rubberBand(_ offset: CGFloat, dimension: CGFloat) -> CGFloat {
        let c: CGFloat = 0.55
        return (1 - (1 / (offset * c / dimension + 1))) * dimension
    }

    /// Progressive dimming: 0 at medium, 0.3 at expanded (Apple standard max)
    private func sheetDimmingOpacity(screenHeight: CGFloat) -> Double {
        let effHeight = effectiveSheetHeight(screenHeight: screenHeight)
        let medium = mediumSheetHeight
        let expanded = expandedSheetHeight(screenHeight: screenHeight)

        guard effHeight > medium else { return 0 }
        let progress = min(1, (effHeight - medium) / (expanded - medium))
        return Double(progress) * 0.3
    }

    private func waveformDynamicHeight(sheetHeight h: CGFloat) -> CGFloat {
        let compact = compactSheetHeight     // 220
        let medium = mediumSheetHeight       // 500
        let minWaveform: CGFloat = 60
        let baseWaveform: CGFloat = 140

        if h <= compact {
            return minWaveform
        } else if h <= medium {
            // Proportional interpolation: 60pt at compact → 140pt at medium
            let progress = (h - compact) / (medium - compact)
            return minWaveform + progress * (baseWaveform - minWaveform)
        } else {
            // Above medium: keeps growing linearly
            return baseWaveform + (h - medium)
        }
    }

    @ViewBuilder
    private func playerSheet(screenHeight: CGFloat) -> some View {
        let effHeight = effectiveSheetHeight(screenHeight: screenHeight)
        let wfHeight = waveformDynamicHeight(sheetHeight: effHeight)

        VStack(spacing: 0) {
            // Grab handle
            sheetGrabHandle(screenHeight: screenHeight)

            // Single unified content — clipped by sheet frame, never switches layout
            fullPlayerContent(waveformHeight: wfHeight)
        }
        .frame(height: effHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.08), radius: 4, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
        // Animation is applied explicitly via withAnimation in the drag gesture onEnded
    }

    private func sheetGrabHandle(screenHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(UIColor.tertiaryLabel))
                .frame(width: 36, height: 5)
                .padding(.top, 5)
                .padding(.bottom, 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 20)
        .contentShape(Rectangle().inset(by: -12))  // Larger hit area than visual
        .gesture(sheetHandleDragGesture(screenHeight: screenHeight))
    }

    private func sheetHandleDragGesture(screenHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Direct 1:1 tracking — no animation during drag
                sheetDragOffset = value.translation.height
            }
            .onEnded { value in
                let baseHeight = sheetHeight(for: sheetDetent, screenHeight: screenHeight)
                let currentHeight = baseHeight - value.translation.height
                let velocity = value.predictedEndTranslation.height - value.translation.height

                let newDetent = resolveDetent(
                    currentHeight: currentHeight,
                    velocity: velocity,
                    screenHeight: screenHeight
                )

                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.86)) {
                    sheetDetent = newDetent
                    sheetDragOffset = 0
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
