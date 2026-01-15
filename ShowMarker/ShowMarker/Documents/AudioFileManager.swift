import Foundation

/// Управляет аудиофайлами внутри .smark package
struct AudioFileManager {
    
    let documentURL: URL
    
    init(documentURL: URL) {
        self.documentURL = documentURL
    }
    
    // MARK: - Audio Directory
    
    private var audioDirectory: URL {
        documentURL.appendingPathComponent("Audio")
    }
    
    // MARK: - Read
    
    func readAudioFile(fileName: String) throws -> Data {
        let fileURL = audioDirectory.appendingPathComponent(fileName)
        return try Data(contentsOf: fileURL)
    }
    
    func audioFileURL(fileName: String) -> URL {
        audioDirectory.appendingPathComponent(fileName)
    }
    
    // MARK: - Write
    
    func addAudioFile(sourceData: Data, fileName: String) throws {
        try createAudioDirectoryIfNeeded()
        
        let targetURL = audioDirectory.appendingPathComponent(fileName)
        try sourceData.write(to: targetURL, options: .atomic)
    }
    
    func deleteAudioFile(fileName: String) throws {
        let fileURL = audioDirectory.appendingPathComponent(fileName)
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
    
    // MARK: - Helpers
    
    private func createAudioDirectoryIfNeeded() throws {
        if !FileManager.default.fileExists(atPath: audioDirectory.path) {
            try FileManager.default.createDirectory(
                at: audioDirectory,
                withIntermediateDirectories: true
            )
        }
    }
    
    func audioFileExists(fileName: String) -> Bool {
        let fileURL = audioDirectory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
