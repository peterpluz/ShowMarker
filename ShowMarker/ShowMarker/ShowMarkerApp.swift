import SwiftUI

@main
struct ShowMarkerApp: App {

    var body: some Scene {
        DocumentGroup(newDocument: ShowMarkerDocument()) { file in
            ProjectView(document: file.$document)
        }
    }
}
