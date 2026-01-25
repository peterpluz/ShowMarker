import Foundation

struct MarkersCSVExporter {

    /// Export markers to CSV format with header: #,Name,Start,End,Length
    static func export(markers: [TimelineMarker], frameRate: Double = 30.0) -> String {

        let sorted = markers
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.timeSeconds < $1.timeSeconds }

        var lines: [String] = []
        lines.reserveCapacity(sorted.count + 1)

        // Add CSV header
        lines.append("#,Name,Start,End,Length")

        for (idx, marker) in sorted.enumerated() {
            let markerId = "M\(idx + 1)"
            let timecode = formatTimecode(marker.timeSeconds, frameRate: frameRate)
            let name = formatCSVField(marker.name)

            // Format: #,Name,Start,End,Length (End and Length are empty)
            let line = "\(markerId),\(name),\(timecode),,"
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    /// Convert seconds to timecode format HH:MM:SS:FF
    private static func formatTimecode(_ totalSeconds: Double, frameRate: Double) -> String {
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        let frames = Int((totalSeconds.truncatingRemainder(dividingBy: 1.0)) * frameRate)

        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }

    /// Format a field for CSV output, adding quotes only when necessary
    private static func formatCSVField(_ text: String) -> String {
        // Check if the field needs quotes (contains comma, quote, or newline)
        let needsQuotes = text.contains(",") || text.contains("\"") || text.contains("\n") || text.contains("\r")

        if needsQuotes {
            // Escape quotes by doubling them
            let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        } else {
            return text
        }
    }
}
