import SwiftUI

struct TimelineSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: TimelineViewModel

    var body: some View {
        NavigationView {
            List {
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

                // Future settings can go here
                Section {
                    Text("Дополнительные настройки будут добавлены в будущем")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                } header: {
                    Text("Прочее")
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
