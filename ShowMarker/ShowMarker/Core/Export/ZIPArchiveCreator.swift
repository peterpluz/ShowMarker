import Foundation

struct ZIPArchiveCreator {

    /// Create real ZIP archive from multiple CSV files using pure Swift implementation
    /// - Parameter files: Dictionary where key is filename and value is file data
    /// - Returns: ZIP archive as Data
    static func createZIP(files: [String: Data]) -> Data? {
        guard !files.isEmpty else { return nil }

        var zipData = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        // Create file entries
        for (filename, fileData) in files.sorted(by: { $0.key < $1.key }) {
            let filenameData = filename.data(using: .utf8) ?? Data()
            let crc32 = calculateCRC32(data: fileData)

            // Local file header
            let localHeader = createLocalFileHeader(
                filename: filenameData,
                fileSize: UInt32(fileData.count),
                crc32: crc32
            )

            // Central directory entry
            let centralEntry = createCentralDirectoryEntry(
                filename: filenameData,
                fileSize: UInt32(fileData.count),
                crc32: crc32,
                offset: offset
            )

            // Append to ZIP
            zipData.append(localHeader)
            zipData.append(filenameData)
            zipData.append(fileData)

            // Append to central directory
            centralDirectory.append(centralEntry)
            centralDirectory.append(filenameData)

            offset = UInt32(zipData.count)
        }

        // End of central directory
        let endOfCentralDirectory = createEndOfCentralDirectory(
            entryCount: UInt16(files.count),
            centralDirectorySize: UInt32(centralDirectory.count),
            centralDirectoryOffset: offset
        )

        zipData.append(centralDirectory)
        zipData.append(endOfCentralDirectory)

        return zipData
    }

    // MARK: - ZIP Structure Helpers

    private static func createLocalFileHeader(filename: Data, fileSize: UInt32, crc32: UInt32) -> Data {
        var header = Data()

        // Local file header signature
        header.append(contentsOf: [0x50, 0x4b, 0x03, 0x04])

        // Version needed to extract (2.0)
        header.append(contentsOf: [0x14, 0x00])

        // General purpose bit flag
        header.append(contentsOf: [0x00, 0x00])

        // Compression method (0 = no compression)
        header.append(contentsOf: [0x00, 0x00])

        // Last mod file time & date
        header.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        // CRC-32
        header.append(littleEndian: crc32)

        // Compressed size
        header.append(littleEndian: fileSize)

        // Uncompressed size
        header.append(littleEndian: fileSize)

        // File name length
        header.append(littleEndian: UInt16(filename.count))

        // Extra field length
        header.append(contentsOf: [0x00, 0x00])

        return header
    }

    private static func createCentralDirectoryEntry(filename: Data, fileSize: UInt32, crc32: UInt32, offset: UInt32) -> Data {
        var entry = Data()

        // Central directory signature
        entry.append(contentsOf: [0x50, 0x4b, 0x01, 0x02])

        // Version made by
        entry.append(contentsOf: [0x14, 0x00])

        // Version needed to extract
        entry.append(contentsOf: [0x14, 0x00])

        // General purpose bit flag
        entry.append(contentsOf: [0x00, 0x00])

        // Compression method
        entry.append(contentsOf: [0x00, 0x00])

        // Last mod file time & date
        entry.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        // CRC-32
        entry.append(littleEndian: crc32)

        // Compressed size
        entry.append(littleEndian: fileSize)

        // Uncompressed size
        entry.append(littleEndian: fileSize)

        // File name length
        entry.append(littleEndian: UInt16(filename.count))

        // Extra field length
        entry.append(contentsOf: [0x00, 0x00])

        // File comment length
        entry.append(contentsOf: [0x00, 0x00])

        // Disk number start
        entry.append(contentsOf: [0x00, 0x00])

        // Internal file attributes
        entry.append(contentsOf: [0x00, 0x00])

        // External file attributes
        entry.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        // Relative offset of local header
        entry.append(littleEndian: offset)

        return entry
    }

    private static func createEndOfCentralDirectory(entryCount: UInt16, centralDirectorySize: UInt32, centralDirectoryOffset: UInt32) -> Data {
        var end = Data()

        // End of central directory signature
        end.append(contentsOf: [0x50, 0x4b, 0x05, 0x06])

        // Number of this disk
        end.append(contentsOf: [0x00, 0x00])

        // Disk where central directory starts
        end.append(contentsOf: [0x00, 0x00])

        // Number of central directory records on this disk
        end.append(littleEndian: entryCount)

        // Total number of central directory records
        end.append(littleEndian: entryCount)

        // Size of central directory
        end.append(littleEndian: centralDirectorySize)

        // Offset of start of central directory
        end.append(littleEndian: centralDirectoryOffset)

        // ZIP file comment length
        end.append(contentsOf: [0x00, 0x00])

        return end
    }

    // Simple CRC32 implementation
    private static func calculateCRC32(data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF

        for byte in data {
            let index = (UInt8(crc & 0xFF) ^ byte)
            crc = (crc >> 8) ^ crc32Table[Int(index)]
        }

        return crc ^ 0xFFFFFFFF
    }

    // CRC32 lookup table
    private static let crc32Table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var crc = UInt32(i)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xEDB88320 : 0)
            }
            return crc
        }
    }()
}

// Data extension for little-endian integer appending
extension Data {
    mutating func append(littleEndian value: UInt16) {
        var val = value.littleEndian
        withUnsafeBytes(of: &val) { self.append(contentsOf: $0) }
    }

    mutating func append(littleEndian value: UInt32) {
        var val = value.littleEndian
        withUnsafeBytes(of: &val) { self.append(contentsOf: $0) }
    }
}
