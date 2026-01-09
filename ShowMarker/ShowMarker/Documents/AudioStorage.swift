import Foundation

enum AudioStorage {

    static func audioDirectory(documentURL: URL) throws -> URL {
        let dir = documentURL
            .deletingLastPathComponent()
            .appendingPathComponent("Audio", isDirectory: true)

        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        }

        return dir
    }

    static func copyToProject(
        from sourceURL: URL,
        documentURL: URL
    ) throws -> String {

        let ext = sourceURL.pathExtension
        let fileName = UUID().uuidString + "." + ext

        let targetDir = try audioDirectory(documentURL: documentURL)
        let targetURL = targetDir.appendingPathComponent(fileName)

        try FileManager.default.copyItem(
            at: sourceURL,
            to: targetURL
        )

        return "Audio/\(fileName)"
    }
}
