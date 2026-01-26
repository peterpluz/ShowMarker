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

/// Управляет аудиофайлами для ShowMarker документов
///
/// ВАЖНО: На iOS нельзя напрямую записывать в documentURL (File Provider Storage).
/// Вместо этого используем временную директорию:
/// 1. Новые аудио файлы сохраняются во временную директорию для воспроизведения
/// 2. Данные сохраняются в pendingAudioFiles для последующего включения в FileWrapper
/// 3. При открытии документа аудио извлекается из FileWrapper во временную директорию
struct AudioFileManager {

    let tempDirectory: URL

    init(tempDirectory: URL) {
        self.tempDirectory = tempDirectory
    }

    // MARK: - Audio Directory

    private var audioDirectory: URL {
        tempDirectory.appendingPathComponent("Audio")
    }

    // MARK: - Read

    func readAudioFile(relativePath: String) throws -> Data {
        let fileURL = tempDirectory.appendingPathComponent(relativePath)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw AudioFileError.fileNotFound(relativePath)
        }

        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw AudioFileError.readFailed(error)
        }
    }

    func audioFileURL(relativePath: String) -> URL {
        tempDirectory.appendingPathComponent(relativePath)
    }

    // MARK: - Write

    /// Сохраняет аудио файл во временную директорию для воспроизведения
    func saveAudioToTemp(sourceData: Data, relativePath: String) throws {
        do {
            try createAudioDirectoryIfNeeded()
        } catch {
            throw AudioFileError.directoryCreationFailed(error)
        }

        let targetURL = tempDirectory.appendingPathComponent(relativePath)

        do {
            try sourceData.write(to: targetURL, options: .atomic)
            print("✅ Audio saved to temp: \(targetURL)")
        } catch {
            throw AudioFileError.writeFailed(error)
        }
    }

    func deleteAudioFile(relativePath: String) throws {
        let fileURL = tempDirectory.appendingPathComponent(relativePath)

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

    func audioFileExists(relativePath: String) -> Bool {
        let fileURL = tempDirectory.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Очищает временную директорию (вызывается при закрытии документа)
    func cleanup() {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
}
