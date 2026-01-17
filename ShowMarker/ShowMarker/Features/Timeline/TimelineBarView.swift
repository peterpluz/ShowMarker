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

    // MARK: - Zoom state
    
    @State private var zoomScale: CGFloat = 1.0
    @State private var isPinching: Bool = false
    @State private var lastMagnification: CGFloat = 1.0
    
    // MARK: - Constants

    private static let barHeight: CGFloat = 140
    private static let baseBarWidth: CGFloat = 3
    private static let baseSpacing: CGFloat = 1
    private static let playheadLineWidth: CGFloat = 2
    private static let markerLineWidth: CGFloat = 3
    
    // Zoom limits
    private static let minZoom: CGFloat = 0.5
    private static let maxZoom: CGFloat = 20.0
    
    // Timeline indicator
    private static let indicatorHeight: CGFloat = 6

    // MARK: - Local state для smooth preview
    
    @State private var draggedMarkerID: UUID?
    @State private var draggedMarkerPreviewTime: Double?
    @State private var dragStartTime: Double?

    // MARK: - Computed zoom values
    
    private var barWidth: CGFloat {
        Self.baseBarWidth * zoomScale
    }
    
    private var spacing: CGFloat {
        Self.baseSpacing * zoomScale
    }

    var body: some View {
        VStack(spacing: 12) {
            
            // Timeline overview indicator
            timelineOverviewIndicator
            
            // Timeline bar
            GeometryReader { geo in
                if !hasAudio {
                    addAudioButton
                } else {
                    timelineContent(geo: geo)
                }
            }
            .frame(height: Self.barHeight)
        }
    }
    
    // MARK: - Timeline Overview Indicator (DAW-style)
    
    private var timelineOverviewIndicator: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                
                // Background track
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: Self.indicatorHeight)
                
                // Visible region capsule
                let visibleRatio = 1.0 / zoomScale
                let visibleWidth = geo.size.width * visibleRatio
                
                // Position based on currentTime
                let timeRatio = duration > 0 ? currentTime / duration : 0
                let centerOffset = geo.size.width * timeRatio
                let xOffset = max(0, min(geo.size.width - visibleWidth, centerOffset - visibleWidth / 2))
                
                Capsule()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: max(20, visibleWidth), height: Self.indicatorHeight)
                    .offset(x: xOffset)
                    .overlay(
                        Capsule()
                            .stroke(Color.accentColor, lineWidth: 1)
                            .frame(width: max(20, visibleWidth), height: Self.indicatorHeight)
                            .offset(x: xOffset)
                    )
                
                // Playhead indicator line
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: Self.indicatorHeight + 4)
                    .offset(x: centerOffset - 1)
            }
        }
        .frame(height: Self.indicatorHeight)
        .padding(.horizontal, 4)
    }
    
    // MARK: - Timeline Content
    
    private func timelineContent(geo: GeometryProxy) -> some View {
        let centerX = geo.size.width / 2
        let contentWidth = max(CGFloat(waveform.count) * (barWidth + spacing), 1)
        let secondsPerPixel = duration > 0 ? duration / Double(contentWidth) : 0

        return ZStack {
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
        .simultaneousGesture(pinchGesture())
    }
    
    // MARK: - Add Audio Button
    
    private var addAudioButton: some View {
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
    }

    // MARK: - Gestures

    private func playheadDrag(secondsPerPixel: Double) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard draggedMarkerID == nil, !isPinching else { return }

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
    
    private func pinchGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if !isPinching {
                    isPinching = true
                    lastMagnification = 1.0
                }
                
                // Incremental scaling for 1:1 feel
                let delta = value / lastMagnification
                let newScale = zoomScale * delta
                zoomScale = min(max(newScale, Self.minZoom), Self.maxZoom)
                lastMagnification = value
            }
            .onEnded { _ in
                isPinching = false
                lastMagnification = 1.0
            }
    }

    // MARK: - Marker gesture

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

                draggedMarkerPreviewTime = newTime
            }
            .onEnded { _ in
                guard draggedMarkerID == marker.id else { return }

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

            HStack(spacing: spacing) {
                ForEach(waveform.indices, id: \.self) { i in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(
                            width: barWidth,
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
