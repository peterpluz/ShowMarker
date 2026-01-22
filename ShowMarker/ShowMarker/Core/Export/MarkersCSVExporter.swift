import Foundation

struct MarkersCSVExporter {

    /// CSV Export with timecode format (HH:MM:SS:FF)
    /// Format: #,Name,Start,End,Length
    static func export(markers: [TimelineMarker], fps: Int = 30) -> String {

        let sorted = markers
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.timeSeconds < $1.timeSeconds }

        var lines: [String] = []
        lines.reserveCapacity(sorted.count + 1)

        // Add header
        lines.append("#,Name,Start,End,Length")

        for (idx, marker) in sorted.enumerated() {
            let index = idx + 1
            let timecode = formatTimecode(marker.timeSeconds, fps: fps)
            let name = formatName(marker.name)

            let line = "M\(index),\(name),\(timecode),,"
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    /// Converts seconds to timecode format HH:MM:SS:FF
    private static func formatTimecode(_ seconds: Double, fps: Int) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        // Calculate frames from fractional part
        let fractional = seconds - Double(totalSeconds)
        let frames = Int(fractional * Double(fps))

        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secs, frames)
    }

    /// Formats name with proper quoting (only when needed)
    private static func formatName(_ text: String) -> String {
        // Check if name contains comma or quote
        let needsQuotes = text.contains(",") || text.contains("\"")

        if needsQuotes {
            // Escape quotes by doubling them
            let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        } else {
            return text
        }
    }
}
