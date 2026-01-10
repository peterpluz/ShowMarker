import SwiftUI

struct TimelineBarView: View {

    let duration: Double
    let currentTime: Double
    let waveform: [Float]
    let onSeek: (Double) -> Void

    private let barHeight: CGFloat = 60
    private let playheadWidth: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            ZStack(alignment: .leading) {

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: barHeight)

                if !waveform.isEmpty {
                    HStack(alignment: .center, spacing: 1) {
                        ForEach(waveform.indices, id: \.self) { i in
                            Rectangle()
                                .fill(Color.secondary.opacity(0.6))
                                .frame(
                                    width: barWidth(totalWidth: width),
                                    height: max(4, CGFloat(waveform[i]) * barHeight)
                                )
                        }
                    }
                    .frame(height: barHeight)
                }

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

    // MARK: - Helpers

    private func playheadX(totalWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(currentTime / duration) * totalWidth
    }

    private func barWidth(totalWidth: CGFloat) -> CGFloat {
        guard !waveform.isEmpty else { return 1 }
        return totalWidth / CGFloat(waveform.count)
    }
}
