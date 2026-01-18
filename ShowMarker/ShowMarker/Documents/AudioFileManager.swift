import Foundation

// MARK: - Audio File Errors

enum AudioFileError: LocalizedError {
    case documentURLInvalid
    case fileNotFound(String)
    case writeFailed(Error)
    case readFailed(Error)
    case deleteFailed(Error)
    case directoryCreationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .documentURLInvalid:
            return "Document URL is invalid or not accessible"
        case .fileNotFound(let fileName):
            return "Audio file '\(fileName)' not found"
        case .writeFailed(let error):
            return "Failed to write audio file: \(error.localizedDescription)"
        case .readFailed(let error):
            return "Failed to read audio file: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete audio file: \(error.localizedDescription)"
        case .directoryCreationFailed(let error):
            return "Failed to create audio directory: \(error.localizedDescription)"
        }
    }
}

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

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw AudioFileError.fileNotFound(fileName)
        }

        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw AudioFileError.readFailed(error)
        }
    }

    func audioFileURL(fileName: String) -> URL {
        audioDirectory.appendingPathComponent(fileName)
    }

    // MARK: - Write

    func addAudioFile(sourceData: Data, fileName: String) throws {
        do {
            try createAudioDirectoryIfNeeded()
        } catch {
            throw AudioFileError.directoryCreationFailed(error)
        }

        let targetURL = audioDirectory.appendingPathComponent(fileName)

        do {
            try sourceData.write(to: targetURL, options: .atomic)
        } catch {
            throw AudioFileError.writeFailed(error)
        }
    }

    func deleteAudioFile(fileName: String) throws {
        let fileURL = audioDirectory.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // File doesn't exist, nothing to delete - not an error
            return
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw AudioFileError.deleteFailed(error)
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
