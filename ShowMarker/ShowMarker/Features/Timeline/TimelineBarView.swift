import SwiftUI

struct TimelineBarView: View {

    let duration: Double
    let currentTime: Double
    let waveform: [Float]
    let onSeek: (Double) -> Void

    // Timeline
    private let barHeight: CGFloat = 60
    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 1

    // Playhead
    private let playheadLineWidth: CGFloat = 2
    private let playheadDotSize: CGFloat = 10
    private let playheadGap: CGFloat = 4

    // Time scale
    private let scaleHeight: CGFloat = 18
    private let scaleSpacing: CGFloat = 6

    @State private var dragStartTime: Double?

    var body: some View {
        VStack(spacing: scaleSpacing) {

            // TIMELINE
            GeometryReader { geo in
                let viewWidth = geo.size.width
                let centerX = viewWidth / 2
                let contentWidth = max(CGFloat(waveform.count) * (barWidth + spacing), 1)
                let secondsPerPixel = duration / Double(contentWidth)

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
                    .offset(x: centerX - timelineOffset(contentWidth: contentWidth))
                    .clipped()

                    // playhead line
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: playheadLineWidth, height: barHeight)
                        .position(x: centerX, y: barHeight / 2)

                    // top dot
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: playheadDotSize, height: playheadDotSize)
                        .position(x: centerX, y: -playheadGap)

                    // bottom dot
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: playheadDotSize, height: playheadDotSize)
                        .position(x: centerX, y: barHeight + playheadGap)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragStartTime == nil {
                                dragStartTime = currentTime
                            }
                            guard let start = dragStartTime else { return }
                            let newTime = start - Double(value.translation.width) * secondsPerPixel
                            onSeek(min(max(newTime, 0), duration))
                        }
                        .onEnded { _ in
                            dragStartTime = nil
                        }
                )
            }
            .frame(height: barHeight)

            // TIME SCALE (как было до регрессий)
            GeometryReader { geo in
                let viewWidth = geo.size.width
                let centerX = viewWidth / 2
                let contentWidth = max(CGFloat(waveform.count) * (barWidth + spacing), 1)
                let pixelsPerSecond = contentWidth / CGFloat(max(duration, 1))

                let majorStep = majorStepSeconds(pixelsPerSecond: pixelsPerSecond)
                let minorStep = majorStep / 4

                ZStack(alignment: .leading) {
                    ForEach(scaleMarks(majorStep: majorStep, minorStep: minorStep), id: \.time) { mark in
                        VStack(spacing: 2) {
                            Rectangle()
                                .fill(Color.secondary.opacity(mark.isMajor ? 0.8 : 0.4))
                                .frame(width: 1, height: mark.isMajor ? 8 : 4)

                            if mark.isMajor {
                                Text(mark.label)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .position(
                            x: centerX
                               - timelineOffset(contentWidth: contentWidth)
                               + CGFloat(mark.time) * pixelsPerSecond,
                            y: scaleHeight / 2
                        )
                    }
                }
            }
            .frame(height: scaleHeight)
        }
    }

    // MARK: - Helpers

    private func timelineOffset(contentWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(currentTime / duration) * contentWidth
    }

    private func majorStepSeconds(pixelsPerSecond: CGFloat) -> Double {
        let minSpacing: CGFloat = 70
        let candidates: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60]

        for step in candidates {
            if CGFloat(step) * pixelsPerSecond >= minSpacing {
                return step
            }
        }
        return 60
    }

    private func scaleMarks(
        majorStep: Double,
        minorStep: Double
    ) -> [(time: Double, isMajor: Bool, label: String)] {

        guard duration > 0 else { return [] }

        var result: [(Double, Bool, String)] = []
        var t: Double = 0

        while t <= duration {
            let isMajor = t.truncatingRemainder(dividingBy: majorStep) == 0
            let label = isMajor ? formatTime(t) : ""
            result.append((t, isMajor, label))
            t += minorStep
        }

        return result
    }

    private func formatTime(_ time: Double) -> String {
        let total = Int(time.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
