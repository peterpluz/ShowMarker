import SwiftUI

struct MarkerNamePopup: View {
    let defaultName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var markerName: String
    @FocusState private var isTextFieldFocused: Bool

    init(
        defaultName: String,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.defaultName = defaultName
        self.onSave = onSave
        self.onCancel = onCancel
        _markerName = State(initialValue: defaultName)
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            // Popup content
            VStack(spacing: 20) {
                // Title
                Text("Название маркера")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.top, 24)

                // Text field with clear button
                HStack(spacing: 8) {
                    TextField("", text: $markerName)
                        .font(.system(size: 17))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemGray5))
                        )
                        .focused($isTextFieldFocused)

                    // Clear button
                    if !markerName.isEmpty {
                        Button {
                            markerName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .font(.system(size: 20))
                        }
                        .padding(.trailing, 4)
                    }
                }
                .padding(.horizontal, 20)

                // Buttons
                HStack(spacing: 12) {
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
                                Capsule().fill(Color(.systemGray5))
                            )
                    }

                    // Save button
                    Button {
                        let finalName = markerName.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(finalName.isEmpty ? defaultName : finalName)
                    } label: {
                        Text("Сохранить")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                Capsule().fill(Color.accentColor)
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .frame(width: 340)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
            )
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        }
        .onAppear {
            // Auto-focus text field when popup appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }
}
