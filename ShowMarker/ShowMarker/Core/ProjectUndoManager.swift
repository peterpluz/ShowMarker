import Foundation

// MARK: - Project-Level Undo Actions

protocol ProjectUndoAction {
    func execute(in repository: ProjectRepository)
    func undo(in repository: ProjectRepository)
    var actionDescription: String { get }
    var timestamp: Date { get }
}

struct CreateTimelineAction: ProjectUndoAction {
    let timeline: Timeline
    let timestamp = Date()
    var actionDescription: String { "Создание \"\(timeline.name)\"" }

    func execute(in repository: ProjectRepository) {
        repository.addTimeline(timeline)
    }

    func undo(in repository: ProjectRepository) {
        repository.project.timelines.removeAll { $0.id == timeline.id }
    }
}

struct DeleteTimelineAction: ProjectUndoAction {
    let timeline: Timeline
    let index: Int
    let timestamp = Date()
    var actionDescription: String { "Удаление \"\(timeline.name)\"" }

    func execute(in repository: ProjectRepository) {
        repository.project.timelines.removeAll { $0.id == timeline.id }
    }

    func undo(in repository: ProjectRepository) {
        let safeIndex = min(index, repository.project.timelines.count)
        repository.project.timelines.insert(timeline, at: safeIndex)
    }
}

struct RenameTimelineAction: ProjectUndoAction {
    let timelineID: UUID
    let oldName: String
    let newName: String
    let timestamp = Date()
    var actionDescription: String { "Переименование \"\(oldName)\" → \"\(newName)\"" }

    func execute(in repository: ProjectRepository) {
        repository.renameTimeline(id: timelineID, newName: newName)
    }

    func undo(in repository: ProjectRepository) {
        repository.renameTimeline(id: timelineID, newName: oldName)
    }
}

struct DuplicateTimelineAction: ProjectUndoAction {
    let newTimeline: Timeline
    let timestamp = Date()
    var actionDescription: String { "Дублирование \"\(newTimeline.name)\"" }

    func execute(in repository: ProjectRepository) {
        repository.addTimeline(newTimeline)
    }

    func undo(in repository: ProjectRepository) {
        repository.project.timelines.removeAll { $0.id == newTimeline.id }
    }
}

// MARK: - Project Undo Manager

@MainActor
class ProjectUndoManager: ObservableObject {
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false

    private var undoStack: [ProjectUndoAction] = []
    private var redoStack: [ProjectUndoAction] = []
    private let maxStackSize: Int = 30

    private weak var repository: ProjectRepository?

    init(repository: ProjectRepository) {
        self.repository = repository
    }

    func performAction(_ action: ProjectUndoAction) {
        guard let repository = repository else { return }
        action.execute(in: repository)
        undoStack.append(action)
        if undoStack.count > maxStackSize {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        updateState()
    }

    func undo() {
        guard let repository = repository, !undoStack.isEmpty else { return }
        let action = undoStack.removeLast()
        action.undo(in: repository)
        redoStack.append(action)
        updateState()
    }

    func redo() {
        guard let repository = repository, !redoStack.isEmpty else { return }
        let action = redoStack.removeLast()
        action.execute(in: repository)
        undoStack.append(action)
        updateState()
    }

    private func updateState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
