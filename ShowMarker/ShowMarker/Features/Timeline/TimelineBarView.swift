import SwiftUI

struct TimelineBarView: View {

    let duration: Double
    let currentTime: Double
    let waveform: [Float]
    let onSeek: (Double) -> Void

    private let barHeight: CGFloat = 60
    private let playheadWidth: CGFloat = 2
    private let spacing: CGFloat = 1
    private let barWidth: CGFloat = 3

    @State private var dragStartTime: Double?

    var body: some View {
        GeometryReader { geo in
            let viewWidth = geo.size.width
            let centerX = viewWidth / 2
            let contentWidth = CGFloat(waveform.count) * (barWidth + spacing)

            ZStack {

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: barHeight)

                HStack(alignment: .center, spacing: spacing) {
                    ForEach(waveform.indices, id: \.self) { i in
                        Rectangle()
                            .fill(Color.secondary.opacity(0.6))
                            .frame(
                                width: barWidth,
                                height: max(4, CGFloat(waveform[i]) * barHeight)
                            )
                    }
                }
                .frame(height: barHeight)
                .offset(x: centerX - waveformOffset(contentWidth: contentWidth))
                .clipped()

                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: playheadWidth, height: barHeight)
                    .position(x: centerX, y: barHeight / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartTime == nil {
                            dragStartTime = currentTime
                        }

                        guard
                            let startTime = dragStartTime,
                            duration > 0,
                            contentWidth > 0
                        else { return }

                        let deltaX = value.translation.width
                        let secondsPerPoint = duration / contentWidth
                        let newTime = startTime - Double(deltaX) * secondsPerPoint

                        onSeek(min(max(newTime, 0), duration))
                    }
                    .onEnded { _ in
                        dragStartTime = nil
                    }
            )
        }
        .frame(height: barHeight)
    }

    // MARK: - Helpers

    private func waveformOffset(contentWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let progress = currentTime / duration
        return CGFloat(progress) * contentWidth
    }
}
