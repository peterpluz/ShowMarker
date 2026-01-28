import SwiftUI

struct TimelineSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: TimelineViewModel
    @ObservedObject var repository: ProjectRepository

    // Callbacks for actions that need to be performed in TimelineScreen
    let onEditBPM: () -> Void
    let onReplaceAudio: () -> Void
    let onDeleteAudio: () -> Void
    let onDeleteAllMarkers: () -> Void

    // Tag editing states
    @State private var editingTag: Tag?
    @State private var isAddingTag = false
    @State private var tagToDelete: Tag?
    @State private var showDeleteConfirmation = false

    // FPS change states
    @State private var pendingFPS: Int?
    @State private var showFPSConfirmation = false

    private let fpsOptions = [24, 25, 30, 50, 60, 100]

    private var hasMarkers: Bool {
        repository.project.timelines.contains { !$0.markers.isEmpty }
    }

    var body: some View {
        ZStack {
            NavigationView {
                List {
                    // FPS Section
                    fpsSection

                    // Haptic Feedback Section
                    hapticFeedbackSection

                    // BPM settings
                    bpmSection

                    // Metronome settings section (only if BPM is set)
                    if viewModel.bpm != nil {
                        metronomeSection
                    }

                    // Marker settings
                    markerSettingsSection

                    // Tags Section
                    tagsSection

                    // Audio settings (only if audio is present)
                    if viewModel.audio != nil {
                        audioSection
                    }

                    // Danger zone
                    dangerZoneSection
                }
                .navigationTitle("Настройки")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") {
                            dismiss()
                        }
                    }
                }
                .alert("Удалить тег?", isPresented: $showDeleteConfirmation, presenting: tagToDelete) { tag in
                    Button("Удалить", role: .destructive) {
                        repository.deleteTag(id: tag.id)
                        tagToDelete = nil
                    }
                    Button("Отмена", role: .cancel) {
                        tagToDelete = nil
                    }
                } message: { tag in
                    Text("Все маркеры с тегом \"\(tag.name)\" будут переведены на первый тег в списке.")
                }
                .alert("Изменить частоту кадров?", isPresented: $showFPSConfirmation) {
                    Button("Изменить", role: .destructive) {
                        if let fps = pendingFPS {
                            repository.setProjectFPS(fps)
                        }
                    }
                    Button("Отмена", role: .cancel) {
                        pendingFPS = nil
                    }
                } message: {
                    Text("В проекте уже есть маркеры. При изменении частоты кадров маркеры будут автоматически перемещены к ближайшим точкам квантования новой сетки кадров, что может привести к небольшому смещению их позиций.")
                }
            }

            // Tag editor pop-up overlay for adding new tag
            if isAddingTag {
                TagEditorView(
                    tag: nil,
                    allTags: repository.project.tags,
                    onSave: { newTag in
                        repository.addTag(newTag)
                        isAddingTag = false
                    },
                    onCancel: {
                        isAddingTag = false
                    }
                )
            }

            // Tag editor pop-up overlay for editing existing tag
            if let tag = editingTag {
                TagEditorView(
                    tag: tag,
                    allTags: repository.project.tags,
                    onSave: { updatedTag in
                        repository.updateTag(updatedTag)
                        editingTag = nil
                    },
                    onCancel: {
                        editingTag = nil
                    }
                )
            }
        }
    }

    // MARK: - FPS Section

    private var fpsSection: some View {
        Section {
            Picker("Частота кадров (FPS)", selection: Binding(
                get: { repository.project.fps },
                set: { newFPS in
                    if newFPS != repository.project.fps && hasMarkers {
                        pendingFPS = newFPS
                        showFPSConfirmation = true
                    } else {
                        repository.setProjectFPS(newFPS)
                    }
                }
            )) {
                ForEach(fpsOptions, id: \.self) { fps in
                    Text("\(fps) FPS").tag(fps)
                }
            }
        }
    }

    // MARK: - Haptic Feedback Section

    private var hapticFeedbackSection: some View {
        Section {
            Toggle("Вибрация маркера", isOn: Binding(
                get: { repository.project.isMarkerHapticFeedbackEnabled },
                set: { newValue in
                    repository.project.isMarkerHapticFeedbackEnabled = newValue
                }
            ))
        } header: {
            Text("Обратная связь")
        }
    }

    // MARK: - BPM Section

    private var bpmSection: some View {
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
                    Label("Установить BPM", systemImage: "square.and.line.vertical.and.square.filled")
                }
            }
        } header: {
            Text("Темп")
        }
    }

    // MARK: - Metronome Section

    private var metronomeSection: some View {
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

    // MARK: - Marker Settings Section

    private var markerSettingsSection: some View {
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
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        Section {
            ForEach(repository.project.tags) { tag in
                HStack(spacing: 12) {
                    // Color circle
                    Circle()
                        .fill(Color(hex: tag.colorHex))
                        .frame(width: 14, height: 14)

                    // Tag name
                    Text(tag.name)
                        .font(.system(size: 17))

                    Spacer()

                    // Edit button
                    Button {
                        editingTag = tag
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        tagToDelete = tag
                        showDeleteConfirmation = true
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }

            // Add tag button
            Button {
                isAddingTag = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.green))

                    Text("Добавить тег")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.primary)

                    Spacer()
                }
            }
        } header: {
            Text("Теги")
        }
    }

    // MARK: - Audio Section

    private var audioSection: some View {
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

    // MARK: - Danger Zone Section

    private var dangerZoneSection: some View {
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
}
