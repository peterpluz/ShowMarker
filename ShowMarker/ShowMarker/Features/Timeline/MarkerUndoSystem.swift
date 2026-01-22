import Foundation
import Combine

// MARK: - Undo/Redo System for Marker Operations

/// Protocol for undoable actions
protocol UndoableAction {
    func execute(in repository: ProjectRepository, timelineID: UUID)
    func undo(in repository: ProjectRepository, timelineID: UUID)
}

// MARK: - Add Marker Action

struct AddMarkerAction: UndoableAction {
    let marker: TimelineMarker

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

    private func updateState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
