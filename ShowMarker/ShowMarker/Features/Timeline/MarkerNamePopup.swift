import SwiftUI

struct MarkerNamePopup: View {
    let defaultName: String
    let tags: [Tag]
    let defaultTagId: UUID
    let onSave: (String, UUID) -> Void
    let onCancel: () -> Void

    @State private var markerName: String
    @State private var selectedTagId: UUID
    @State private var showTagPicker = false
    @FocusState private var isTextFieldFocused: Bool

    init(
        defaultName: String,
        tags: [Tag],
        defaultTagId: UUID,
        onSave: @escaping (String, UUID) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.defaultName = defaultName
        self.tags = tags
        self.defaultTagId = defaultTagId
        self.onSave = onSave
        self.onCancel = onCancel
        _markerName = State(initialValue: defaultName)
        _selectedTagId = State(initialValue: defaultTagId)
    }

    private var selectedTag: Tag? {
        tags.first(where: { $0.id == selectedTagId })
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
                Text("Название маркера")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.top, 24)

                // Text field with Liquid Glass style
                HStack(spacing: 8) {
                    TextField("", text: $markerName)
                        .font(.system(size: 16, weight: .regular))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color(.systemGray6).opacity(0.4))
                                .background(
                                    Capsule()
                                        .fill(.ultraThickMaterial)
                                )
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                        .focused($isTextFieldFocused)

                    // Clear button
                    if !markerName.isEmpty {
                        Button {
                            markerName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color(.tertiaryLabel))
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .padding(.trailing, 4)
                    }
                }
                .padding(.horizontal, 16)

                // Tag selector with Liquid Glass style
                Button {
                    showTagPicker = true
                } label: {
                    HStack {
                        Text("Тег")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.primary)

                        Spacer()

                        if let tag = selectedTag {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: tag.colorHex))
                                    .frame(width: 14, height: 14)

                                Text(tag.name)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(Color(hex: tag.colorHex))

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color(.systemGray6).opacity(0.4))
                            .background(
                                Capsule()
                                    .fill(.ultraThickMaterial)
                            )
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

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
                                    .fill(Color(.systemGray6).opacity(0.4))
                                    .background(
                                        Capsule()
                                            .fill(.ultraThickMaterial)
                                    )
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)

                    // Save button
                    Button {
                        let finalName = markerName.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(finalName.isEmpty ? defaultName : finalName, selectedTagId)
                    } label: {
                        Text("Сохранить")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.8))
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
        .sheet(isPresented: $showTagPicker) {
            TagPickerView(
                tags: tags,
                selectedTagId: selectedTagId,
                onSelect: { tagId in
                    selectedTagId = tagId
                    showTagPicker = false
                },
                onCancel: {
                    showTagPicker = false
                }
            )
        }
    }
}
