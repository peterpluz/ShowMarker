import Foundation

enum AudioStorage {

    static func audioDirectory() throws -> URL {
        let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let dir = docs.appendingPathComponent("Audio", isDirectory: true)

        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        }

        return dir
    }

    static func copyToProject(from sourceURL: URL) throws -> String {
        let ext = sourceURL.pathExtension
        let fileName = UUID().uuidString + "." + ext

        let targetURL = try audioDirectory()
            .appendingPathComponent(fileName)

        try FileManager.default.copyItem(
            at: sourceURL,
            to: targetURL
        )

        return "Audio/\(fileName)"
    }

    static func url(for relativePath: String) -> URL {
        let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        return docs.appendingPathComponent(relativePath)
    }
}
