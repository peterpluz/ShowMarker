import SwiftUI

struct TagFilterView: View {
    let tags: [Tag]
    @Binding var selectedTagIds: Set<UUID>
    let onClose: () -> Void

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(tags) { tag in
                        Button {
                            toggleTag(tag.id)
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

                                // Checkmark for selected tags
                                if selectedTagIds.contains(tag.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                        .font(.system(size: 17, weight: .semibold))
                                }
                            }
                        }
                    }
                } header: {
                    Text("Выберите теги для отображения")
                }
            }
            .navigationTitle("Фильтр тегов")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        selectAll()
                    } label: {
                        Text("Все")
                    }
                    .disabled(selectedTagIds.count == tags.count)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        onClose()
                    }
                }
            }
        }
    }

    private func toggleTag(_ tagId: UUID) {
        if selectedTagIds.contains(tagId) {
            selectedTagIds.remove(tagId)
        } else {
            selectedTagIds.insert(tagId)
        }
    }

    private func selectAll() {
        selectedTagIds = Set(tags.map(\.id))
    }
}
