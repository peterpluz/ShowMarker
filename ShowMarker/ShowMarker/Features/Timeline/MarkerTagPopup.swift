import SwiftUI

struct MarkerTagPopup: View {
    let tags: [Tag]
    let selectedTagId: UUID
    let onTagSelected: (UUID) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            // Dimmed background — full screen uniform
            Color.black.opacity(0.35)
                .ignoresSafeArea(.all)
                .onTapGesture {
                    onCancel()
                }

            // Popup card — translucent glass
            VStack(spacing: 0) {
                // Title
                Text("Теги")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.top, 20)
                    .padding(.bottom, 14)

                // Tag list
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(tags) { tag in
                            tagRow(tag)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxHeight: 300)

                // Divider
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                // Cancel button
                Button {
                    onCancel()
                } label: {
                    Text("Отмена")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(width: 300)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 40, x: 0, y: 12)
        }
    }

    private func tagRow(_ tag: Tag) -> some View {
        let isSelected = tag.id == selectedTagId

        return HStack(spacing: 10) {
            // Color dot — subtle, small
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 10, height: 10)
                .opacity(isSelected ? 1.0 : 0.55)

            // Tag name
            Text(tag.name)
                .font(.system(size: 16, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)

            Spacer()

            // Checkmark for selected
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: tag.colorHex))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected
                      ? Color.primary.opacity(0.06)
                      : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            onTagSelected(tag.id)
        }
    }
}
