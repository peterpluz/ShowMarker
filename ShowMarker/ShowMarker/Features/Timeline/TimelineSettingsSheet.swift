import SwiftUI

struct TimelineSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: TimelineViewModel

    // Preroll input state
    @State private var prerollSecondsText: String = ""
    @State private var prerollFramesText: String = ""

    // BPM drag state
    @State private var bpmDragStartValue: Double = 120
    @State private var bpmDragAccumulated: CGFloat = 0

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
                    // BPM stepper row
                    HStack(spacing: 0) {
                        // Left side: "Задайте темп" label
                        Text("Задайте темп")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)

                        // Right side: BPM value with up/down controls
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
        viewModel.setPrerollSeconds(totalSeconds)
    }
}
