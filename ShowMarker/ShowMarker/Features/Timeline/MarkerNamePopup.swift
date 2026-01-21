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
            // Dimmed background with blur effect (iOS style)
            Color.black.opacity(0.25)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            // Popup content
            VStack(spacing: 16) {
                // Title
                Text("Название маркера")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.top, 20)

                // Text field with clear button
                HStack(spacing: 8) {
                    TextField("", text: $markerName)
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
                    if !markerName.isEmpty {
                        Button {
                            markerName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color(.tertiaryLabel))
                                .font(.system(size: 20))
                        }
                        .padding(.trailing, 4)
                    }
                }
                .padding(.horizontal, 16)

                // Tag selector
                Button {
                    showTagPicker = true
                } label: {
                    HStack {
                        Text("Тег")
                            .font(.system(size: 17))
                            .foregroundColor(.primary)

                        Spacer()

                        if let tag = selectedTag {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: tag.colorHex))
                                    .frame(width: 16, height: 16)

                                Text(tag.name)
                                    .font(.system(size: 17))
                                    .foregroundColor(Color(hex: tag.colorHex))

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

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
                        let finalName = markerName.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(finalName.isEmpty ? defaultName : finalName, selectedTagId)
                    } label: {
                        Text("Сохранить")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
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
