import Foundation
import Combine

// MARK: - Undo/Redo System for Marker Operations

/// Protocol for undoable actions
protocol UndoableAction {
    func execute(in repository: ProjectRepository, timelineID: UUID)
    func undo(in repository: ProjectRepository, timelineID: UUID)
    var actionDescription: String { get }
    var timestamp: Date { get }
}

// MARK: - Add Marker Action

struct AddMarkerAction: UndoableAction {
    let marker: TimelineMarker
    let timestamp: Date

    var actionDescription: String {
        "Добавить маркер '\(marker.name)'"
    }

    init(marker: TimelineMarker, timestamp: Date = Date()) {
        self.marker = marker
        self.timestamp = timestamp
    }

    func execute(in repository: ProjectRepository, timelineID: UUID) {
        repository.addMarker(timelineID: timelineID, marker: marker)
    }

    func undo(in repository: ProjectRepository, timelineID: UUID) {
        repository.removeMarker(timelineID: timelineID, markerID: marker.id)
    }
}

// MARK: - Delete Marker Action

struct DeleteMarkerAction: UndoableAction {
    let marker: TimelineMarker
    let timestamp: Date

    var actionDescription: String {
        "Удалить маркер '\(marker.name)'"
    }

    init(marker: TimelineMarker, timestamp: Date = Date()) {
        self.marker = marker
        self.timestamp = timestamp
    }

    func execute(in repository: ProjectRepository, timelineID: UUID) {
        repository.removeMarker(timelineID: timelineID, markerID: marker.id)
    }

    func undo(in repository: ProjectRepository, timelineID: UUID) {
        repository.addMarker(timelineID: timelineID, marker: marker)
    }
}

// MARK: - Rename Marker Action

struct RenameMarkerAction: UndoableAction {
    let markerID: UUID
    let oldName: String
    let newName: String
    let timestamp: Date

    var actionDescription: String {
        "Переименовать маркер '\(oldName)' → '\(newName)'"
    }

    init(markerID: UUID, oldName: String, newName: String, timestamp: Date = Date()) {
        self.markerID = markerID
        self.oldName = oldName
        self.newName = newName
        self.timestamp = timestamp
    }

    func execute(in repository: ProjectRepository, timelineID: UUID) {
        guard let timeline = repository.project.timelines.first(where: { $0.id == timelineID }),
              var marker = timeline.markers.first(where: { $0.id == markerID }) else {
            return
        }
        marker.name = newName
        repository.updateMarker(timelineID: timelineID, marker: marker)
    }

    func undo(in repository: ProjectRepository, timelineID: UUID) {
        guard let timeline = repository.project.timelines.first(where: { $0.id == timelineID }),
              var marker = timeline.markers.first(where: { $0.id == markerID }) else {
            return
        }
        marker.name = oldName
        repository.updateMarker(timelineID: timelineID, marker: marker)
    }
}

// MARK: - Change Marker Time Action

struct ChangeMarkerTimeAction: UndoableAction {
    let markerID: UUID
    let oldTime: Double
    let newTime: Double
    let timestamp: Date

    var actionDescription: String {
        "Переместить маркер"
    }

    init(markerID: UUID, oldTime: Double, newTime: Double, timestamp: Date = Date()) {
        self.markerID = markerID
        self.oldTime = oldTime
        self.newTime = newTime
        self.timestamp = timestamp
    }

    func execute(in repository: ProjectRepository, timelineID: UUID) {
        guard let timeline = repository.project.timelines.first(where: { $0.id == timelineID }),
              var marker = timeline.markers.first(where: { $0.id == markerID }) else {
            return
        }
        marker.timeSeconds = newTime
        repository.updateMarker(timelineID: timelineID, marker: marker)
    }

    func undo(in repository: ProjectRepository, timelineID: UUID) {
        guard let timeline = repository.project.timelines.first(where: { $0.id == timelineID }),
              var marker = timeline.markers.first(where: { $0.id == markerID }) else {
            return
        }
        marker.timeSeconds = oldTime
        repository.updateMarker(timelineID: timelineID, marker: marker)
    }
}

// MARK: - Change Marker Tag Action

struct ChangeMarkerTagAction: UndoableAction {
    let markerID: UUID
    let oldTagId: UUID
    let newTagId: UUID
    let timestamp: Date

    var actionDescription: String {
        "Изменить тег маркера"
    }

    init(markerID: UUID, oldTagId: UUID, newTagId: UUID, timestamp: Date = Date()) {
        self.markerID = markerID
        self.oldTagId = oldTagId
        self.newTagId = newTagId
        self.timestamp = timestamp
    }

    func execute(in repository: ProjectRepository, timelineID: UUID) {
        guard let timeline = repository.project.timelines.first(where: { $0.id == timelineID }),
              var marker = timeline.markers.first(where: { $0.id == markerID }) else {
            return
        }
        marker.tagId = newTagId
        repository.updateMarker(timelineID: timelineID, marker: marker)
    }

    func undo(in repository: ProjectRepository, timelineID: UUID) {
        guard let timeline = repository.project.timelines.first(where: { $0.id == timelineID }),
              var marker = timeline.markers.first(where: { $0.id == markerID }) else {
            return
        }
        marker.tagId = oldTagId
        repository.updateMarker(timelineID: timelineID, marker: marker)
    }
}

// MARK: - Delete All Markers Action

struct DeleteAllMarkersAction: UndoableAction {
    let markers: [TimelineMarker]
    let timestamp: Date

    var actionDescription: String {
        "Удалить все маркеры (\(markers.count))"
    }

    init(markers: [TimelineMarker], timestamp: Date = Date()) {
        self.markers = markers
        self.timestamp = timestamp
    }

    func execute(in repository: ProjectRepository, timelineID: UUID) {
        markers.forEach { marker in
            repository.removeMarker(timelineID: timelineID, markerID: marker.id)
        }
    }

    func undo(in repository: ProjectRepository, timelineID: UUID) {
        markers.forEach { marker in
            repository.addMarker(timelineID: timelineID, marker: marker)
        }
    }
}

// MARK: - Change Beat Grid Offset Action

struct ChangeBeatGridOffsetAction: UndoableAction {
    let oldOffset: Double
    let newOffset: Double
    let timestamp: Date

    var actionDescription: String {
        "Сместить сетку BPM"
    }

    init(oldOffset: Double, newOffset: Double, timestamp: Date = Date()) {
        self.oldOffset = oldOffset
        self.newOffset = newOffset
        self.timestamp = timestamp
    }

    func execute(in repository: ProjectRepository, timelineID: UUID) {
        guard let idx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        repository.project.timelines[idx].beatGridOffset = newOffset
    }

    func undo(in repository: ProjectRepository, timelineID: UUID) {
        guard let idx = repository.project.timelines.firstIndex(where: { $0.id == timelineID }) else { return }
        repository.project.timelines[idx].beatGridOffset = oldOffset
    }
}

// MARK: - History Item

struct HistoryItem {
    let description: String
    let timeAgo: String
}

// MARK: - Undo Manager

@MainActor
class MarkerUndoManager: ObservableObject {
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false

    private var undoStack: [UndoableAction] = []
    private var redoStack: [UndoableAction] = []
    private let maxStackSize: Int = 50

    private weak var repository: ProjectRepository?
    private var timelineID: UUID

    init(repository: ProjectRepository, timelineID: UUID) {
        self.repository = repository
        self.timelineID = timelineID
    }

    func performAction(_ action: UndoableAction) {
        guard let repository = repository else { return }

        action.execute(in: repository, timelineID: timelineID)
        undoStack.append(action)

        // Limit stack size
        if undoStack.count > maxStackSize {
            undoStack.removeFirst()
        }

        // Clear redo stack when new action is performed
        redoStack.removeAll()

        updateState()
    }

    func undo() {
        guard let repository = repository, !undoStack.isEmpty else { return }

        let action = undoStack.removeLast()
        action.undo(in: repository, timelineID: timelineID)
        redoStack.append(action)

        updateState()
    }

    func redo() {
        guard let repository = repository, !redoStack.isEmpty else { return }

        let action = redoStack.removeLast()
        action.execute(in: repository, timelineID: timelineID)
        undoStack.append(action)

        updateState()
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        updateState()
    }

    // MARK: - History Access

    private func formatTimeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            let seconds = Int(interval)
            return seconds == 1 ? "1 сек назад" : "\(seconds) сек назад"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return minutes == 1 ? "1 мин назад" : "\(minutes) мин назад"
        } else {
            let hours = Int(interval / 3600)
            return hours == 1 ? "1 ч назад" : "\(hours) ч назад"
        }
    }

    func getUndoHistory(limit: Int = 10) -> [HistoryItem] {
        return undoStack.suffix(limit).reversed().map { action in
            HistoryItem(
                description: action.actionDescription,
                timeAgo: formatTimeAgo(action.timestamp)
            )
        }
    }

    func getRedoHistory(limit: Int = 10) -> [HistoryItem] {
        return redoStack.suffix(limit).reversed().map { action in
            HistoryItem(
                description: action.actionDescription,
                timeAgo: formatTimeAgo(action.timestamp)
            )
        }
    }

    func undoToIndex(_ index: Int) {
        guard index < undoStack.count else { return }
        let count = undoStack.count - index - 1
        for _ in 0..<count {
            undo()
        }
    }

    func redoToIndex(_ index: Int) {
        guard index < redoStack.count else { return }
        let count = redoStack.count - index - 1
        for _ in 0..<count {
            redo()
        }
    }

    private func updateState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
