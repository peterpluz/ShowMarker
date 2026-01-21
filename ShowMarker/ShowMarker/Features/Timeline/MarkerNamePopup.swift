import SwiftUI

struct MarkerNamePopup: View {
    @Environment(\.dismiss) private var dismiss

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
        NavigationView {
            VStack(spacing: 24) {
                // Title
                Text("Название маркера")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.top, 20)

                // Text field with clear button
                HStack(spacing: 12) {
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
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                // Buttons
                HStack(spacing: 12) {
                    // Cancel button
                    Button {
                        onCancel()
                        dismiss()
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
                        dismiss()
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
                .padding(.bottom, 20)
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            // Auto-focus text field when popup appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }
}
