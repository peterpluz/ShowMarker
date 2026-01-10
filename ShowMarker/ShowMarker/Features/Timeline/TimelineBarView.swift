import SwiftUI

struct TimelineBarView: View {

    let duration: Double
    let currentTime: Double
    let waveform: [Float]
    let markers: [TimelineMarker]
    let hasAudio: Bool
    let onAddAudio: () -> Void
    let onSeek: (Double) -> Void

    private let barHeight: CGFloat = 140
    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 1

    private let playheadLineWidth: CGFloat = 2
    private let markerLineWidth: CGFloat = 2

    private let scaleHeight: CGFloat = 18
    private let scaleSpacing: CGFloat = 6

    @State private var dragStartTime: Double?

    var body: some View {
        VStack(spacing: scaleSpacing) {

            GeometryReader { geo in

                if !hasAudio {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.12))
                        .overlay {
                            Button {
                                onAddAudio()
                            } label: {
                                Label("Добавить аудиофайл", systemImage: "plus")
                            }
                        }
                } else {

                    let centerX = geo.size.width / 2
                    let contentWidth = max(CGFloat(waveform.count) * (barWidth + spacing), 1)
                    let secondsPerPixel = duration > 0 ? duration / Double(contentWidth) : 0
                    let offsetX = centerX - timelineOffset(contentWidth: contentWidth)

                    ZStack {

                        // Waveform background
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.secondary.opacity(0.12))
                                .frame(width: contentWidth, height: barHeight)

                            HStack(spacing: spacing) {
                                ForEach(waveform.indices, id: \.self) { i in
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.6))
                                        .frame(
                                            width: barWidth,
                                            height: max(12, CGFloat(waveform[i]) * barHeight)
                                        )
                                }
                            }
                        }
                        .offset(x: offsetX)

                        // Markers
                        ForEach(markers) { marker in
                            Rectangle()
                                .fill(Color.orange)
                                .frame(width: markerLineWidth, height: barHeight)
                                .position(
                                    x: centerX
                                        - timelineOffset(contentWidth: contentWidth)
                                        + CGFloat(marker.timeSeconds / max(duration, 0.001)) * contentWidth,
                                    y: barHeight / 2
                                )
                        }

                        // Playhead
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: playheadLineWidth, height: barHeight)
                            .position(x: centerX, y: barHeight / 2)
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if dragStartTime == nil {
                                    dragStartTime = currentTime
                                }
                                guard let start = dragStartTime else { return }
                                let delta = Double(value.translation.width) * secondsPerPixel * -1
                                onSeek(clamp(start + delta))
                            }
                            .onEnded { _ in
                                dragStartTime = nil
                            }
                    )
                }
            }
            .frame(height: barHeight)

            if hasAudio {
                GeometryReader { geo in
                    let centerX = geo.size.width / 2
                    let contentWidth = max(CGFloat(waveform.count) * (barWidth + spacing), 1)
                    let pixelsPerSecond = contentWidth / CGFloat(max(duration, 1))

                    let major = majorStepSeconds(pixelsPerSecond: pixelsPerSecond)
                    let minor = major / 4

                    ZStack {
                        ForEach(scaleMarks(majorStep: major, minorStep: minor), id: \.time) { mark in
                            VStack(spacing: 2) {
                                Rectangle()
                                    .frame(width: 1, height: mark.isMajor ? 8 : 4)
                                if mark.isMajor {
                                    Text(mark.label)
                                        .font(.caption2)
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
    }

    private func clamp(_ t: Double) -> Double {
        min(max(t, 0), duration)
    }

    private func timelineOffset(contentWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(currentTime / duration) * contentWidth
    }

    private func majorStepSeconds(pixelsPerSecond: CGFloat) -> Double {
        for s in [0.5, 1, 2, 5, 10, 30, 60] {
            if CGFloat(s) * pixelsPerSecond >= 70 {
                return s
            }
        }
        return 60
    }

    private func scaleMarks(
        majorStep: Double,
        minorStep: Double
    ) -> [(time: Double, isMajor: Bool, label: String)] {
        var t: Double = 0
        var r: [(Double, Bool, String)] = []
        while t <= duration {
            let major = t.truncatingRemainder(dividingBy: majorStep) == 0
            r.append((t, major, major ? formatTime(t) : ""))
            t += minorStep
        }
        return r
    }

    private func formatTime(_ t: Double) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
