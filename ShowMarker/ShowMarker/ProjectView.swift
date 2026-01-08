import SwiftUI

struct ProjectView: View {

    @Binding var document: ShowMarkerDocument

    @State private var isAddTimelinePresented = false
    @State private var newTimelineName = ""

    @State private var isRenamePresented = false
    @State private var renameTimelineName = ""
    @State private var timelineToRename: Timeline?

    var body: some View {
        List {
            if document.file.project.timelines.isEmpty {
                emptyState
            } else {
                timelinesList
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
            Button("Создать", action: createTimeline)
            Button("Отмена", role: .cancel) {}
        }
        .alert("Переименовать таймлайн", isPresented: $isRenamePresented) {
            TextField("Название", text: $renameTimelineName)
            Button("Сохранить", action: renameTimeline)
            Button("Отмена", role: .cancel) {}
        }
    }

    // MARK: - Views

    private var emptyState: some View {
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
    }

    private var timelinesList: some View {
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
                Button("Переименовать") {
                    timelineToRename = timeline
                    renameTimelineName = timeline.name
                    isRenamePresented = true
                }
            }
        }
        .onDelete(perform: deleteTimelines)
        .onMove(perform: moveTimelines)
    }

    // MARK: - Actions

    private func createTimeline() {
        let name = newTimelineName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        document.file.project.timelines.append(
            Timeline(name: name)
        )

        newTimelineName = ""
    }

    private func renameTimeline() {
        guard
            let timeline = timelineToRename,
            let index = document.file.project.timelines.firstIndex(where: { $0.id == timeline.id })
        else { return }

        let name = renameTimelineName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        document.file.project.timelines[index].name = name
    }

    private func deleteTimelines(at offsets: IndexSet) {
        document.file.project.timelines.remove(atOffsets: offsets)
    }

    private func moveTimelines(from source: IndexSet, to destination: Int) {
        document.file.project.timelines.move(fromOffsets: source, toOffset: destination)
    }
}
