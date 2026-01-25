import Foundation

struct ZIPArchiveCreator {

    /// Create real ZIP archive from multiple CSV files
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

            // Create ZIP using system ditto command
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", tempDir.path, zipURL.path]

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw NSError(domain: "ZIPArchiveCreator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create ZIP archive"])
            }

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
