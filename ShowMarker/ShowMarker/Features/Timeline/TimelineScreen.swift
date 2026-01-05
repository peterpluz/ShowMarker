import SwiftUI

struct TimelineScreen: View {
    let timeline: Timeline

    var body: some View {
        VStack(spacing: 16) {
            Text(timeline.name)
                .font(.title2)
                .fontWeight(.semibold)

            Text("Таймлайн пока пуст")
                .foregroundColor(.secondary)
        }
        .padding()
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
    }
}
