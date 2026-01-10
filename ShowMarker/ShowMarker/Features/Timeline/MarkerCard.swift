import SwiftUI

struct MarkerCard: View {

    let marker: TimelineMarker
    let fps: Int

    var body: some View {
        HStack(spacing: 12) {

            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 4)
                .cornerRadius(2)

            VStack(alignment: .leading, spacing: 4) {
                Text(marker.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(timecode())
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.12))
        )
    }

    private func timecode() -> String {
        let totalFrames = Int(marker.timeSeconds * Double(fps))
        let frames = totalFrames % fps
        let totalSeconds = totalFrames / fps
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60

        return String(
            format: "%02d:%02d:%02d:%02d",
            hours, minutes, seconds, frames
        )
    }
}
