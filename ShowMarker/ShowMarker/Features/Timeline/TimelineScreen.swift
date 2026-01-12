import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct TimelineScreen: View {

    @StateObject private var viewModel: TimelineViewModel

    @State private var isPickerPresented = false
    @State private var isRenamingTimeline = false
    @State private var renameText = ""

    @State private var renamingMarker: TimelineMarker?
    @State private var renameMarkerText = ""

    @State private var editingTimeMarker: TimelineMarker?
    @State private var markerTimeText = ""

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
        List {
            Section {
                ForEach(viewModel.markers) { marker in
                    MarkerCard(marker: marker, fps: viewModel.fps)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.seek(to: marker.timeSeconds)
                        }
                        .contextMenu {
                            Button {
                                renamingMarker = marker
                                renameMarkerText = marker.name
                            } label: {
                                Label("Переименовать", systemImage: "pencil")
                            }

                            Button {
                                editingTimeMarker = marker
                                markerTimeText = String(format: "%.3f", marker.timeSeconds)
                            } label: {
                                Label("Изменить время положения", systemImage: "clock")
                            }

                            Divider()

                            Button(role: .destructive) {
                                viewModel.deleteMarker(marker)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {

                            Button(role: .destructive) {
                                viewModel.deleteMarker(marker)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }

                            Button {
                                renamingMarker = marker
                                renameMarkerText = marker.name
                            } label: {
                                Label("Переименовать", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(viewModel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) { bottomPanel }
        .onDisappear {
            viewModel.onDisappear()
        }
        .alert("Переименовать маркер", isPresented: Binding(
            get: { renamingMarker != nil },
            set: { if !$0 { renamingMarker = nil } }
        )) {
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
        .alert("Изменить время маркера", isPresented: Binding(
            get: { editingTimeMarker != nil },
            set: { if !$0 { editingTimeMarker = nil } }
        )) {
            TextField("Время (секунды)", text: $markerTimeText)
                .keyboardType(.decimalPad)

            Button("Готово") {
                if let marker = editingTimeMarker,
                   let value = Double(markerTimeText) {
                    viewModel.moveMarker(marker, to: value)
                }
                editingTimeMarker = nil
            }

            Button("Отмена", role: .cancel) {
                editingTimeMarker = nil
            }
        }
    }

    // MARK: - TOOLBAR

    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - BOTTOM PANEL (лево==право==низ = 24pt)

    private var bottomPanel: some View {
        VStack(spacing: 12) {

            // чуть меньше пространства над waveform чтобы визуально кнопка ниже
            TimelineBarView(
                duration: viewModel.duration,
                currentTime: viewModel.currentTime,
                waveform: viewModel.waveform,
                markers: viewModel.markers,
                hasAudio: viewModel.audio != nil,
                onAddAudio: { isPickerPresented = true },
                onSeek: { viewModel.seek(to: $0) },
                onPreviewMoveMarker: { id, time in
                    if let marker = viewModel.markers.first(where: { $0.id == id }) {
                        viewModel.moveMarker(marker, to: time)
                    }
                },
                onCommitMoveMarker: { _, _ in }
            )
            .frame(height: 160)

            Text(viewModel.timecode())
                .font(.system(size: 30, weight: .bold))

            HStack(spacing: 44) {
                Button { viewModel.seekBackward() } label: {
                    Image(systemName: "gobackward.15")
                }
                Button { viewModel.togglePlayPause() } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                }
                Button { viewModel.seekForward() } label: {
                    Image(systemName: "goforward.15")
                }
            }
            .font(.system(size: 28, weight: .semibold))
            .disabled(viewModel.audio == nil)
            .opacity(viewModel.audio == nil ? 0.4 : 1)

            // кнопка опущена визуально за счёт уменьшения высоты waveform и уменьшенных spacing
            Button {
                viewModel.addMarkerAtCurrentTime()
            } label: {
                Text("ДОБАВИТЬ МАРКЕР")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                    )
            }
            .disabled(viewModel.audio == nil)
            .opacity(viewModel.audio == nil ? 0.4 : 1)
        }
        // одинаковые отступы слева/справа/снизу
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        )
    }
}
