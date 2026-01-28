import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ProjectView: View {

    @Binding var document: ShowMarkerDocument

    // ObservedObject для nonisolated repository
    @ObservedObject private var repository: ProjectRepository

    @State private var searchText = ""
    @State private var isSearchPressed = false
    @State private var isAddButtonPressed = false

    @State private var isAddTimelinePresented = false
    @State private var newTimelineName = ""

    @State private var renamingTimelineID: UUID?
    @State private var renameText = ""

    @State private var isEditing = false
    @State private var selectedTimelines: Set<UUID> = []

    // Selected timeline for navigation
    @State private var selectedTimelineID: UUID?

    // Sidebar visibility
    @State private var isSidebarVisible = false

    // Export states
    @State private var csvExportData: Data?
    @State private var isCSVExportPresented = false
    @State private var exportFilename = ""

    // ZIP export states
    @State private var zipExportData: Data?
    @State private var isZIPExportPresented = false
    @State private var zipExportFilename = ""

    // CSV batch import states
    @State private var isCSVBatchImportPresented = false
    @State private var csvImportError: String?
    @State private var showCSVImportError = false

    private let availableFPS = [25, 30, 50, 60, 100]

    init(document: Binding<ShowMarkerDocument>) {
        _document = document
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
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // Sidebar - Timeline List
            sidebarContent
                .navigationTitle(repository.project.name)
                .toolbar { sidebarToolbarContent }
        } detail: {
            // Detail - Selected Timeline
            if let timelineID = selectedTimelineID {
                TimelineScreen(
                    repository: repository,
                    timelineID: timelineID
                )
            } else {
                // Placeholder when no timeline selected
                VStack(spacing: 16) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("Выберите таймлайн")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    if repository.project.timelines.isEmpty {
                        Text("Или создайте новый")
                            .font(.subheadline)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
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
        .onChange(of: renamingTimelineID) { oldValue, newValue in
            if newValue != nil {
                print("📝 [Rename] Alert opened for timeline")
            } else if oldValue != nil {
                print("📝 [Rename] Alert closed")
            }
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
            document: SimpleZIPDocument(zipData: zipExportData ?? Data()),
            contentType: .zip,
            defaultFilename: zipExportFilename
        ) { result in
            switch result {
            case .success:
                print("ZIP export successful")
            case .failure(let error):
                print("ZIP export failed: \(error.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $isCSVBatchImportPresented,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: true,
            onCompletion: handleCSVBatchImport
        )
        .alert("Ошибка импорта", isPresented: $showCSVImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(csvImportError ?? "Неизвестная ошибка")
        }
        .onAppear {
            // Auto-select first timeline if none selected
            if selectedTimelineID == nil, let first = repository.project.timelines.first {
                selectedTimelineID = first.id
            }
        }
    }

    // MARK: - Sidebar Content

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            if filteredTimelines.isEmpty {
                emptyState
            } else {
                List(selection: $selectedTimelineID) {
                    ForEach(filteredTimelines) { timeline in
                        sidebarTimelineRow(timeline)
                            .tag(timeline.id)
                    }
                    .onMove { fromOffsets, toOffset in
                        repository.moveTimelines(from: fromOffsets, to: toOffset)
                    }
                }
                .listStyle(.sidebar)
                .environment(\.editMode, .constant(isEditing ? .active : .inactive))
            }

            // Bottom bar with add button
            sidebarBottomBar
        }
    }

    private func sidebarTimelineRow(_ timeline: Timeline) -> some View {
        HStack(spacing: 12) {
            if isEditing {
                // Selection checkbox
                ZStack {
                    Circle()
                        .stroke(selectedTimelines.contains(timeline.id) ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: 2)
                        .frame(width: 22, height: 22)

                    if selectedTimelines.contains(timeline.id) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 22, height: 22)

                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .onTapGesture {
                    toggleSelection(timeline.id)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(timeline.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(timeline.markers.count) маркеров")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    if timeline.audio != nil {
                        Image(systemName: "waveform")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                duplicateTimeline(timeline)
            } label: {
                Label("Дублировать", systemImage: "doc.on.doc")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteTimeline(timeline)
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
        .contextMenu {
            timelineContextMenu(timeline)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Нет таймлайнов")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Нажмите + чтобы создать")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var sidebarBottomBar: some View {
        HStack(spacing: 12) {
            if isEditing {
                // Share button
                Button {
                    exportSelectedTimelines()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16))
                }
                .disabled(selectedTimelines.isEmpty)
                .opacity(selectedTimelines.isEmpty ? 0.4 : 1)

                // Duplicate button
                Button {
                    duplicateSelectedTimelines()
                } label: {
                    Image(systemName: "plus.square.on.square")
                        .font(.system(size: 16))
                }
                .disabled(selectedTimelines.isEmpty)
                .opacity(selectedTimelines.isEmpty ? 0.4 : 1)

                Spacer()

                // Delete button
                Button(role: .destructive) {
                    deleteSelectedTimelines()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                }
                .disabled(selectedTimelines.isEmpty)
                .opacity(selectedTimelines.isEmpty ? 0.4 : 1)

                // Done button
                Button("Готово") {
                    isEditing = false
                }
                .fontWeight(.semibold)
            } else {
                Spacer()

                // Add timeline button
                Button {
                    isAddTimelinePresented = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.accentColor))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground).opacity(0.95))
    }

    @ViewBuilder
    private func timelineContextMenu(_ timeline: Timeline) -> some View {
        Button {
            startRename(timeline)
        } label: {
            Label("Переименовать", systemImage: "pencil")
        }

        Divider()

        Button {
            duplicateTimeline(timeline)
        } label: {
            Label("Дублировать", systemImage: "doc.on.doc")
        }

        Button {
            shareTimeline(timeline)
        } label: {
            Label("Поделиться", systemImage: "square.and.arrow.up")
        }

        Divider()

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
                let newTimeline = repository.addTimeline(name: name)
                newTimelineName = ""
                // Auto-select the new timeline
                selectedTimelineID = newTimeline.id
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

    private var sidebarToolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        isEditing = true
                    } label: {
                        Label("Выбрать", systemImage: "checkmark.circle")
                    }

                    Button {
                        isCSVBatchImportPresented = true
                    } label: {
                        Label("Импорт маркеров из CSV", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        exportAllTimelines()
                    } label: {
                        Label("Экспорт CSV всех таймлайнов", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17))
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14))

            TextField("Поиск", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.system(size: 15))
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6))
        )
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

        // Clear selection if deleted
        if let selected = selectedTimelineID, !repository.project.timelines.contains(where: { $0.id == selected }) {
            selectedTimelineID = repository.project.timelines.first?.id
        }
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

    private func duplicateTimeline(_ timeline: Timeline) {
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

        // Insert after the original timeline instead of at the end
        if let currentIndex = repository.project.timelines.firstIndex(where: { $0.id == timeline.id }) {
            repository.project.timelines.insert(newTimeline, at: currentIndex + 1)
        } else {
            repository.addTimeline(newTimeline)
        }
    }

    private func shareTimeline(_ timeline: Timeline) {
        csvExportData = generateCSV(for: timeline)
        exportFilename = "\(timeline.name).csv"
        isCSVExportPresented = true
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
            // Multiple timelines - export as ZIP archive with separate CSV files
            if let zipData = generateZIP(for: selectedTimelineObjects) {
                zipExportData = zipData
                zipExportFilename = "\(repository.project.name) CSV.zip"
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
                zipExportFilename = "\(repository.project.name) CSV.zip"
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
        // Create separate CSV file for each timeline
        var files: [String: Data] = [:]

        for timeline in timelines {
            let csv = MarkersCSVExporter.export(
                markers: timeline.markers,
                frameRate: Double(repository.project.fps)
            )

            if let csvData = csv.data(using: .utf8) {
                // Sanitize filename to remove invalid characters
                let sanitizedName = timeline.name
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                let filename = "\(sanitizedName).csv"
                files[filename] = csvData
            }
        }

        return ZIPArchiveCreator.createZIP(files: files)
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

        // Clear selection if deleting currently selected
        if selectedTimelineID == timeline.id {
            let nextIndex = index > 0 ? index - 1 : (repository.project.timelines.count > 1 ? 1 : nil)
            selectedTimelineID = nextIndex.map { repository.project.timelines[$0].id }
        }

        repository.removeTimelines(at: IndexSet(integer: index))
    }

    private func handleCSVBatchImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }

        for url in urls {
            guard url.startAccessingSecurityScopedResource() else {
                csvImportError = "Не удалось получить доступ к файлу: \(url.lastPathComponent)"
                showCSVImportError = true
                continue
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                guard let csvContent = String(data: data, encoding: .utf8) else {
                    csvImportError = "Не удалось декодировать файл как текст: \(url.lastPathComponent)"
                    showCSVImportError = true
                    continue
                }

                // Parse markers from CSV
                let importedMarkers = MarkersCSVImporter.importFromCSV(csvContent, fps: repository.project.fps)

                // Create timeline from filename (without .csv extension)
                var timelineName = url.deletingPathExtension().lastPathComponent
                if timelineName.trimmingCharacters(in: .whitespaces).isEmpty {
                    timelineName = "Imported Timeline"
                }

                // Create new timeline
                let newTimeline = Timeline(
                    id: UUID(),
                    name: timelineName,
                    createdAt: Date(),
                    audio: nil,
                    fps: repository.project.fps,
                    markers: importedMarkers
                )

                repository.addTimeline(newTimeline)
                print("✅ Created timeline '\(timelineName)' with \(importedMarkers.count) markers from CSV")
            } catch {
                csvImportError = "Ошибка при чтении файла \(url.lastPathComponent): \(error.localizedDescription)"
                showCSVImportError = true
                print("❌ CSV batch import error: \(error)")
            }
        }

        if !urls.isEmpty && csvImportError == nil {
            print("✅ Batch CSV import completed: \(urls.count) files imported")
        }
    }
}
