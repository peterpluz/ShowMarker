import Foundation
import Compression

struct ZIPArchiveCreator {

    /// Create real ZIP archive from multiple CSV files using Archive framework
    /// - Parameter files: Dictionary where key is filename and value is file data
    /// - Returns: ZIP archive as Data
    static func createZIP(files: [String: Data]) -> Data? {
        guard !files.isEmpty else { return nil }

        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let zipURL = fileManager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")

        do {
            // Create temporary directory
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Write all files to temporary directory
            for (filename, data) in files {
                let fileURL = tempDir.appendingPathComponent(filename)
                try data.write(to: fileURL)
            }

            // Create ZIP using FileManager's built-in archiving
            // For macOS, we can use the coordinator to create a zip
            try fileManager.zipItem(at: tempDir, to: zipURL)

            // Read ZIP data
            let zipData = try Data(contentsOf: zipURL)

            // Cleanup temporary files
            try? fileManager.removeItem(at: tempDir)
            try? fileManager.removeItem(at: zipURL)

            return zipData

        } catch {
            print("Error creating ZIP: \(error)")
            try? fileManager.removeItem(at: tempDir)
            try? fileManager.removeItem(at: zipURL)
            return nil
        }
    }
}

// FileManager extension for ZIP creation
extension FileManager {
    func zipItem(at sourceURL: URL, to destinationURL: URL) throws {
        // Use NSTask for zip creation (available in macOS)
        let task = Foundation.Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", sourceURL.path, destinationURL.path]

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            throw NSError(domain: "ZIPArchiveCreator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create ZIP archive"])
        }
    }
}
