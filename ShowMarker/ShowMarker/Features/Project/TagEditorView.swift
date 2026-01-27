import SwiftUI

struct TagEditorView: View {
    let tag: Tag?  // nil = creating new tag
    let allTags: [Tag]
    let onSave: (Tag) -> Void
    let onCancel: () -> Void

    @State private var tagName: String
    @State private var selectedColor: String
    @FocusState private var isTextFieldFocused: Bool

    // Apple's standard accent colors (9 colors)
    private let colorPalette: [TagColor] = [
        TagColor(name: "Красный", hex: "#FF3B30"),
        TagColor(name: "Оранжевый", hex: "#FF9500"),
        TagColor(name: "Желтый", hex: "#FFCC00"),
        TagColor(name: "Зеленый", hex: "#34C759"),
        TagColor(name: "Мятный", hex: "#00C7BE"),
        TagColor(name: "Синий", hex: "#007AFF"),
        TagColor(name: "Индиго", hex: "#5856D6"),
        TagColor(name: "Фиолетовый", hex: "#AF52DE"),
        TagColor(name: "Розовый", hex: "#FF2D55")
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
            // Dimmed background with blur
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            // Popup content with Liquid Glass style
            VStack(spacing: 20) {
                // Title
                Text(isEditing ? "Редактировать тег" : "Новый тег")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.top, 24)

                // Text field with darker Liquid Glass style
                HStack(spacing: 0) {
                    TextField("Название тега", text: $tagName)
                        .font(.system(size: 16, weight: .regular))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .focused($isTextFieldFocused)

                    // Clear button inside field
                    if !tagName.isEmpty {
                        Button {
                            tagName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color(.tertiaryLabel))
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .padding(.trailing, 8)
                    }
                }
                .background(
                    Capsule()
                        .fill(Color(.systemGray5).opacity(0.6))
                        .background(
                            Capsule()
                                .fill(.regularMaterial)
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
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
                                    // Haptic feedback on color selection
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                    selectedColor = colorOption.hex
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: colorOption.hex))
                                            .frame(width: 32, height: 32)

                                        if selectedColor == colorOption.hex {
                                            Circle()
                                                .strokeBorder(Color.primary, lineWidth: 2.5)
                                                .frame(width: 36, height: 36)
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

                // Buttons with Liquid Glass style
                HStack(spacing: 12) {
                    // Cancel button
                    Button {
                        onCancel()
                    } label: {
                        Text("Отмена")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                Capsule()
                                    .fill(Color(.systemGray5).opacity(0.6))
                                    .background(
                                        Capsule()
                                            .fill(.regularMaterial)
                                    )
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)

                    // Save button
                    Button {
                        saveTag()
                    } label: {
                        Text(isEditing ? "Сохранить" : "Создать")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                Capsule()
                                    .fill(tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(.systemGray6).opacity(0.9))
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.ultraThickMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: 10)
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
