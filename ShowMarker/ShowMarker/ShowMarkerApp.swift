import SwiftUI

@main
struct ShowMarkerApp: App {

    var body: some Scene {
        DocumentGroup(newDocument: ShowMarkerDocument()) { file in
            ProjectView(document: file.$document)
                .onAppear {
                    // Устанавливаем documentURL при открытии файла
                    if let url = file.fileURL {
                        file.document.documentURL = url
                    }
                }
                .onChange(of: file.fileURL) { oldURL, newURL in
                    // КРИТИЧНО: обновляем documentURL когда файл сохраняется
                    // Это происходит при первом autosave нового документа (~15 сек)
                    // или при ручном сохранении
                    if let url = newURL {
                        file.document.documentURL = url
                    }
                }
        }
    }
}
