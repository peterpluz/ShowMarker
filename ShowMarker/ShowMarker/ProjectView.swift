import SwiftUI

struct ProjectView: View {

    @Binding var document: ShowMarkerDocument

    @State private var searchText = ""

    @State private var isAddTimelinePresented = false
    @State private var newTimelineName = ""

    @State private var renamingTimelineID: UUID?
    @State private var renameText = ""

    @State private var isEditing = false

    private let availableFPS = [25, 30, 50, 60, 100]

    private var isRenamingPresented: Binding<Bool> {
        Binding(
            get: { renamingTimelineID != nil },
            set: { if !$0 { renamingTimelineID = nil } }
        )
    }

    private var filteredTimelines: [Timeline] {
        let all = document.project.timelines
        guard !searchText.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        mainContent
            .navigationTitle(document.project.name)
            .environment(\.editMode, .constant(isEditing ? .active : .inactive))
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { bottomNotesStyleBar }
            .alert("Новый таймлайн", isPresented: $isAddTimelinePresented) {
                addTimelineAlert
            }
            .alert("Переименовать таймлайн", isPresented: isRenamingPresented) {
                renameTimelineAlert
            }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        List {
            if filteredTimelines.isEmpty {
                emptyState
            } else {
                timelineList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Нет таймлайнов")
                .foregroundColor(.secondary)
            Text("Создайте новый таймлайн")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowSeparator(.hidden)
    }

    private var timelineList: some View {
        ForEach(filteredTimelines) { timeline in
            timelineRow(timeline)
        }
        .onDelete { document.removeTimelines(at: $0) }
        .onMove { document.moveTimelines(from: $0, to: $1) }
    }

    private func timelineRow(_ timeline: Timeline) -> some View {
        NavigationLink {
            TimelineScreen(
                document: $document,
                timelineID: timeline.id
            )
        } label: {
            Text(timeline.name)
                .foregroundColor(.primary)
                .padding(.vertical, 6)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            timelineSwipeActions(timeline)
        }
        .contextMenu {
            timelineContextMenu(timeline)
        }
    }

    @ViewBuilder
    private func timelineSwipeActions(_ timeline: Timeline) -> some View {
        Button(role: .destructive) {
            deleteTimeline(timeline)
        } label: {
            Label("Удалить", systemImage: "trash")
        }

        Button {
            startRename(timeline)
        } label: {
            Label("Переименовать", systemImage: "pencil")
        }
        .tint(.blue)
    }

    @ViewBuilder
    private func timelineContextMenu(_ timeline: Timeline) -> some View {
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

    // MARK: - Alerts

    private var addTimelineAlert: some View {
        Group {
            TextField("Название", text: $newTimelineName)
            Button("Создать") {
                let name = newTimelineName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                document.addTimeline(name: name)
                newTimelineName = ""
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var renameTimelineAlert: some View {
        Group {
            TextField("Название", text: $renameText)
            Button("Готово") { applyRename() }
            Button("Отмена", role: .cancel) {
                renamingTimelineID = nil
            }
        }
    }

    // MARK: - Toolbar

    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    isEditing.toggle()
                } label: {
                    Label(
                        isEditing ? "Done" : "Edit",
                        systemImage: "list.bullet"
                    )
                }

                Divider()

                fpsMenu

            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .semibold))
            }
        }
    }

    private var fpsMenu: some View {
        Menu {
            ForEach(availableFPS, id: \.self) { value in
                Button {
                    document.setProjectFPS(value)
                } label: {
                    if document.project.fps == value {
                        Label("\(value) FPS", systemImage: "checkmark")
                    } else {
                        Text("\(value) FPS")
                    }
                }
            }
        } label: {
            Label(
                "FPS (\(document.project.fps))",
                systemImage: "speedometer"
            )
        }
    }

    // MARK: - Bottom bar

    private var bottomNotesStyleBar: some View {
        HStack(spacing: 12) {
            searchBar
            addButton
        }
        .padding(16)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Поиск", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(
            Capsule()
                .fill(.regularMaterial)
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var addButton: some View {
        Button {
            isAddTimelinePresented = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                )
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
            let index = document.project.timelines.firstIndex(where: { $0.id == id })
        else {
            renamingTimelineID = nil
            return
        }

        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            renamingTimelineID = nil
            return
        }

        document.project.timelines[index].name = name
        renamingTimelineID = nil
    }

    private func deleteTimeline(_ timeline: Timeline) {
        guard let index = document.project.timelines.firstIndex(where: { $0.id == timeline.id }) else { return }
        document.project.timelines.remove(at: index)
    }
}
