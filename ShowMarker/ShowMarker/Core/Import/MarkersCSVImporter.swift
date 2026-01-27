import Foundation

struct MarkersCSVImporter {

    /// Import markers from CSV string
    /// Format: #,Name,Start,End,Length
    /// Example: M1,"My Marker",00:00:05:15,,
    static func importFromCSV(_ csvContent: String, fps: Int) -> [TimelineMarker] {
        var markers: [TimelineMarker] = []

        let lines = csvContent.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Skip header line if it exists
        let dataLines = lines.first == "#,Name,Start,End,Length" ? Array(lines.dropFirst()) : lines

        for line in dataLines {
            if let marker = parseCSVLine(line, fps: fps) {
                markers.append(marker)
            }
        }

        // Sort by time
        return markers.sorted { $0.timeSeconds < $1.timeSeconds }
    }

    // MARK: - Private

    /// Parse a single CSV line into a TimelineMarker
    private static func parseCSVLine(_ line: String, fps: Int) -> TimelineMarker? {
        let fields = parseCSVFields(line)

        // Need at least: #, Name, Start
        guard fields.count >= 3 else {
            print("❌ Invalid CSV line (not enough fields): \(line)")
            return nil
        }

        let name = fields[1]
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            print("❌ Invalid CSV line (empty name): \(line)")
            return nil
        }

        let timecodString = fields[2]
        guard let timeSeconds = parseTimecode(timecodString, fps: fps) else {
            print("❌ Invalid timecode format: \(timecodString)")
            return nil
        }

        // Create marker with unique ID
        return TimelineMarker(
            id: UUID(),
            name: name,
            timeSeconds: timeSeconds,
            tagId: nil
        )
    }

    /// Parse CSV line respecting quoted fields and escaped quotes
    private static func parseCSVFields(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var isQuoted = false
        var chars = Array(line)
        var i = 0

        while i < chars.count {
            let char = chars[i]

            if char == "\"" {
                if isQuoted && i + 1 < chars.count && chars[i + 1] == "\"" {
                    // Double quote - escaped quote
                    currentField.append("\"")
                    i += 2
                } else {
                    // Toggle quote state
                    isQuoted.toggle()
                    i += 1
                }
            } else if char == "," && !isQuoted {
                // Field separator
                fields.append(currentField)
                currentField = ""
                i += 1
            } else {
                currentField.append(char)
                i += 1
            }
        }

        // Add last field
        fields.append(currentField)

        return fields.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Parse timecode string HH:MM:SS:FF to seconds
    /// Supports both "HH:MM:SS:FF" and "MM:SS:FF" formats
    private static func parseTimecode(_ timecodeString: String, fps: Int) -> Double? {
        let parts = timecodeString.split(separator: ":")

        switch parts.count {
        case 3:
            // MM:SS:FF format
            guard let minutes = Int(parts[0]),
                  let seconds = Int(parts[1]),
                  let frames = Int(parts[2]) else {
                return nil
            }
            return Double(minutes * 60 + seconds) + Double(frames) / Double(fps)

        case 4:
            // HH:MM:SS:FF format
            guard let hours = Int(parts[0]),
                  let minutes = Int(parts[1]),
                  let seconds = Int(parts[2]),
                  let frames = Int(parts[3]) else {
                return nil
            }
            return Double(hours * 3600 + minutes * 60 + seconds) + Double(frames) / Double(fps)

        default:
            return nil
        }
    }
}
