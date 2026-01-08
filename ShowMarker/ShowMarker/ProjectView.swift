import SwiftUI

struct ProjectView: View {

    @ObservedObject var document: ShowMarkerDocument

    @State private var isAddTimelinePresented = false
    @State private var newTimelineName = ""

    var body: some View {
        VStack(spacing: 24) {

            Text(document.project.name)
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            if document.project.timelines.isEmpty {
                VStack(spacing: 8) {
                    Text("Нет таймлайнов")
                        .foregroundColor(.secondary)
                    Text("Начните с создания таймлайна")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else {
                List(document.project.timelines) { timeline in
                    NavigationLink {
                        TimelineScreen(timeline: timeline)
                    } label: {
                        Text(timeline.name)
                    }
                }
            }

            Spacer()

            Button("Создать таймлайн") {
                newTimelineName = ""
                isAddTimelinePresented = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .alert("Новый таймлайн", isPresented: $isAddTimelinePresented) {
            TextField("Название", text: $newTimelineName)
            Button("Создать") {
                let name = newTimelineName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                document.project.timelines.append(Timeline(name: name))
            }
            Button("Отмена", role: .cancel) {}
        }
    }
}
