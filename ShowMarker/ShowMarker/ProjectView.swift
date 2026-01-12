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
        let all = document.file.project.timelines
        guard !searchText.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if filteredTimelines.isEmpty {
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
            } else {
                ForEach(filteredTimelines) { timeline in
                    NavigationLink {
                        TimelineScreen(
                            document: $document,
                            timelineID: timeline.id
                        )
                    } label: {
                        TimelineRow(title: timeline.name)
                    }
                    // ===== SWIPE ACTIONS =====
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {

                        // Delete — САМАЯ ПРАВАЯ
                        Button(role: .destructive) {
                            deleteTimeline(timeline)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }

                        // Rename — левее delete
                        Button {
                            startRename(timeline)
                        } label: {
                            Label("Переименовать", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    // ===== CONTEXT MENU (оставляем) =====
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
                }
                .onDelete { document.removeTimelines(at: $0) }
                .onMove { document.moveTimelines(from: $0, to: $1) }
            }
        }
        .navigationTitle(document.file.project.name)
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        .toolbar {

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

                    Menu {
                        ForEach(availableFPS, id: \.self) { value in
                            Button {
                                document.setProjectFPS(value)
                            } label: {
                                if document.file.project.fps == value {
                                    Label("\(value) FPS", systemImage: "checkmark")
                                } else {
                                    Text("\(value) FPS")
                                }
                            }
                        }
                    } label: {
                        Label(
                            "FPS (\(document.file.project.fps))",
                            systemImage: "speedometer"
                        )
                    }

                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomNotesStyleBar
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
            Button("Готово") { applyRename() }
            Button("Отмена", role: .cancel) {
                renamingTimelineID = nil
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomNotesStyleBar: some View {
        HStack(spacing: 12) {

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Поиск", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                Image(systemName: "mic.fill")
                    .foregroundColor(.secondary)
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
        .padding(16)
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
