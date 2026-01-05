import SwiftUI

struct ProjectView: View {

    @Binding var document: ShowMarkerDocument

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
                    Text(timeline.name)
                }
            }

            Spacer()

            Button("Создать таймлайн") {
                // заглушка — логика позже
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
