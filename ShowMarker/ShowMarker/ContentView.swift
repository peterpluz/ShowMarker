import SwiftUI

struct ContentView: View {

    @Binding var document: ShowMarkerDocument

    var body: some View {
        VStack(spacing: 20) {
            Text("Project")
                .font(.headline)

            TextField("Project name", text: $document.projectName)
                .textFieldStyle(.roundedBorder)
                .padding()
        }
        .padding()
    }
}
