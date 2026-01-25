import Foundation

struct ZIPArchiveCreator {

    /// Create FileWrapper representing a directory with multiple CSV files
    /// When exported with .zip UTType, system will automatically create ZIP archive
    /// - Parameter files: Dictionary where key is filename and value is file data
    /// - Returns: FileWrapper containing all files
    static func createDirectoryWrapper(files: [String: Data]) -> FileWrapper? {
        guard !files.isEmpty else { return nil }

        var fileWrappers: [String: FileWrapper] = [:]

        for (filename, data) in files {
            let fileWrapper = FileWrapper(regularFileWithContents: data)
            fileWrapper.preferredFilename = filename
            fileWrappers[filename] = fileWrapper
        }

        return FileWrapper(directoryWithFileWrappers: fileWrappers)
    }
}
