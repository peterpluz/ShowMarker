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
                        print("📁 [onAppear] documentURL set: \(url)")
                    } else {
                        print("📁 [onAppear] fileURL is nil (new unsaved document)")
                    }
                }
                // ✅ CRITICAL FIX: Track fileURL changes after autosave
                // New documents have nil fileURL until iOS autosaves them.
                // Without this onChange, documentURL stays nil and audio import fails.
                .onChange(of: file.fileURL) { oldValue, newValue in
                    if let url = newValue {
                        file.document.documentURL = url
                        print("📁 [onChange] documentURL updated: \(url)")
                    }
                }
        }
    }
}
