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
                            .font(.system(size: 24))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func tagRow(_ tag: Tag) -> some View {
        HStack {
            Text(tag.name)
                .font(.system(size: 17))
                .foregroundStyle(.primary)

            Spacer()

            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 24, height: 24)

            if tag.id == selectedTagId {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            onTagSelected(tag.id)
        }
    }
}
