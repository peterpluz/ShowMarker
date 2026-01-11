import SwiftUI

struct TimelineBarView: View {

    let duration: Double
    let currentTime: Double
    let waveform: [Float]
    let markers: [TimelineMarker]
    let hasAudio: Bool
    let onAddAudio: () -> Void
    let onSeek: (Double) -> Void
    let onMoveMarker: (TimelineMarker, Double) -> Void

    private let barHeight: CGFloat = 140
    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 1

    private let playheadLineWidth: CGFloat = 2
    private let markerLineWidth: CGFloat = 3

    private let scaleHeight: CGFloat = 18
    private let scaleSpacing: CGFloat = 6

    @State private var dragStartTime: Double?
    @State private var armedMarkerID: UUID?
    @State private var isBlinking = false

    var body: some View {
        VStack(spacing: scaleSpacing) {

            GeometryReader { geo in

                if !hasAudio {

                    Button(action: onAddAudio) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.12))
                            .overlay {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus")
                                    Text("Добавить аудиофайл")
                                }
                                .font(.headline)
                                .foregroundColor(.accentColor)
                            }
                    }
                    .buttonStyle(.plain)

                } else {

                    let centerX = geo.size.width / 2
                    let contentWidth = max(CGFloat(waveform.count) * (barWidth + spacing), 1)
                    let secondsPerPixel = duration > 0 ? duration / Double(contentWidth) : 0

                    ZStack {

                        waveformView(contentWidth: contentWidth)
                            .offset(x: centerX - timelineOffset(contentWidth: contentWidth))

                        ForEach(markers) { marker in
                            let isArmed = armedMarkerID == marker.id

                            Rectangle()
                                .fill(Color.orange)
                                .frame(width: markerLineWidth, height: barHeight)
                                .opacity(isArmed && isBlinking ? 0.3 : 1)
                                .animation(
                                    isArmed
                                    ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                                    : .default,
                                    value: isBlinking
                                )
                                .position(
                                    x: centerX
                                        - timelineOffset(contentWidth: contentWidth)
                                        + CGFloat(marker.timeSeconds / max(duration, 0.001)) * contentWidth,
                                    y: barHeight / 2
                                )
                                // ✅ ОДИН жест: LongPress → Drag
                                .gesture(
                                    LongPressGesture(minimumDuration: 0.35)
                                        .onEnded { _ in
                                            armedMarkerID = marker.id
                                            isBlinking = true
                                        }
                                        .sequenced(before: DragGesture())
                                        .onChanged { value in
                                            guard case .second(true, let drag?) = value,
                                                  armedMarkerID == marker.id
                                            else { return }

                                            let contentOriginX =
                                                centerX - timelineOffset(contentWidth: contentWidth)

                                            let relative =
                                                (drag.location.x - contentOriginX) / contentWidth

                                            let newTime = clamp(Double(relative) * duration)
                                            onMoveMarker(marker, newTime)
                                        }
                                        .onEnded { _ in
                                            armedMarkerID = nil
                                            isBlinking = false
                                        }
                                )
                        }

                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: playheadLineWidth, height: barHeight)
                            .position(x: centerX, y: barHeight / 2)
                    }
                    // drag таймлайна (если НЕ тянем маркер)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard armedMarkerID == nil else { return }

                                if dragStartTime == nil {
                                    dragStartTime = currentTime
                                }
                                guard let start = dragStartTime else { return }

                                let delta = Double(value.translation.width)
                                    * secondsPerPixel * -1
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
                scaleView
            }
        }
    }

    // MARK: - Subviews

    private func waveformView(contentWidth: CGFloat) -> some View {
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
    }

    private var scaleView: some View {
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

    // MARK: - Helpers

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
