import SwiftUI

struct ProjectView: View {

    @Binding var document: ShowMarkerDocument

    @State private var isAddTimelinePresented = false
    @State private var newTimelineName = ""

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
            Button("Создать таймлайн") {
                isAddTimelinePresented = true
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
    }
}
