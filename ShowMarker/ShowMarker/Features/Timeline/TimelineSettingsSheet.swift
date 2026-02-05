import SwiftUI

struct TimelineSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: TimelineViewModel

    // Preroll input state
    @State private var prerollSecondsText: String = ""
    @State private var prerollFramesText: String = ""

    // Preroll marker deletion confirmation
    @State private var showPrerollMarkerDeletionAlert = false
    @State private var pendingPrerollSeconds: Double = 0
    @State private var markersToDeleteInPreroll: [TimelineMarker] = []

    // BPM drag state
    @State private var bpmDragStartValue: Double = 120
    @State private var bpmDragAccumulated: CGFloat = 0

    // Tap tempo state
    @State private var tapTempoTimestamps: [Date] = []
    @State private var tapTempoResetTask: DispatchWorkItem?

    // Callbacks for actions that need to be performed in TimelineScreen
    let onReplaceAudio: () -> Void
    let onDeleteAudio: () -> Void
    let onDeleteAllMarkers: () -> Void

    private var currentBPM: Double {
        viewModel.bpm ?? 120
    }

    var body: some View {
        NavigationView {
            List {
                // BPM settings
                Section {
                    // BPM row: tap tempo button + stepper
                    HStack(spacing: 0) {
                        // Left: Tap Tempo button
                        Button {
                            handleTapTempo()
                        } label: {
                            Text("Задайте темп")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(UIColor.tertiarySystemFill))
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 12)
                        .padding(.vertical, 6)

                        // Right: BPM value with up/down controls
                        bpmStepperControl
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                    // Time signature picker
                    Picker(selection: Binding(
                        get: { viewModel.timeSignature },
                        set: { viewModel.setTimeSignature($0) }
                    )) {
                        ForEach(TimeSignature.allCases, id: \.self) { signature in
                            Text(signature.displayName).tag(signature)
                        }
                    } label: {
                        Label("Тактовый размер", systemImage: "music.note.list")
                    }

                    Toggle(isOn: Binding(
                        get: { viewModel.isBeatGridEnabled },
                        set: { _ in viewModel.toggleBeatGrid() }
                    )) {
                        Label("Показать сетку битов", systemImage: "grid")
                    }

                    Toggle(isOn: Binding(
                        get: { viewModel.isSnapToGridEnabled },
                        set: { _ in viewModel.toggleSnapToGrid() }
                    )) {
                        Label("Привязка к сетке битов", systemImage: "scope")
                    }
                    .disabled(!viewModel.isBeatGridEnabled)
                } header: {
                    Text("Темп")
                } footer: {
                    Text("Касайтесь стрелок для изменения пошагово или смахните вертикально для изменения на большие значения.")
                        .font(.system(size: 13))
                }

                // Preroll settings
                Section {
                    HStack(spacing: 16) {
                        Text("Преролл")

                        Spacer()

                        HStack(spacing: 4) {
                            TextField("SS", text: $prerollSecondsText)
                                .keyboardType(.numberPad)
                                .frame(width: 40)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(8)
                                .onChange(of: prerollSecondsText) { _, newValue in
                                    updatePrerollFromInput()
                                }

                            Text(":")
                                .foregroundColor(.secondary)

                            TextField("FF", text: $prerollFramesText)
                                .keyboardType(.numberPad)
                                .frame(width: 40)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(8)
                                .onChange(of: prerollFramesText) { _, newValue in
                                    updatePrerollFromInput()
                                }
                        }
                    }
                } header: {
                    Text("Преролл")
                } footer: {
                    Text("Время в формате SS:FF (секунды:кадры). Зона преролла выделяется на таймлайне.")
                        .font(.system(size: 13))
                }
                .onAppear {
                    initPrerollFields()
                }

                // Metronome settings section
                Section {
                    // Volume slider
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "speaker.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 16))

                            Text("Громкость метронома")
                                .font(.system(size: 16, weight: .regular))

                            Spacer()

                            Text("\(Int(viewModel.metronomeVolume * 100))%")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        // Horizontal volume slider
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.metronomeVolume) },
                                set: { viewModel.setMetronomeVolume(Float($0)) }
                            ),
                            in: 0...1
                        )
                        .tint(.accentColor)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Метроном")
                } footer: {
                    Text("Метроном автоматически запускается вместе с воспроизведением")
                        .font(.system(size: 13))
                }

                // Marker settings
                Section {
                    Toggle(isOn: $viewModel.isAutoScrollEnabled) {
                        Label("Автоскролл маркеров", systemImage: "arrow.down.circle")
                    }

                    Toggle(isOn: $viewModel.shouldPauseOnMarkerCreation) {
                        Label("Останавливать воспроизведение", systemImage: "pause.circle")
                    }

                    Toggle(isOn: $viewModel.shouldShowMarkerPopup) {
                        Label("Показывать окно создания маркера", systemImage: "square.and.pencil")
                    }
                } header: {
                    Text("Маркеры")
                } footer: {
                    Text("Автоскролл прокручивает список к следующему маркеру во время воспроизведения")
                        .font(.system(size: 13))
                }

                // Audio settings (only if audio is present)
                if viewModel.audio != nil {
                    Section {
                        Button {
                            onReplaceAudio()
                        } label: {
                            Label("Заменить аудиофайл", systemImage: "arrow.triangle.2.circlepath")
                        }

                        Button(role: .destructive) {
                            onDeleteAudio()
                        } label: {
                            Label("Удалить аудиофайл", systemImage: "trash")
                        }
                    } header: {
                        Text("Аудио")
                    }
                }

                // Danger zone
                Section {
                    Button(role: .destructive) {
                        onDeleteAllMarkers()
                    } label: {
                        Label("Удалить все маркеры", systemImage: "trash.fill")
                    }
                    .disabled(viewModel.markers.isEmpty)
                } header: {
                    Text("Опасная зона")
                }
            }
            .navigationTitle("Настройки таймлайна")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
            .alert("Маркеры за пределами преролла", isPresented: $showPrerollMarkerDeletionAlert) {
                Button("Удалить и изменить", role: .destructive) {
                    for marker in markersToDeleteInPreroll {
                        viewModel.deleteMarker(marker)
                    }
                    viewModel.setPrerollSeconds(pendingPrerollSeconds)
                }
                Button("Отмена", role: .cancel) {
                    // Revert input fields to current preroll value
                    initPrerollFields()
                }
            } message: {
                let count = markersToDeleteInPreroll.count
                Text("При уменьшении преролла \(count) \(count == 1 ? "маркер будет удалён" : "маркеров будут удалены"). Это действие нельзя отменить.")
            }
        }
    }

    // MARK: - BPM Stepper Control

    private var bpmStepperControl: some View {
        HStack(spacing: 0) {
            // BPM value display with vertical drag gesture
            Text("\(Int(currentBPM))")
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .frame(width: 60, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if bpmDragAccumulated == 0 {
                                bpmDragStartValue = currentBPM
                            }
                            bpmDragAccumulated = value.translation.height
                            // Dragging UP = increase, DOWN = decrease
                            // Every 8pt of drag = 1 BPM
                            let delta = -bpmDragAccumulated / 8
                            let newBPM = max(20, min(300, bpmDragStartValue + Double(delta)))
                            viewModel.setBPM(Double(Int(newBPM)))
                        }
                        .onEnded { _ in
                            bpmDragAccumulated = 0
                        }
                )

            // Up/Down arrows
            VStack(spacing: 2) {
                Button {
                    let newBPM = min(300, currentBPM + 1)
                    viewModel.setBPM(newBPM)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    let newBPM = max(20, currentBPM - 1)
                    viewModel.setBPM(newBPM)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    // MARK: - Tap Tempo

    private func handleTapTempo() {
        let now = Date()

        // Reset if last tap was more than 2 seconds ago
        if let last = tapTempoTimestamps.last, now.timeIntervalSince(last) > 2.0 {
            tapTempoTimestamps.removeAll()
        }

        tapTempoTimestamps.append(now)

        // Keep only last 8 taps
        if tapTempoTimestamps.count > 8 {
            tapTempoTimestamps.removeFirst()
        }

        // Need at least 2 taps to calculate BPM
        if tapTempoTimestamps.count >= 2 {
            let intervals = zip(tapTempoTimestamps.dropFirst(), tapTempoTimestamps).map {
                $0.timeIntervalSince($1)
            }
            let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
            let bpm = 60.0 / avgInterval
            let clampedBPM = max(20, min(300, round(bpm)))
            viewModel.setBPM(clampedBPM)
        }

        // Auto-reset after 2 seconds of inactivity
        tapTempoResetTask?.cancel()
        let task = DispatchWorkItem { [self] in
            tapTempoTimestamps.removeAll()
        }
        tapTempoResetTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: task)
    }

    // MARK: - Preroll Helpers

    private func initPrerollFields() {
        let fps = viewModel.fps
        let totalSeconds = viewModel.prerollSeconds
        let wholeSeconds = Int(totalSeconds)
        let fractionalSeconds = totalSeconds - Double(wholeSeconds)
        let frames = Int(round(fractionalSeconds * Double(fps)))

        prerollSecondsText = wholeSeconds > 0 ? String(wholeSeconds) : ""
        prerollFramesText = frames > 0 ? String(frames) : ""
    }

    private func updatePrerollFromInput() {
        let fps = viewModel.fps
        let seconds = Int(prerollSecondsText) ?? 0
        let frames = Int(prerollFramesText) ?? 0

        // Clamp frames to valid range
        let clampedFrames = max(0, min(frames, fps - 1))

        let totalSeconds = Double(seconds) + Double(clampedFrames) / Double(fps)

        // If increasing or same preroll — apply immediately, no markers are affected
        if totalSeconds >= viewModel.prerollSeconds {
            viewModel.setPrerollSeconds(totalSeconds)
            return
        }

        // Decreasing preroll — check for markers that would fall outside the new range.
        // Markers in preroll have negative timeSeconds; a marker at -3.0 is outside
        // if the new preroll is only 2 seconds (-3.0 < -2.0).
        let markersOutside = viewModel.markers.filter { $0.timeSeconds < -totalSeconds }

        if markersOutside.isEmpty {
            viewModel.setPrerollSeconds(totalSeconds)
        } else {
            // Show confirmation before deleting markers
            pendingPrerollSeconds = totalSeconds
            markersToDeleteInPreroll = markersOutside
            showPrerollMarkerDeletionAlert = true
        }
    }
}
