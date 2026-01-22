import Foundation
import SwiftUI
import UniformTypeIdentifiers

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

    // Export states
    @State private var csvExportData: Data?
    @State private var zipExportData: Data?
    @State private var isCSVExportPresented = false
    @State private var isZIPExportPresented = false
    @State private var exportFilename = ""

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
            .fileExporter(
                isPresented: $isCSVExportPresented,
                document: SimpleCSVDocument(data: csvExportData ?? Data()),
                contentType: .commaSeparatedText,
                defaultFilename: exportFilename
            ) { result in
                switch result {
                case .success:
                    print("CSV export successful")
                case .failure(let error):
                    print("CSV export failed: \(error.localizedDescription)")
                }
            }
            .fileExporter(
                isPresented: $isZIPExportPresented,
                document: SimpleZIPDocument(data: zipExportData ?? Data()),
                contentType: .zip,
                defaultFilename: exportFilename
            ) { result in
                switch result {
                case .success:
                    print("ZIP export successful")
                case .failure(let error):
                    print("ZIP export failed: \(error.localizedDescription)")
                }
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
        .onMove { fromOffsets, toOffset in
            repository.moveTimelines(from: fromOffsets, to: toOffset)
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
            if isEditing {
                // Select all button (left)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        selectAllTimelines()
                    } label: {
                        Text("Выбрать все")
                            .font(.system(size: 17))
                    }
                }

                // Selection count (center)
                ToolbarItem(placement: .principal) {
                    Text("\(selectedTimelines.count) объекта")
                        .font(.system(size: 17, weight: .semibold))
                }

                // Done button (right)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isEditing = false
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.accentColor))
                    }
                }

                // Settings button (always visible)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isProjectSettingsPresented = true
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 20, weight: .semibold))
                    }
                }
            } else {
                // Menu with select option
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            isEditing = true
                        } label: {
                            Label("Выбрать", systemImage: "checkmark.circle")
                        }

                        Button {
                            exportAllTimelines()
                        } label: {
                            Label("Экспорт CSV всех таймлайнов", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20, weight: .semibold))
                    }
                }

                // Settings button (right)
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
    }

    // MARK: - Bottom bar

    private var bottomNotesStyleBar: some View {
        HStack(spacing: 12) {
            if isEditing {
                editingBottomBar
            } else {
                searchBar
                addButton
            }
        }
        .padding(16)
    }

    private var editingBottomBar: some View {
        HStack(spacing: 16) {
            // Share button
            Button {
                exportSelectedTimelines()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(selectedTimelines.isEmpty ? .secondary : .accentColor)
                    .frame(width: 44, height: 44)
            }
            .disabled(selectedTimelines.isEmpty)

            // Duplicate button
            Button {
                duplicateSelectedTimelines()
            } label: {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(selectedTimelines.isEmpty ? .secondary : .accentColor)
                    .frame(width: 44, height: 44)
            }
            .disabled(selectedTimelines.isEmpty)

            Spacer()

            // Delete button
            Button {
                deleteSelectedTimelines()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(selectedTimelines.isEmpty ? .secondary : .red)
                    .frame(width: 44, height: 44)
            }
            .disabled(selectedTimelines.isEmpty)
        }
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

    private func selectAllTimelines() {
        selectedTimelines = Set(filteredTimelines.map(\.id))
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

    private func duplicateSelectedTimelines() {
        for timelineID in selectedTimelines {
            guard let timeline = repository.project.timelines.first(where: { $0.id == timelineID }) else {
                continue
            }

            let duplicateName = "\(timeline.name) Copy"
            let newTimeline = Timeline(
                name: duplicateName,
                audio: timeline.audio,
                fps: timeline.fps,
                markers: timeline.markers.map { marker in
                    TimelineMarker(
                        timeSeconds: marker.timeSeconds,
                        name: marker.name,
                        tagId: marker.tagId
                    )
                }
            )

            repository.addTimeline(newTimeline)
        }

        selectedTimelines.removeAll()
        isEditing = false
    }

    private func exportSelectedTimelines() {
        let selectedTimelineObjects = repository.project.timelines.filter { selectedTimelines.contains($0.id) }

        if selectedTimelineObjects.count == 1 {
            // Single timeline - export as CSV
            if let timeline = selectedTimelineObjects.first {
                csvExportData = generateCSV(for: timeline)
                exportFilename = "\(timeline.name).csv"
                isCSVExportPresented = true
            }
        } else if selectedTimelineObjects.count > 1 {
            // Multiple timelines - export as ZIP
            if let zipData = generateZIP(for: selectedTimelineObjects) {
                zipExportData = zipData
                exportFilename = "SelectedTimelines.zip"
                isZIPExportPresented = true
            }
        }
    }

    private func exportAllTimelines() {
        let allTimelines = repository.project.timelines

        if allTimelines.count == 1 {
            if let timeline = allTimelines.first {
                csvExportData = generateCSV(for: timeline)
                exportFilename = "\(timeline.name).csv"
                isCSVExportPresented = true
            }
        } else if allTimelines.count > 1 {
            if let zipData = generateZIP(for: allTimelines) {
                zipExportData = zipData
                exportFilename = "\(repository.project.name)_AllTimelines.zip"
                isZIPExportPresented = true
            }
        }
    }

    private func generateCSV(for timeline: Timeline) -> Data {
        let csv = MarkersCSVExporter.export(
            markers: timeline.markers,
            frameRate: Double(repository.project.fps)
        )
        return csv.data(using: .utf8) ?? Data()
    }

    private func generateZIP(for timelines: [Timeline]) -> Data? {
        // Generate separate CSV file for each timeline and pack into ZIP
        var csvFiles: [(name: String, data: Data)] = []

        for timeline in timelines {
            let csv = MarkersCSVExporter.export(
                markers: timeline.markers,
                frameRate: Double(repository.project.fps)
            )

            if let csvData = csv.data(using: .utf8) {
                // Sanitize timeline name for filename
                let sanitizedName = timeline.name
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                let filename = "\(sanitizedName).csv"
                csvFiles.append((name: filename, data: csvData))
            }
        }

        return createZIPArchive(files: csvFiles)
    }

    private func createZIPArchive(files: [(name: String, data: Data)]) -> Data? {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let zipPath = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Write all CSV files to temp directory
            for file in files {
                let fileURL = tempDir.appendingPathComponent(file.name)
                try file.data.write(to: fileURL)
            }

            // Create ZIP using zip command
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-j", "-q", zipPath.path] + files.map { tempDir.appendingPathComponent($0.name).path }

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                print("ZIP creation failed with status: \(process.terminationStatus)")
                try? FileManager.default.removeItem(at: tempDir)
                try? FileManager.default.removeItem(at: zipPath)
                return nil
            }

            // Read ZIP data
            let zipData = try Data(contentsOf: zipPath)

            // Cleanup
            try FileManager.default.removeItem(at: tempDir)
            try FileManager.default.removeItem(at: zipPath)

            return zipData
        } catch {
            print("Error creating ZIP: \(error)")
            try? FileManager.default.removeItem(at: tempDir)
            try? FileManager.default.removeItem(at: zipPath)
            return nil
        }
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
