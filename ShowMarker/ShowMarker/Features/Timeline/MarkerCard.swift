import SwiftUI

struct MarkerCard: View {

    let marker: TimelineMarker
    let fps: Int

    var body: some View {
        HStack(spacing: 12) {

            Image(systemName: "bookmark.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(marker.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(timecode())
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8) // ⬅️ ключевое уменьшение высоты
        .contentShape(Rectangle())
    }

    private func timecode() -> String {
        let totalFrames = Int(marker.timeSeconds * Double(fps))
        let frames = totalFrames % fps
        let totalSeconds = totalFrames / fps
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60

        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
}
