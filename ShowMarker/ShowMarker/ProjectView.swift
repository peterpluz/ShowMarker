import SwiftUI

struct ProjectView: View {

    @Binding var document: ShowMarkerDocument

    @State private var isAddTimelinePresented = false
    @State private var newTimelineName = ""

    @State private var renamingTimelineID: UUID?
    @State private var renameText: String = ""

    private var isRenamingPresented: Binding<Bool> {
        Binding(
            get: { renamingTimelineID != nil },
            set: { if !$0 { renamingTimelineID = nil } }
        )
    }

    var body: some View {
        List {
            if document.file.project.timelines.isEmpty {
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
            } else {
                ForEach(document.file.project.timelines) { timeline in
                    NavigationLink {
                        TimelineScreen(
                            document: $document,
                            timelineID: timeline.id
                        )
                    } label: {
                        TimelineRow(title: timeline.name)
                    }
                    .contextMenu {
                        Button {
                            startRename(timeline)
                        } label: {
                            Label("Переименовать", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            deleteTimeline(timeline)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {

                        // СЛЕВА
                        Button(role: .destructive) {
                            deleteTimeline(timeline)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }

                        // КРАЙНЯЯ СПРАВА
                        Button {
                            startRename(timeline)
                        } label: {
                            Label("Переименовать", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
                .onDelete { offsets in
                    document.removeTimelines(at: offsets)
                }
                .onMove { from, to in
                    document.moveTimelines(from: from, to: to)
                }
            }
        }
        .toolbar { EditButton() }
        .safeAreaInset(edge: .bottom) {
            Button {
                isAddTimelinePresented = true
            } label: {
                Text("Создать таймлайн")
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .alert("Новый таймлайн", isPresented: $isAddTimelinePresented) {
            TextField("Название", text: $newTimelineName)
            Button("Создать") {
                let name = newTimelineName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                document.addTimeline(name: name)
                newTimelineName = ""
            }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Переименовать таймлайн", isPresented: isRenamingPresented) {
            TextField("Название", text: $renameText)
            Button("Готово") {
                applyRename()
            }
            Button("Отмена", role: .cancel) {
                renamingTimelineID = nil
            }
        }
    }

    // MARK: - Helpers

    private func startRename(_ timeline: Timeline) {
        renamingTimelineID = timeline.id
        renameText = timeline.name
    }

    private func applyRename() {
        guard
            let id = renamingTimelineID,
            let index = document.file.project.timelines.firstIndex(where: { $0.id == id })
        else {
            renamingTimelineID = nil
            return
        }

        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            renamingTimelineID = nil
            return
        }

        document.file.project.timelines[index].name = name
        renamingTimelineID = nil
    }

    private func deleteTimeline(_ timeline: Timeline) {
        guard let index = document.file.project.timelines.firstIndex(where: { $0.id == timeline.id }) else { return }
        document.file.project.timelines.remove(at: index)
    }
}
