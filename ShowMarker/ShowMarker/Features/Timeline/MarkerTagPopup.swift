import SwiftUI

struct MarkerTagPopup: View {
    let tags: [Tag]
    let selectedTagId: UUID
    let onTagSelected: (UUID) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            // Popup content with Liquid Glass style
            VStack(spacing: 16) {
                // Title
                Text("Теги")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.top, 24)

                // Tag list
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(tags) { tag in
                            tagRow(tag)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(maxHeight: 320)

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
    }

    private func tagRow(_ tag: Tag) -> some View {
        HStack(spacing: 12) {
            // Checkbox circle
            if tag.id == selectedTagId {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
            } else {
                Circle()
                    .stroke(Color(.tertiaryLabel), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
            }

            // Tag name
            Text(tag.name)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.primary)

            Spacer()

            // Color indicator
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(tag.id == selectedTagId
                      ? Color(.systemGray4).opacity(0.5)
                      : Color(.systemGray5).opacity(0.3))
                .background(
                    Capsule()
                        .fill(.regularMaterial)
                )
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .contentShape(Capsule())
        .onTapGesture {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            onTagSelected(tag.id)
        }
    }
}
