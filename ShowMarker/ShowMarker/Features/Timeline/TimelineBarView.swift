import SwiftUI

struct TimelineBarView: View {

    let duration: Double
    let currentTime: Double

    let waveform: [Float]
    let markers: [TimelineMarker]

    let hasAudio: Bool

    let onAddAudio: () -> Void
    let onSeek: (Double) -> Void
    let onZoomChange: (CGFloat) -> Void

    let onPreviewMoveMarker: (UUID, Double) -> Void
    let onCommitMoveMarker: (UUID, Double) -> Void

    // MARK: - Zoom state
    
    @State private var zoomScale: CGFloat = 1.0
    @State private var isPinching: Bool = false
    @State private var lastMagnification: CGFloat = 1.0
    
    // Drag state для капсулы
    @State private var capsuleDragStart: CGFloat?
    
    // MARK: - Constants

    private static let barHeight: CGFloat = 140
    private static let baseBarWidth: CGFloat = 0.8  // Очень тонкие линии
    private static let baseSpacing: CGFloat = 0.2
    private static let playheadLineWidth: CGFloat = 2
    private static let markerLineWidth: CGFloat = 3
    
    // Zoom limits
    private static let minZoom: CGFloat = 1.0
    private static let maxZoom: CGFloat = 20.0
    
    // Timeline indicator
    private static let indicatorHeight: CGFloat = 6
    
    // Time ruler
    private static let rulerHeight: CGFloat = 24

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
        VStack(spacing: 8) {
            
            // Timeline overview indicator
            timelineOverviewIndicator
            
            // Time ruler
            if hasAudio {
                timeRuler
            }
            
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
                
                let idealOffset = centerOffset - visibleWidth / 2
                let xOffset = max(0, min(geo.size.width - visibleWidth, idealOffset))
                
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
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if capsuleDragStart == nil {
                                    capsuleDragStart = xOffset
                                }
                                
                                guard let startOffset = capsuleDragStart else { return }
                                
                                let newX = startOffset + value.translation.width
                                let clampedX = max(0, min(geo.size.width - visibleWidth, newX))
                                
                                let newTimeRatio = (clampedX + visibleWidth / 2) / geo.size.width
                                onSeek(duration * newTimeRatio)
                            }
                            .onEnded { _ in
                                capsuleDragStart = nil
                            }
                    )
                
                // Playhead indicator line
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: Self.indicatorHeight + 4)
                    .offset(x: centerOffset - 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: Self.indicatorHeight)
        .padding(.horizontal, 4)
    }
    
    // MARK: - Time Ruler
    
    private var timeRuler: some View {
        GeometryReader { geo in
            let pairCount = waveform.count / 2
            let contentWidth = max(CGFloat(pairCount) * (barWidth + spacing), geo.size.width)
            let centerX = geo.size.width / 2
            
            Canvas { context, size in
                let offset = timelineOffset(contentWidth)
                
                let interval = timeInterval(for: zoomScale)
                let smallInterval = interval / 5.0
                
                var time: Double = 0
                while time <= duration {
                    let x = centerX - offset + CGFloat(time / duration) * contentWidth
                    
                    guard x >= 0 && x <= size.width else {
                        time += smallInterval
                        continue
                    }
                    
                    let isMajor = Int(time / interval) * Int(interval) == Int(time)
                    
                    if isMajor {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: size.height - 12))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(.secondary.opacity(0.6)), lineWidth: 1.5)
                        
                        let timeText = formatTime(time)
                        context.draw(
                            Text(timeText)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary),
                            at: CGPoint(x: x, y: 6)
                        )
                    } else {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: size.height - 6))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
                    }
                    
                    time += smallInterval
                }
            }
            .frame(height: Self.rulerHeight)
        }
        .frame(height: Self.rulerHeight)
    }
    
    private func timeInterval(for zoom: CGFloat) -> Double {
        switch zoom {
        case 0...2: return 10.0
        case 2...5: return 5.0
        case 5...10: return 2.0
        default: return 1.0
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    // MARK: - Timeline Content
    
    private func timelineContent(geo: GeometryProxy) -> some View {
        let centerX = geo.size.width / 2
        let baseWidth = geo.size.width
        let pairCount = waveform.count / 2
        let contentWidth = max(baseWidth * zoomScale, CGFloat(pairCount) * (barWidth + spacing))
        let secondsPerPixel = duration > 0 ? duration / Double(contentWidth) : 0

        return ZStack {
            waveformView(width: contentWidth, geoWidth: geo.size.width)
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
                
                let delta = value / lastMagnification
                let newScale = zoomScale * delta
                let clamped = min(max(newScale, Self.minZoom), Self.maxZoom)
                zoomScale = clamped
                onZoomChange(clamped)
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

    // MARK: - Subviews (REAPER-STYLE WAVEFORM)

    private func waveformView(width: CGFloat, geoWidth: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: width, height: Self.barHeight)

            // Canvas для Reaper-style waveform с заливкой
            Canvas { context, size in
                let pairCount = waveform.count / 2
                guard pairCount > 0 else { return }
                
                let totalWidth = CGFloat(pairCount) * (barWidth + spacing)
                let scale = width / totalWidth
                let centerY = Self.barHeight / 2
                
                for i in 0..<pairCount {
                    let minIndex = i * 2
                    let maxIndex = i * 2 + 1
                    
                    guard maxIndex < waveform.count else { break }
                    
                    let minValue = waveform[minIndex]  // Отрицательное значение
                    let maxValue = waveform[maxIndex]  // Положительное значение
                    
                    let x = CGFloat(i) * (barWidth + spacing) * scale
                    
                    // Верхняя часть (от центра вверх)
                    let topHeight = CGFloat(maxValue) * (Self.barHeight / 2)
                    let topY = centerY - topHeight
                    
                    // Нижняя часть (от центра вниз)
                    let bottomHeight = CGFloat(abs(minValue)) * (Self.barHeight / 2)
                    
                    // Рисуем сплошную вертикальную линию от min до max
                    let path = Path { p in
                        p.move(to: CGPoint(x: x, y: topY))
                        p.addLine(to: CGPoint(x: x, y: centerY + bottomHeight))
                    }
                    
                    context.stroke(
                        path,
                        with: .color(.secondary.opacity(0.75)),
                        lineWidth: max(0.5, barWidth * scale)
                    )
                }
                
                // Центральная линия
                var centerLine = Path()
                centerLine.move(to: CGPoint(x: 0, y: centerY))
                centerLine.addLine(to: CGPoint(x: width, y: centerY))
                context.stroke(centerLine, with: .color(.secondary.opacity(0.2)), lineWidth: 1)
            }
            .frame(width: width, height: Self.barHeight)
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
