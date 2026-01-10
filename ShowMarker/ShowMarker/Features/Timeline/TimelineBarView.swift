import SwiftUI

struct TimelineBarView: View {

    let duration: Double
    let currentTime: Double
    let onSeek: (Double) -> Void

    private let barHeight: CGFloat = 60
    private let playheadWidth: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            ZStack(alignment: .leading) {

                // Timeline background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: barHeight)

                // Playhead
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: playheadWidth, height: barHeight)
                    .offset(x: playheadX(totalWidth: width))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = min(max(0, value.location.x), width)
                        let seconds = (x / width) * duration
                        onSeek(seconds)
                    }
            )
        }
        .frame(height: barHeight)
    }

    private func playheadX(totalWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(currentTime / duration) * totalWidth
    }
}
