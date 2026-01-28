import SwiftUI

struct TimelineSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: TimelineViewModel

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
}
