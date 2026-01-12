import Foundation

struct MarkersCSVExporter {

    /// Reaper Markers CSV v1 (seconds-based)
    static func export(markers: [TimelineMarker]) -> String {

        let sorted = markers
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.timeSeconds < $1.timeSeconds }

        var lines: [String] = []
        lines.reserveCapacity(sorted.count)

        for (idx, marker) in sorted.enumerated() {
            let index = idx + 1
            let seconds = formatSeconds(marker.timeSeconds)
            let name = escape(marker.name)

            let line = "\(index),\(seconds),0,\"\(name)\""
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private static func formatSeconds(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "\"\"")
    }
}
