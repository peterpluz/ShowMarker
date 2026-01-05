import SwiftUI

@main
struct ShowMarkerApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: ShowMarkerDocument()) { _ in
            ContentView()
        }
    }
}
