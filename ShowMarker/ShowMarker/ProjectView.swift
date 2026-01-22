import SwiftUI

struct ProjectView: View {

    @Binding var document: ShowMarkerDocument
    
    // ✅ ИСПРАВЛЕНО: ObservedObject для nonisolated repository
    @ObservedObject private var repository: ProjectRepository

    @State private var searchText = ""

    @State private var isAddTimelinePresented = false
    @State private var newTimelineName = ""

    @State private var renamingTimelineID: UUID?
    @State private var renameText = ""

    @State private var isEditing = false
    @State private var isProjectSettingsPresented = false
    @State private var selectedTimelines: Set<UUID> = []

    private let availableFPS = [25, 30, 50, 60, 100]

    init(document: Binding<ShowMarkerDocument>) {
        _document = document
        // ✅ КРИТИЧНО: безопасное извлечение repository
        _repository = ObservedObject(wrappedValue: document.wrappedValue.repository)
    }

    private var isRenamingPresented: Binding<Bool> {
        Binding(
            get: { renamingTimelineID != nil },
            set: { if !$0 { renamingTimelineID = nil } }
        )
    }

    private var filteredTimelines: [Timeline] {
        let all = repository.project.timelines
        guard !searchText.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        mainContent
            .navigationTitle(repository.project.name)
            .environment(\.editMode, .constant(isEditing ? .active : .inactive))
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { bottomNotesStyleBar }
            .onChange(of: isEditing) { oldValue, newValue in
                if !newValue {
                    selectedTimelines.removeAll()
                }
            }
            .alert("Новый таймлайн", isPresented: $isAddTimelinePresented) {
                addTimelineAlert
            }
            .alert("Переименовать таймлайн", isPresented: isRenamingPresented) {
                renameTimelineAlert
            }
            .sheet(isPresented: $isProjectSettingsPresented) {
                ProjectSettingsView(repository: repository)
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
    }

    private func timelineRow(_ timeline: Timeline) -> some View {
        Group {
            if isEditing {
                // Selection mode with checkbox
                Button {
                    toggleSelection(timeline.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedTimelines.contains(timeline.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundColor(selectedTimelines.contains(timeline.id) ? .accentColor : .secondary)

                        Text(timeline.name)
                            .foregroundColor(.primary)
                            .padding(.vertical, 6)

                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            } else {
                // Normal mode with NavigationLink
                NavigationLink {
                    TimelineScreen(
                        repository: repository,
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
                repository.addTimeline(name: name)
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
        Group {
            // Checkmark button (left)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isEditing.toggle()
                } label: {
                    Image(systemName: isEditing ? "checkmark" : "checkmark.circle")
                        .font(.system(size: 20, weight: .semibold))
                }
            }

            // Settings button (right - will appear after checkmark)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isProjectSettingsPresented = true
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 20, weight: .semibold))
                }
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomNotesStyleBar: some View {
        HStack(spacing: 12) {
            if isEditing {
                deleteSelectedButton
            } else {
                searchBar
                addButton
            }
        }
        .padding(16)
    }

    private var deleteSelectedButton: some View {
        Button {
            deleteSelectedTimelines()
        } label: {
            HStack {
                Image(systemName: "trash")
                    .font(.system(size: 20, weight: .semibold))
                Text("Удалить (\(selectedTimelines.count))")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                Capsule()
                    .fill(selectedTimelines.isEmpty ? Color.gray : Color.red)
            )
        }
        .disabled(selectedTimelines.isEmpty)
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

    private func toggleSelection(_ timelineID: UUID) {
        if selectedTimelines.contains(timelineID) {
            selectedTimelines.remove(timelineID)
        } else {
            selectedTimelines.insert(timelineID)
        }
    }

    private func deleteSelectedTimelines() {
        let indices = IndexSet(
            selectedTimelines.compactMap { id in
                repository.project.timelines.firstIndex(where: { $0.id == id })
            }
        )
        repository.removeTimelines(at: indices)
        selectedTimelines.removeAll()
        isEditing = false
    }

    private func startRename(_ timeline: Timeline) {
        renamingTimelineID = timeline.id
        renameText = timeline.name
    }

    private func applyRename() {
        guard let id = renamingTimelineID else {
            return
        }

        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            renamingTimelineID = nil
            return
        }

        repository.renameTimeline(id: id, newName: name)
        renamingTimelineID = nil
    }

    private func deleteTimeline(_ timeline: Timeline) {
        guard let index = repository.project.timelines.firstIndex(where: { $0.id == timeline.id }) else { return }
        repository.removeTimelines(at: IndexSet(integer: index))
    }
}
