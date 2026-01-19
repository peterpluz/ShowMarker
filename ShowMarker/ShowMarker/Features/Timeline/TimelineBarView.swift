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

    // MARK: - Zoom state (Binding to ViewModel for synchronization)

    @Binding var zoomScale: CGFloat
    @State private var isPinching: Bool = false
    @State private var lastMagnification: CGFloat = 1.0

    @State private var capsuleDragStart: CGFloat?

    // MARK: - Constants

    private static let barHeight: CGFloat = 140
    private static let playheadLineWidth: CGFloat = 2
    private static let markerLineWidth: CGFloat = 3

    private static let minZoom: CGFloat = 1.0
    private static let maxZoom: CGFloat = 500.0

    private static let indicatorHeight: CGFloat = 6
    private static let rulerHeight: CGFloat = 24

    @State private var draggedMarkerID: UUID?
    @State private var draggedMarkerPreviewTime: Double?
    @State private var dragStartTime: Double?

    // MARK: - Timeline Drag State
    @State private var isTimelineDragging: Bool = false
    @State private var dragCurrentTime: Double = 0
    @State private var dragEndTime: Date?

    // MARK: - Capsule Drag State
    @State private var isCapsuleDragging: Bool = false
    @State private var capsuleDragTime: Double = 0
    @State private var capsuleDragEndTime: Date?

    var body: some View {
        VStack(spacing: 8) {
            if hasAudio {
                timelineOverviewIndicator
                timeRuler
            }

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
    
    // MARK: - Timeline Overview Indicator

    private var timelineOverviewIndicator: some View {
        GeometryReader { geo in
            let visibleRatio = 1.0 / zoomScale
            let visibleWidth = geo.size.width * visibleRatio

            // ✅ FIX: Use effectiveCurrentTime for smooth 1:1 feedback
            let timeRatio = duration > 0 ? effectiveCurrentTime() / duration : 0
            let centerOffset = geo.size.width * timeRatio

            let idealOffset = centerOffset - visibleWidth / 2
            let xOffset = max(0, min(geo.size.width - visibleWidth, idealOffset))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: Self.indicatorHeight)

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
                                    capsuleDragTime = effectiveCurrentTime()
                                    isCapsuleDragging = true
                                    capsuleDragEndTime = nil
                                }

                                guard let startOffset = capsuleDragStart else { return }

                                let newX = startOffset + value.translation.width
                                let clampedX = max(0, min(geo.size.width - visibleWidth, newX))

                                let newTimeRatio = (clampedX + visibleWidth / 2) / geo.size.width
                                let newTime = duration * newTimeRatio

                                // ✅ FIX: Store local drag time immediately for smooth visual feedback
                                capsuleDragTime = newTime

                                // Update audio playback (throttled)
                                onSeek(newTime)
                            }
                            .onEnded { _ in
                                capsuleDragStart = nil
                                isCapsuleDragging = false
                                capsuleDragEndTime = Date()
                            }
                    )

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: Self.indicatorHeight + 4)
                    .offset(x: {
                        // ✅ FIX: Mini playhead positioning logic
                        // When capsule is NOT clamped (centered on playhead): mini playhead in center
                        // When capsule IS clamped (at edges): mini playhead shows real position

                        let idealOffset = centerOffset - visibleWidth / 2
                        let playheadIdealX = geo.size.width * timeRatio

                        // Check if capsule is clamped
                        if abs(idealOffset - xOffset) < 0.1 {
                            // Not clamped - playhead always in center
                            return xOffset + visibleWidth / 2 - 1
                        } else {
                            // Clamped at edge - show real playhead position within capsule
                            let playheadX = max(xOffset, min(xOffset + visibleWidth, playheadIdealX))
                            return playheadX - 1
                        }
                    }())
                    .allowsHitTesting(false)
            }
        }
        .frame(height: Self.indicatorHeight)
        .padding(.horizontal, 4)
    }
    
    // MARK: - Time Ruler

    private var timeRuler: some View {
        GeometryReader { geo in
            let contentWidth = max(geo.size.width * zoomScale, geo.size.width)
            let centerX = geo.size.width / 2
            let offset = timelineOffset(contentWidth)

            Canvas { context, size in
                guard duration > 0 else { return }

                // ✅ CRITICAL FIX: Calculate adaptive interval based on pixel density
                let secondsPerPixel = duration / Double(contentWidth)
                let interval = adaptiveTimeInterval(secondsPerPixel: secondsPerPixel)
                let subdivisions = getSubdivisions(for: interval)
                let smallInterval = interval / Double(subdivisions)

                // ✅ Calculate visible time range accurately
                let visibleWidthSeconds = Double(geo.size.width) * secondsPerPixel
                let visibleStartTime = max(0, currentTime - visibleWidthSeconds / 2)
                let visibleEndTime = min(duration, currentTime + visibleWidthSeconds / 2)

                // Start from rounded value
                let startTime = floor(visibleStartTime / smallInterval) * smallInterval

                var time = startTime
                while time <= visibleEndTime + smallInterval {
                    let normalizedPosition = time / duration
                    let x = centerX - offset + (normalizedPosition * contentWidth)

                    // Only draw if in visible area
                    guard x >= -50 && x <= size.width + 50 else {
                        time += smallInterval
                        continue
                    }

                    let isMajor = abs(time.truncatingRemainder(dividingBy: interval)) < 0.0001

                    if isMajor {
                        // Major tick with time label
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: size.height - 12))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(.secondary.opacity(0.7)), lineWidth: 1.5)

                        let timeText = formatTime(time, interval: interval)
                        context.draw(
                            Text(timeText)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary),
                            at: CGPoint(x: x, y: 6)
                        )
                    } else {
                        // Minor tick
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

    /// Calculate optimal time interval based on pixel density (like Pro Tools/Premiere)
    /// Target: 60-120 pixels between major marks
    private func adaptiveTimeInterval(secondsPerPixel: Double) -> Double {
        let targetPixelSpacing: Double = 80.0  // Optimal spacing
        let targetSeconds = secondsPerPixel * targetPixelSpacing

        // Find nearest "nice" interval: 1, 2, 5, 10, 20, 30, 60, 120, 300, 600...
        let niceIntervals: [Double] = [
            0.001, 0.002, 0.005, 0.01, 0.02, 0.05,  // Milliseconds
            0.1, 0.2, 0.5,                           // Sub-second
            1, 2, 5, 10, 15, 30,                     // Seconds
            60, 120, 300, 600, 900, 1800, 3600       // Minutes/Hours
        ]

        // Find closest nice interval
        var bestInterval = niceIntervals[0]
        var minDiff = abs(targetSeconds - bestInterval)

        for interval in niceIntervals {
            let diff = abs(targetSeconds - interval)
            if diff < minDiff {
                minDiff = diff
                bestInterval = interval
            }
        }

        return bestInterval
    }

    /// Get number of subdivisions for an interval (2, 5, or 10)
    private func getSubdivisions(for interval: Double) -> Int {
        // Intervals ending in 1 or 10: divide by 10 (e.g., 1s → 10 parts)
        // Intervals ending in 2: divide by 2 (e.g., 2s → 2 parts)
        // Intervals ending in 5: divide by 5 (e.g., 5s → 5 parts)
        // Intervals ending in 15/30/60: divide by 5 or 10

        if interval < 0.01 {
            return 10
        } else if interval < 0.1 {
            return interval == 0.02 || interval == 0.05 ? 5 : 10
        } else if interval < 1 {
            return interval == 0.2 || interval == 0.5 ? 5 : 10
        } else if interval < 10 {
            return interval == 2.0 ? 2 : (interval == 5.0 ? 5 : 10)
        } else if interval == 15 || interval == 30 {
            return 5
        } else if interval == 60 || interval == 120 {
            return 10
        } else {
            return 5
        }
    }
    
    /// Format time based on interval (adaptive precision like Pro Tools)
    private func formatTime(_ seconds: Double, interval: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        let hours = minutes / 60
        let mins = minutes % 60

        // Choose format based on interval
        if interval >= 3600 {
            // Hours: "1h", "2h"
            return "\(hours)h"
        } else if interval >= 60 {
            // Minutes: "1:00", "2:30"
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, mins, secs)
            }
            return String(format: "%d:%02d", minutes, secs)
        } else if interval >= 1 {
            // Seconds: "0:05", "1:30"
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, mins, secs)
            }
            return String(format: "%d:%02d", minutes, secs)
        } else if interval >= 0.1 {
            // Tenths of second: "0:00.5", "0:01.2"
            let tenths = Int((seconds - floor(seconds)) * 10)
            return String(format: "%d:%02d.%01d", minutes, secs, tenths)
        } else if interval >= 0.01 {
            // Centiseconds: "0:00.05", "0:00.12"
            let centis = Int((seconds - floor(seconds)) * 100)
            return String(format: "%d:%02d.%02d", minutes, secs, centis)
        } else {
            // Milliseconds: "0:00.125", "0:00.250"
            let ms = Int((seconds - floor(seconds)) * 1000)
            return String(format: "%d:%02d.%03d", minutes, secs, ms)
        }
    }
    
    // MARK: - Timeline Content

    private func timelineContent(geo: GeometryProxy) -> some View {
        let centerX = geo.size.width / 2
        let contentWidth = max(geo.size.width * zoomScale, geo.size.width)
        let secondsPerPixel = duration > 0 ? duration / Double(contentWidth) : 0
        let offset = timelineOffset(contentWidth)

        return ZStack {
            // ✅ КРИТИЧНО: Кэшированная waveform view
            cachedWaveformView(width: contentWidth)
                .offset(x: centerX - offset)

            ForEach(markers) { marker in
                let displayTime: Double = {
                    if draggedMarkerID == marker.id, let previewTime = draggedMarkerPreviewTime {
                        return previewTime
                    }
                    return marker.timeSeconds
                }()

                let normalizedPosition = displayTime / max(duration, 0.0001)
                let markerX = centerX - offset + (normalizedPosition * contentWidth)

                Rectangle()
                    .fill(Color.orange)
                    .frame(width: Self.markerLineWidth, height: Self.barHeight)
                    .position(x: markerX, y: Self.barHeight / 2)
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
                    dragCurrentTime = currentTime
                    isTimelineDragging = true
                    dragEndTime = nil  // Clear any previous drag end time
                }
                guard let start = dragStartTime else { return }

                // ✅ FIX: Calculate new time directly from translation
                let delta = Double(value.translation.width) * secondsPerPixel * -1
                dragCurrentTime = clamp(start + delta)

                // Update audio playback (throttled, but visual uses dragCurrentTime)
                onSeek(dragCurrentTime)
            }
            .onEnded { _ in
                dragStartTime = nil
                isTimelineDragging = false
                dragEndTime = Date()  // Mark when drag ended
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
                zoomScale = clamped  // Binding automatically updates ViewModel
                lastMagnification = value
            }
            .onEnded { _ in
                isPinching = false
                lastMagnification = 1.0
            }
    }

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

                let offset = timelineOffset(contentWidth)
                let originX = centerX - offset
                let normalizedPosition = (drag.location.x - originX) / contentWidth
                let newTime = clamp(normalizedPosition * duration)

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

    // MARK: - ✅ КРИТИЧНО: Кэшированная WAVEFORM

    @ViewBuilder
    private func cachedWaveformView(width: CGFloat) -> some View {
        // ✅ ИСПРАВЛЕНО: показываем waveform напрямую без кэширования
        // Кэширование в Image вызывало проблемы с отображением
        directWaveformView(width: width)
    }

    // ✅ ПРЯМОЙ рендер waveform
    private func directWaveformView(width: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: width, height: Self.barHeight)

            Canvas { context, size in
                let pairCount = waveform.count / 2
                guard pairCount > 0 else { return }

                let centerY = Self.barHeight / 2

                // ✅ CRITICAL FIX: Use size.width from Canvas for accuracy
                let canvasWidth = size.width

                // ✅ CRITICAL: Fixed amplitude scale
                let amplitudeScale: CGFloat = 0.85

                var upperPath = Path()
                var lowerPath = Path()

                // ✅ CRITICAL FIX: Remove double downsampling
                // Draw each sample directly using normalized position
                // This ensures waveform matches playhead/marker coordinate space

                for i in 0..<pairCount {
                    let minIndex = i * 2
                    let maxIndex = i * 2 + 1

                    guard maxIndex < waveform.count else { break }

                    let minValue = waveform[minIndex]
                    let maxValue = waveform[maxIndex]

                    // ✅ Use same normalization as markers/playhead
                    let normalizedPosition = Double(i) / Double(max(pairCount - 1, 1))
                    let x = normalizedPosition * canvasWidth

                    // ✅ Symmetric display top/bottom
                    let topY = centerY - CGFloat(maxValue) * (Self.barHeight / 2) * amplitudeScale
                    let bottomY = centerY - CGFloat(minValue) * (Self.barHeight / 2) * amplitudeScale

                    if i == 0 {
                        upperPath.move(to: CGPoint(x: x, y: centerY))
                        lowerPath.move(to: CGPoint(x: x, y: centerY))
                    }

                    upperPath.addLine(to: CGPoint(x: x, y: topY))
                    lowerPath.addLine(to: CGPoint(x: x, y: bottomY))
                }

                upperPath.addLine(to: CGPoint(x: canvasWidth, y: centerY))
                lowerPath.addLine(to: CGPoint(x: canvasWidth, y: centerY))

                upperPath.closeSubpath()
                lowerPath.closeSubpath()

                // Fill waveform areas
                let fillColor = Color.secondary.opacity(0.5)
                context.fill(upperPath, with: .color(fillColor))
                context.fill(lowerPath, with: .color(fillColor))
            }
            .frame(width: width, height: Self.barHeight)
        }
    }

    // MARK: - Helpers

    /// Returns current time to use for visual display, accounting for drag state
    private func effectiveCurrentTime() -> Double {
        // ✅ FIX: Capsule drag takes priority
        if isCapsuleDragging {
            return capsuleDragTime
        } else if let endTime = capsuleDragEndTime {
            let timeSinceDragEnd = Date().timeIntervalSince(endTime)
            if timeSinceDragEnd < 0.1 && abs(capsuleDragTime - currentTime) > 0.05 {
                return capsuleDragTime
            }
        }

        // Timeline drag
        if isTimelineDragging {
            return dragCurrentTime
        } else if let endTime = dragEndTime {
            let timeSinceDragEnd = Date().timeIntervalSince(endTime)
            if timeSinceDragEnd < 0.1 && abs(dragCurrentTime - currentTime) > 0.05 {
                return dragCurrentTime
            }
        }

        // Use throttled currentTime (normal state or after transition)
        return currentTime
    }

    private func timelineOffset(_ contentWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(effectiveCurrentTime() / duration) * contentWidth
    }

    private func clamp(_ t: Double) -> Double {
        min(max(t, 0), duration)
    }
}
