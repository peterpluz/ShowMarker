import SwiftUI

struct ProjectView: View {

    @ObservedObject var document: ShowMarkerDocument

    @State private var isAddTimelinePresented = false
    @State private var newTimelineName = ""

    @State private var isRenamePresented = false
    @State private var renameTimelineName = ""
    @State private var timelineToRename: Timeline?

    var body: some View {
        List {
            if document.project.timelines.isEmpty {
                VStack(spacing: 8) {
                    Text("Нет таймлайнов")
                        .foregroundColor(.secondary)

                    Text("Начните с создания таймлайна")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(document.project.timelines) { timeline in
                    NavigationLink {
                        TimelineScreen(timeline: timeline)
                    } label: {
                        TimelineRow(title: timeline.name)
                    }
                    .contextMenu {
                        Button("Переименовать") {
                            timelineToRename = timeline
                            renameTimelineName = timeline.name
                            isRenamePresented = true
                        }
                    }
                }
                .onDelete { offsets in
                    document.removeTimelines(at: offsets)
                }
                .onMove { source, destination in
                    document.moveTimelines(from: source, to: destination)
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            EditButton()
        }

        // ✅ Кнопка закреплена корректно, без визуального разрыва в Dark Mode
        .safeAreaInset(edge: .bottom) {
            Button("Создать таймлайн") {
                newTimelineName = ""
                isAddTimelinePresented = true
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }

        // Создание таймлайна
        .alert("Новый таймлайн", isPresented: $isAddTimelinePresented) {
            TextField("Название", text: $newTimelineName)
            Button("Создать") {
                let name = newTimelineName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                document.addTimeline(name: name)
            }
            Button("Отмена", role: .cancel) {}
        }

        // Переименование таймлайна
        .alert("Переименовать таймлайн", isPresented: $isRenamePresented) {
            TextField("Название", text: $renameTimelineName)
            Button("Сохранить") {
                guard let timeline = timelineToRename else { return }
                let name = renameTimelineName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                document.renameTimeline(id: timeline.id, name: name)
            }
            Button("Отмена", role: .cancel) {}
        }
    }
}
