import SwiftUI

struct TimelineSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: TimelineViewModel

    // Preroll input state
    @State private var prerollSecondsText: String = ""
    @State private var prerollFramesText: String = ""

    // Callbacks for actions that need to be performed in TimelineScreen
    let onEditBPM: () -> Void
    let onReplaceAudio: () -> Void
    let onDeleteAudio: () -> Void
    let onDeleteAllMarkers: () -> Void

    var body: some View {
        NavigationView {
            List {
                // BPM settings
                Section {
                    if let bpm = viewModel.bpm {
                        HStack {
                            Text("BPM")
                            Spacer()
                            Text("\(Int(bpm))")
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onEditBPM()
                        }

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
                    } else {
                        Button {
                            onEditBPM()
                        } label: {
                            Label("Установить BPM", systemImage: "metronome")
                        }
                    }
                } header: {
                    Text("Темп")
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

                // Metronome settings section (only if BPM is set)
                if viewModel.bpm != nil {
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
