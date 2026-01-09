import SwiftUI

@main
struct ShowMarkerApp: App {
    var body: some Scene {
        DocumentGroup(
            newDocument: { ShowMarkerDocument() }
        ) { file in
            // `file.document` is an ObservedObject wrapper around ShowMarkerDocument.
            ProjectView(document: file.document)
        }
    }
}
