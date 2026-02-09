import SwiftUI

struct MarkerTagPopup: View {
    let tags: [Tag]
    let selectedTagId: UUID
    let onTagSelected: (UUID) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            // Dimmed backdrop — lighter than before to let glass refraction show
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            // Floating glass sheet
            VStack(spacing: 0) {
                // Title
                Text("Выбрать тег")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                // Tag rows — clean list with dividers
                VStack(spacing: 0) {
                    ForEach(Array(tags.enumerated()), id: \.element.id) { index, tag in
                        let isSelected = selectedTagId == tag.id

                        Button {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            onTagSelected(tag.id)
                        } label: {
                            HStack(spacing: 14) {
                                // Glass-tinted color dot with glow
                                Circle()
                                    .fill(Color(hex: tag.colorHex).opacity(0.9))
                                    .frame(width: 12, height: 12)
                                    .shadow(
                                        color: Color(hex: tag.colorHex).opacity(0.5),
                                        radius: 4, x: 0, y: 0
                                    )

                                // Tag name — primary with subtle tint
                                Text(tag.name)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(.primary)

                                Spacer()

                                // Selection: subtle checkmark
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color(hex: tag.colorHex))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(hex: tag.colorHex).opacity(0.1))
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        // Divider between rows
                        if index < tags.count - 1 {
                            Divider()
                                .padding(.leading, 42)
                                .padding(.trailing, 16)
                        }
                    }
                }
                .padding(.horizontal, 8)

                // Cancel button — glass capsule
                Button {
                    onCancel()
                } label: {
                    Text("Отмена")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            .frame(width: 320)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
