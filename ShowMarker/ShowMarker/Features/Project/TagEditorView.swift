import SwiftUI

struct TagEditorView: View {
    let tag: Tag?  // nil = creating new tag
    let allTags: [Tag]
    let onSave: (Tag) -> Void
    let onCancel: () -> Void

    @State private var tagName: String
    @State private var selectedColor: String
    @FocusState private var isTextFieldFocused: Bool

    // Predefined color palette
    private let colorPalette: [TagColor] = [
        TagColor(name: "Красный", hex: "#FF3B30"),
        TagColor(name: "Оранжевый", hex: "#FF9500"),
        TagColor(name: "Желтый", hex: "#FFCC00"),
        TagColor(name: "Зеленый", hex: "#34C759"),
        TagColor(name: "Мятный", hex: "#00C7BE"),
        TagColor(name: "Синий", hex: "#007AFF"),
        TagColor(name: "Индиго", hex: "#5856D6"),
        TagColor(name: "Фиолетовый", hex: "#AF52DE"),
        TagColor(name: "Розовый", hex: "#FF2D55"),
        TagColor(name: "Серый", hex: "#8E8E93"),
        TagColor(name: "Коричневый", hex: "#A2845E"),
        TagColor(name: "Черный", hex: "#000000")
    ]

    init(
        tag: Tag?,
        allTags: [Tag],
        onSave: @escaping (Tag) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.tag = tag
        self.allTags = allTags
        self.onSave = onSave
        self.onCancel = onCancel

        // Initialize state
        _tagName = State(initialValue: tag?.name ?? "")
        _selectedColor = State(initialValue: tag?.colorHex ?? "#FF3B30")
    }

    private var isEditing: Bool {
        tag != nil
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.25)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            // Popup content
            VStack(spacing: 16) {
                // Title
                Text(isEditing ? "Редактировать тег" : "Новый тег")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.top, 20)

                // Text field
                HStack(spacing: 8) {
                    TextField("Название тега", text: $tagName)
                        .font(.system(size: 17))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.tertiarySystemFill))
                        )
                        .focused($isTextFieldFocused)

                    // Clear button
                    if !tagName.isEmpty {
                        Button {
                            tagName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color(.tertiaryLabel))
                                .font(.system(size: 20))
                        }
                        .padding(.trailing, 4)
                    }
                }
                .padding(.horizontal, 16)

                // Color picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Цвет")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(colorPalette, id: \.hex) { colorOption in
                                Button {
                                    selectedColor = colorOption.hex
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: colorOption.hex))
                                            .frame(width: 40, height: 40)

                                        if selectedColor == colorOption.hex {
                                            Circle()
                                                .strokeBorder(Color.primary, lineWidth: 3)
                                                .frame(width: 46, height: 46)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(height: 50)
                }

                // Buttons
                HStack(spacing: 8) {
                    // Cancel button
                    Button {
                        onCancel()
                    } label: {
                        Text("Отмена")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.tertiarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)

                    // Save button
                    Button {
                        saveTag()
                    } label: {
                        Text(isEditing ? "Сохранить" : "Создать")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 10)
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 5)
        }
        .onAppear {
            // Auto-focus text field when popup appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }

    private func saveTag() {
        let trimmedName = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let existingTag = tag {
            // Update existing tag
            var updatedTag = existingTag
            updatedTag.name = trimmedName
            updatedTag.colorHex = selectedColor
            onSave(updatedTag)
        } else {
            // Create new tag
            let newOrder = allTags.map(\.order).max() ?? 0
            let newTag = Tag(
                name: trimmedName,
                colorHex: selectedColor,
                order: newOrder + 1
            )
            onSave(newTag)
        }
    }
}

// MARK: - Tag Color

private struct TagColor {
    let name: String
    let hex: String
}
