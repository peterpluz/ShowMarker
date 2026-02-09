import SwiftUI

struct MarkerTagPopup: View {
    let tags: [Tag]
    let selectedTagId: UUID
    let onTagSelected: (UUID) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(tags) { tag in
                    tagRow(tag)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Теги")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func tagRow(_ tag: Tag) -> some View {
        HStack(spacing: 12) {
            // Checkbox circle — left side
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
                .font(.system(size: 17))
                .foregroundStyle(.primary)

            Spacer()

            // Color indicator — right side
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 24, height: 24)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            onTagSelected(tag.id)
        }
    }
}
