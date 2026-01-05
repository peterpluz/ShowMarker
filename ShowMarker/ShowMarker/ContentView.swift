import SwiftUI

struct ContentView: View {

    @Binding var document: ShowMarkerDocument

    var body: some View {
        VStack(spacing: 20) {
            Text("Project")
                .font(.headline)

            TextField("Project name", text: $document.project.name)
                .textFieldStyle(.roundedBorder)
                .padding()
        }
        .padding()
    }
}
