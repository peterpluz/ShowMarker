import SwiftUI

struct MarkerTagPopup: View {
    let tags: [Tag]
    let selectedTagId: UUID
    let onTagSelected: (UUID) -> Void
    let onCancel: () -> Void

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
                Text("Выбрать тег")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.top, 24)

                // Tag selector with Liquid Glass style
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(tags) { tag in
                        Button {
                            onTagSelected(tag.id)
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: tag.colorHex))
                                    .frame(width: 16, height: 16)

                                Text(tag.name)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(Color(hex: tag.colorHex))

                                Spacer()

                                if selectedTagId == tag.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color(hex: tag.colorHex))
                                        .font(.system(size: 20, weight: .semibold))
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
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
                    }
                }
                .padding(.horizontal, 16)

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
}
