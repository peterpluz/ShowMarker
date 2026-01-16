import SwiftUI

struct TimelineBarView: View {

    let duration: Double
    let currentTime: Double

    let waveform: [Float]
    let markers: [TimelineMarker]

    let hasAudio: Bool

    let onAddAudio: () -> Void
    let onSeek: (Double) -> Void

    let onPreviewMoveMarker: (UUID, Double) -> Void
    let onCommitMoveMarker: (UUID, Double) -> Void

    // MARK: - Constants

    private static let barHeight: CGFloat = 140
    private static let barWidth: CGFloat = 3
    private static let spacing: CGFloat = 1
    private static let playheadLineWidth: CGFloat = 2
    private static let markerLineWidth: CGFloat = 3

    // MARK: - Local state для smooth preview
    
    @State private var draggedMarkerID: UUID?
    @State private var draggedMarkerPreviewTime: Double?
    @State private var dragStartTime: Double?

    var body: some View {
        GeometryReader { geo in

            if !hasAudio {

                Button(action: onAddAudio) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.12))
                        .overlay {
                            Label("Добавить аудиофайл", systemImage: "plus")
                                .font(.headline)
                                .foregroundColor(.accentColor)
                        }
                }
                .buttonStyle(.plain)

            } else {

                let centerX = geo.size.width / 2
                let contentWidth = max(CGFloat(waveform.count) * (Self.barWidth + Self.spacing), 1)
                let secondsPerPixel = duration > 0 ? duration / Double(contentWidth) : 0

                ZStack {

                    waveformView(width: contentWidth)
                        .offset(x: centerX - timelineOffset(contentWidth))

                    ForEach(markers) { marker in
                        let displayTime = (draggedMarkerID == marker.id && draggedMarkerPreviewTime != nil)
                            ? draggedMarkerPreviewTime!
                            : marker.timeSeconds
                        
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: Self.markerLineWidth, height: Self.barHeight)
                            .position(
                                x: centerX
                                    - timelineOffset(contentWidth)
                                    + CGFloat(displayTime / max(duration, 0.0001)) * contentWidth,
                                y: Self.barHeight / 2
                            )
                            .gesture(markerGesture(
                                marker: marker,
                                centerX: centerX,
                                contentWidth: contentWidth
                            ))
                    }

                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: Self.playheadLineWidth, height: Self.barHeight)
                        .position(x: centerX, y: Self.barHeight / 2)
                }
                .gesture(playheadDrag(secondsPerPixel: secondsPerPixel))
            }
        }
        .frame(height: Self.barHeight)
    }

    // MARK: - Gestures

    private func playheadDrag(secondsPerPixel: Double) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard draggedMarkerID == nil else { return }

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
    }

    // MARK: - Marker gesture (ИСПРАВЛЕНО: локальный preview)

    private func markerGesture(
        marker: TimelineMarker,
        centerX: CGFloat,
        contentWidth: CGFloat
    ) -> some Gesture {

        LongPressGesture(minimumDuration: 0.35)
            .onEnded { _ in
                draggedMarkerID = marker.id
                draggedMarkerPreviewTime = marker.timeSeconds
            }
            .sequenced(before: DragGesture())
            .onChanged { value in
                guard
                    case .second(true, let drag?) = value,
                    draggedMarkerID == marker.id
                else { return }

                let originX = centerX - timelineOffset(contentWidth)
                let relative = (drag.location.x - originX) / contentWidth
                let newTime = clamp(Double(relative) * duration)

                // ⚡ Локальный preview БЕЗ вызова repository
                draggedMarkerPreviewTime = newTime
            }
            .onEnded { _ in
                guard draggedMarkerID == marker.id else { return }

                // ⚡ Только при завершении коммитим в repository
                if let finalTime = draggedMarkerPreviewTime {
                    onCommitMoveMarker(marker.id, finalTime)
                }

                draggedMarkerID = nil
                draggedMarkerPreviewTime = nil
            }
    }

    // MARK: - Subviews

    private func waveformView(width: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: width, height: Self.barHeight)

            HStack(spacing: Self.spacing) {
                ForEach(waveform.indices, id: \.self) { i in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(
                            width: Self.barWidth,
                            height: max(12, CGFloat(waveform[i]) * Self.barHeight)
                        )
                }
            }
        }
    }

    // MARK: - Helpers

    private func timelineOffset(_ contentWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(currentTime / duration) * contentWidth
    }

    private func clamp(_ t: Double) -> Double {
        min(max(t, 0), duration)
    }
}
