import SwiftUI

struct MarkerCard: View {

    let marker: TimelineMarker
    let fps: Int
    let isFlashing: Bool

    @State private var flashOpacity: Double = 0

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
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(flashOpacity * 0.3))
        )
        .onChange(of: isFlashing) { newValue in
            if newValue {
                triggerFlashEffect()
            }
        }
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

    private func triggerFlashEffect() {
        // Quick attack: rise to full opacity in 0.1 seconds
        withAnimation(.easeOut(duration: 0.1)) {
            flashOpacity = 1.0
        }

        // Slow decay: fade out over 0.4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeIn(duration: 0.4)) {
                flashOpacity = 0
            }
        }
    }
}
