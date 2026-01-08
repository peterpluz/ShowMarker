import SwiftUI

struct ProjectView: View {

    @ObservedObject var document: ShowMarkerDocument

    @State private var isAddTimelinePresented = false
    @State private var newTimelineName = ""

    @State private var isRenamePresented = false
    @State private var renameTimelineName = ""
    @State private var timelineToRename: Timeline?

    var body: some View {
        VStack(spacing: 24) {

            Spacer()

            if document.project.timelines.isEmpty {
                VStack(spacing: 8) {
                    Text("Нет таймлайнов")
                        .foregroundColor(.secondary)
                    Text("Начните с создания таймлайна")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else {
                List {
                    ForEach(document.project.timelines) { timeline in
                        NavigationLink {
                            TimelineScreen(timeline: timeline)
                        } label: {
                            Text(timeline.name)
                        }
                        .contextMenu {
                            Button(
                                action: {
                                    timelineToRename = timeline
                                    renameTimelineName = timeline.name
                                    isRenamePresented = true
                                },
                                label: {
                                    Text("Переименовать")
                                }
                            )
                        }
                    }
                    .onDelete { offsets in
                        document.removeTimelines(at: offsets)
                    }
                    .onMove { source, destination in
                        document.moveTimelines(from: source, to: destination)
                    }
                }
                .toolbar {
                    EditButton()
                }
            }

            Spacer()

            Button("Создать таймлайн") {
                newTimelineName = ""
                isAddTimelinePresented = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()

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
