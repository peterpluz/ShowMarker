import SwiftUI

struct ProjectSettingsView: View {
    @ObservedObject var repository: ProjectRepository
    @Environment(\.dismiss) private var dismiss

    @State private var editingTag: Tag?
    @State private var isAddingTag = false
    @State private var tagToDelete: Tag?
    @State private var showDeleteConfirmation = false
    @State private var showTagInUseAlert = false

    // Rename tag states
    @State private var renamingTag: Tag?
    @State private var renameTagText = ""

    var body: some View {
        ZStack {
            NavigationView {
                List {
                    // FPS Section
                    fpsSection

                    // Haptic Feedback Section
                    hapticFeedbackSection

                    // Tags Section
                    tagsSection
                }
                .navigationTitle("Настройки проекта")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
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

    // MARK: - FPS Section

    private var fpsSection: some View {
        Section {
            NavigationLink {
                FPSPickerView(
                    selectedFPS: repository.project.fps,
                    onSelect: { fps in
                        repository.setProjectFPS(fps)
                    },
                    repository: repository
                )
            } label: {
                HStack {
                    Text("Частота кадров (FPS)")
                    Spacer()
                    Text("\(repository.project.fps)")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        Group {
            Section {
                ForEach(repository.project.tags) { tag in
                    HStack(spacing: 12) {
                        Text(tag.name)
                            .font(.system(size: 17))

                        Spacer()

                        Circle()
                            .fill(Color(hex: tag.colorHex))
                            .frame(width: 24, height: 24)
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button {
                            renamingTag = tag
                            renameTagText = tag.name
                        } label: {
                            Label("Переименовать", systemImage: "pencil")
                        }

                        Button {
                            editingTag = tag
                        } label: {
                            Label("Изменить цвет", systemImage: "paintbrush")
                        }

                        Divider()

                        Button(role: .destructive) {
                            attemptDeleteTag(tag)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            attemptDeleteTag(tag)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }

                        Button {
                            renamingTag = tag
                            renameTagText = tag.name
                        } label: {
                            Label("Переименовать", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
            } header: {
                Text("Теги")
            }

            Section {
                Button {
                    isAddingTag = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.green)

                        Text("Добавить новый тег...")
                            .font(.system(size: 17))
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                }
            }
        }
        .alert("Переименовать тег", isPresented: renameTagBinding) {
            TextField("Название", text: $renameTagText)
            Button("Готово") {
                applyTagRename()
            }
            Button("Отмена", role: .cancel) {
                renamingTag = nil
            }
        }
        .alert("Невозможно удалить", isPresented: $showTagInUseAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Этот тег используется в маркерах. Сначала измените тег у маркеров, затем удалите его.")
        }
    }

    private var renameTagBinding: Binding<Bool> {
        Binding(
            get: { renamingTag != nil },
            set: { if !$0 { renamingTag = nil } }
        )
    }

    private func applyTagRename() {
        guard var tag = renamingTag else { return }
        let name = renameTagText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            renamingTag = nil
            return
        }
        tag.name = name
        repository.updateTag(tag)
        renamingTag = nil
    }

    private func attemptDeleteTag(_ tag: Tag) {
        if repository.isTagUsedByMarkers(tag.id) {
            showTagInUseAlert = true
        } else {
            tagToDelete = tag
            showDeleteConfirmation = true
        }
    }
}

// MARK: - FPS Picker View

struct FPSPickerView: View {
    let selectedFPS: Int
    let onSelect: (Int) -> Void
    @ObservedObject var repository: ProjectRepository

    @Environment(\.dismiss) private var dismiss
    @State private var pendingFPS: Int?
    @State private var showConfirmation = false

    private let fpsOptions = [24, 25, 30, 50, 60, 100]

    private var hasMarkers: Bool {
        repository.project.timelines.contains { !$0.markers.isEmpty }
    }

    var body: some View {
        List {
            ForEach(fpsOptions, id: \.self) { fps in
                Button {
                    if fps != selectedFPS && hasMarkers {
                        pendingFPS = fps
                        showConfirmation = true
                    } else {
                        onSelect(fps)
                        dismiss()
                    }
                } label: {
                    HStack {
                        Text("\(fps) FPS")
                            .foregroundColor(.primary)
                        Spacer()
                        if fps == selectedFPS {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle("Частота кадров")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Изменить частоту кадров?", isPresented: $showConfirmation) {
            Button("Изменить", role: .destructive) {
                if let fps = pendingFPS {
                    onSelect(fps)
                    dismiss()
                }
            }
            Button("Отмена", role: .cancel) {
                pendingFPS = nil
            }
        } message: {
            Text("В проекте уже есть маркеры. При изменении частоты кадров маркеры будут автоматически перемещены к ближайшим точкам квантования новой сетки кадров, что может привести к небольшому смещению их позиций.")
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return "#000000"
        }

        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])

        return String(format: "#%02lX%02lX%02lX",
                      lroundf(r * 255),
                      lroundf(g * 255),
                      lroundf(b * 255))
    }
}
