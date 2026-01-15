import SwiftUI

@main
struct ShowMarkerApp: App {

    var body: some Scene {
        DocumentGroup(newDocument: ShowMarkerDocument()) { file in
            ProjectView(document: file.$document)
                .onAppear {
                    // Устанавливаем documentURL после открытия файла
                    if let url = file.fileURL {
                        file.document.documentURL = url
                    }
                }
        }
    }
}
