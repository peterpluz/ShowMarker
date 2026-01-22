import SwiftUI

struct TagPickerView: View {
    let tags: [Tag]
    let selectedTagId: UUID
    let onSelect: (UUID) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            List {
                ForEach(tags) { tag in
                    Button {
                        onSelect(tag.id)
                    } label: {
                        HStack(spacing: 12) {
                            // Color circle
                            Circle()
                                .fill(Color(hex: tag.colorHex))
                                .frame(width: 14, height: 14)

                            // Tag name
                            Text(tag.name)
                                .font(.system(size: 17))
                                .foregroundColor(.primary)

                            Spacer()

                            // Checkmark for selected tag
                            if tag.id == selectedTagId {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Выбрать тег")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") {
                        onCancel()
                    }
                }
            }
        }
    }
}
