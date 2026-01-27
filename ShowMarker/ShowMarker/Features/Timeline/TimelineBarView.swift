import SwiftUI

struct TimelineBarView: View {

    let duration: Double
    let currentTime: Double

    let waveform: [Float]
    let waveform2: [Float]?  // Second waveform for 4-channel audio (channels 3-4)
    let markers: [TimelineMarker]
    let tags: [Tag]  // Tags for coloring markers

    let fps: Int  // Project FPS for frame-based ruler divisions

    // Beat grid parameters
    let bpm: Double?
    let isBeatGridEnabled: Bool
    let isSnapToGridEnabled: Bool

    let hasAudio: Bool

    let onAddAudio: () -> Void
    let onSeek: (Double) -> Void

    let onPreviewMoveMarker: (UUID, Double) -> Void
    let onCommitMoveMarker: (UUID, Double) -> Void

    // MARK: - Zoom state (Binding to ViewModel for synchronization)

    @Binding var zoomScale: CGFloat
    @State private var isPinching: Bool = false
    @State private var lastMagnification: CGFloat = 1.0
    @GestureState private var pinchMagnification: CGFloat = 1.0  // Resets automatically when gesture ends
    @State private var pinchBaseZoom: CGFloat = 1.0  // Base zoom when pinch started

    // Double-tap zoom state (hold second tap + drag)
    @State private var isDoubleTapZoomMode: Bool = false
    @State private var doubleTapStartZoom: CGFloat = 1.0
    @State private var lastTapTime: Date?
    @State private var doubleTapZoomStartX: CGFloat = 0
    @State private var doubleTapHoldStartLocation: CGPoint?

    @State private var capsuleDragStart: CGFloat?

    // MARK: - Marker Drag State (Bindings to ViewModel)

    @Binding var draggedMarkerID: UUID?
    @Binding var draggedMarkerPreviewTime: Double?

    // MARK: - Constants

    private static let barHeight: CGFloat = 140
    private static let playheadLineWidth: CGFloat = 2
    private static let markerLineWidth: CGFloat = 3

    private static let minZoom: CGFloat = 1.0
    private static let maxZoom: CGFloat = 500.0

    private static let indicatorHeight: CGFloat = 6
    private static let rulerHeight: CGFloat = 24

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
            let totalWidth = geo.size.width
            let visibleRatio = 1.0 / zoomScale
            let visibleWidth = max(20, totalWidth * visibleRatio)
            
            // Normalized playhead position (0...1)
            let timeRatio = duration > 0 ? effectiveCurrentTime() / duration : 0
            
            // Capsule position - centered on playhead, clamped to edges
            let capsuleCenterIdeal = totalWidth * timeRatio
            let halfCapsule = visibleWidth / 2
            let capsuleCenter = max(halfCapsule, min(totalWidth - halfCapsule, capsuleCenterIdeal))
            let xOffset = capsuleCenter - halfCapsule

            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: Self.indicatorHeight)

                // Visible area capsule
                Capsule()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: visibleWidth, height: Self.indicatorHeight)
                    .offset(x: xOffset)
                    .overlay(
                        Capsule()
                            .stroke(Color.accentColor, lineWidth: 1)
                            .frame(width: visibleWidth, height: Self.indicatorHeight)
                            .offset(x: xOffset)
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if capsuleDragStart == nil {
                                    capsuleDragStart = xOffset
                                    capsuleDragTime = effectiveCurrentTime()
                                    isCapsuleDragging = true
                                    capsuleDragEndTime = nil
                                }

                                guard let startOffset = capsuleDragStart else { return }

                                let newX = startOffset + value.translation.width
                                let clampedX = max(0, min(totalWidth - visibleWidth, newX))

                                let newTimeRatio = (clampedX + halfCapsule) / totalWidth
                                let newTime = duration * newTimeRatio

                                capsuleDragTime = newTime
                                onSeek(newTime)
                            }
                            .onEnded { _ in
                                capsuleDragStart = nil
                                isCapsuleDragging = false
                                capsuleDragEndTime = Date()
                            }
                    )

                // Mini playhead
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: Self.indicatorHeight + 4)
                    .offset(x: {
                        let idealCapsuleCenter = totalWidth * timeRatio
                        let actualCapsuleCenter = capsuleCenter
                        let capsuleShift = actualCapsuleCenter - idealCapsuleCenter
                        let miniPlayheadX = actualCapsuleCenter - capsuleShift
                        let minX = xOffset + 1
                        let maxX = xOffset + visibleWidth - 1
                        let clampedX = max(minX, min(maxX, miniPlayheadX))
                        return clampedX - 1
                    }())
                    .allowsHitTesting(false)
            }
        }
        .frame(height: Self.indicatorHeight)
        .padding(.horizontal, 4)
    }
    
    // MARK: - Time Ruler (Completely Rewritten)

    private var timeRuler: some View {
        GeometryReader { geo in
            let viewportWidth = geo.size.width
            let contentWidth = viewportWidth * zoomScale
            let effectiveTime = effectiveCurrentTime()
            
            // Calculate visible time range
            let secondsPerPixel = duration / contentWidth
            let visibleDuration = viewportWidth * secondsPerPixel
            let visibleStartTime = max(0, effectiveTime - visibleDuration / 2)
            let visibleEndTime = min(duration, effectiveTime + visibleDuration / 2)
            
            // Choose optimal interval based on pixel density
            let (majorInterval, minorPerMajor) = chooseTimeInterval(
                secondsPerPixel: secondsPerPixel,
                viewportWidth: viewportWidth
            )
            let minorInterval = majorInterval / Double(minorPerMajor)
            
            Canvas { context, size in
                guard duration > 0 else { return }
                
                // Calculate the offset for positioning
                // Center of viewport = effectiveTime
                let centerX = size.width / 2
                
                // Function to convert time to X coordinate
                func timeToX(_ time: Double) -> CGFloat {
                    let deltaTime = time - effectiveTime
                    let deltaPixels = deltaTime / secondsPerPixel
                    return centerX + deltaPixels
                }
                
                // Extend range slightly for smooth scrolling
                let drawStartTime = floor((visibleStartTime - majorInterval) / minorInterval) * minorInterval
                let drawEndTime = ceil((visibleEndTime + majorInterval) / minorInterval) * minorInterval
                
                // Collect all major tick positions first to check for label overlap
                var majorTicks: [(time: Double, x: CGFloat)] = []
                var time = ceil(max(0, drawStartTime) / majorInterval) * majorInterval
                while time <= min(duration, drawEndTime) {
                    let x = timeToX(time)
                    majorTicks.append((time, x))
                    time += majorInterval
                }
                
                // Calculate minimum label spacing (based on typical label width)
                let minLabelSpacing: CGFloat = 50  // Minimum pixels between label centers
                
                // Filter labels to prevent overlap
                var visibleLabels: [(time: Double, x: CGFloat)] = []
                for tick in majorTicks {
                    // Check if this label would overlap with the last visible label
                    if let lastLabel = visibleLabels.last {
                        if tick.x - lastLabel.x < minLabelSpacing {
                            continue  // Skip this label
                        }
                    }
                    // Check if label is within viewport (with padding for partial visibility)
                    let labelHalfWidth: CGFloat = 25
                    if tick.x >= -labelHalfWidth && tick.x <= size.width + labelHalfWidth {
                        visibleLabels.append(tick)
                    }
                }
                
                // Draw minor ticks
                time = max(0, floor(drawStartTime / minorInterval) * minorInterval)
                while time <= min(duration, drawEndTime) {
                    let x = timeToX(time)
                    
                    // Only draw if within viewport
                    if x >= -1 && x <= size.width + 1 {
                        // Check if this is a major tick position
                        let isMajor = isNearMajorTick(time: time, majorInterval: majorInterval)
                        
                        if !isMajor {
                            // Draw minor tick
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: size.height - 5))
                            path.addLine(to: CGPoint(x: x, y: size.height))
                            context.stroke(path, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
                        }
                    }
                    time += minorInterval
                }
                
                // Draw major ticks and labels
                for tick in majorTicks {
                    let x = tick.x
                    
                    // Only draw tick if within viewport
                    if x >= -1 && x <= size.width + 1 {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: size.height - 10))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(.secondary.opacity(0.7)), lineWidth: 1.5)
                    }
                }
                
                // Draw labels only for non-overlapping positions
                for label in visibleLabels {
                    let timeText = formatTimeLabel(label.time, interval: majorInterval)
                    context.draw(
                        Text(timeText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary),
                        at: CGPoint(x: label.x, y: 6)
                    )
                }
            }
            .frame(height: Self.rulerHeight)
        }
        .frame(height: Self.rulerHeight)
    }
    
    /// Choose optimal time interval based on zoom level
    /// Returns (majorInterval in seconds, number of minor ticks per major)
    private func chooseTimeInterval(secondsPerPixel: Double, viewportWidth: CGFloat) -> (Double, Int) {
        // Target: 80-150 pixels between major ticks
        let targetMajorSpacing: CGFloat = 100
        let targetSecondsPerMajor = Double(targetMajorSpacing) * secondsPerPixel

        // Build intervals list with FPS-based divisions at very high zoom
        var intervals: [(Double, Int)] = []

        // At very high zoom (when fps intervals would be useful)
        let frameInterval = 1.0 / Double(fps)

        // Add frame-based intervals dynamically if at high zoom
        if secondsPerPixel < frameInterval * 2 {
            // For each frame multiple (1 frame, 2 frames, 5 frames, 10 frames, etc.)
            let frameMultiples = [1, 2, 5, 10, 20, 50, 100]
            for multiple in frameMultiples {
                let interval = frameInterval * Double(multiple)
                // Choose subdivision count based on multiple
                let subdivisions = multiple <= 5 ? 5 : (multiple <= 10 ? 10 : 5)
                intervals.append((interval, subdivisions))

                // Stop adding if interval gets too large
                if interval > 0.5 {
                    break
                }
            }
        }

        // Add standard intervals
        let standardIntervals: [(Double, Int)] = [
            // Milliseconds/centiseconds (for very high zoom)
            (0.01, 10),    // 10ms, 10 subdivisions = 1ms minor
            (0.02, 10),    // 20ms
            (0.05, 5),     // 50ms, 5 subdivisions = 10ms minor
            (0.1, 10),     // 100ms
            (0.2, 10),     // 200ms
            (0.5, 5),      // 500ms
            // Seconds
            (1, 10),       // 1s, 10 subdivisions = 100ms minor
            (2, 10),       // 2s
            (5, 5),        // 5s
            (10, 10),      // 10s
            (15, 3),       // 15s
            (30, 6),       // 30s
            // Minutes
            (60, 6),       // 1min, 6 subdivisions = 10s minor
            (120, 4),      // 2min
            (300, 5),      // 5min
            (600, 10),     // 10min
            // Hours
            (1800, 6),     // 30min
            (3600, 6),     // 1h
        ]

        intervals.append(contentsOf: standardIntervals)

        // Find the interval closest to target
        var bestInterval = intervals[0]
        var bestDiff = Double.infinity

        for interval in intervals {
            let diff = abs(interval.0 - targetSecondsPerMajor)
            if diff < bestDiff {
                bestDiff = diff
                bestInterval = interval
            }
        }

        // Verify spacing won't cause overlap
        let pixelsPerMajor = bestInterval.0 / secondsPerPixel
        if pixelsPerMajor < 50 {
            // Need larger interval - find next one up
            for interval in intervals where interval.0 > bestInterval.0 {
                let spacing = interval.0 / secondsPerPixel
                if spacing >= 50 {
                    return interval
                }
            }
        }

        return bestInterval
    }
    
    /// Check if time is near a major tick position
    private func isNearMajorTick(time: Double, majorInterval: Double) -> Bool {
        let remainder = time.truncatingRemainder(dividingBy: majorInterval)
        let threshold = majorInterval * 0.001  // 0.1% tolerance
        return remainder < threshold || (majorInterval - remainder) < threshold
    }
    
    /// Format time label based on the interval scale
    private func formatTimeLabel(_ seconds: Double, interval: Double) -> String {
        let frameInterval = 1.0 / Double(fps)

        // Check if this is a frame-based interval
        if interval < frameInterval * 1.5 && interval > 0 {
            // Frame-based display
            let totalFrames = Int(round(seconds * Double(fps)))
            let frames = totalFrames % fps
            let totalSeconds = totalFrames / fps
            let secs = totalSeconds % 60
            let minutes = totalSeconds / 60
            let hours = minutes / 60
            let mins = minutes % 60

            if hours > 0 {
                return String(format: "%d:%02d:%02d:%02d", hours, mins, secs, frames)
            } else if minutes > 0 {
                return String(format: "%d:%02d:%02d", minutes, secs, frames)
            } else {
                return String(format: "%d:%02d", secs, frames)
            }
        }

        // Standard time-based display
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        let hours = minutes / 60
        let mins = minutes % 60

        if interval >= 3600 {
            // Hours scale
            return "\(hours)h"
        } else if interval >= 60 {
            // Minutes scale
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, mins, secs)
            }
            return String(format: "%d:%02d", minutes, secs)
        } else if interval >= 1 {
            // Seconds scale
            return String(format: "%d:%02d", minutes, secs)
        } else if interval >= 0.1 {
            // Tenths scale
            let tenths = Int((seconds - floor(seconds)) * 10)
            return String(format: "%d:%02d.%d", minutes, secs, tenths)
        } else {
            // Centiseconds/milliseconds scale
            let centis = Int((seconds - floor(seconds)) * 100)
            return String(format: "%d:%02d.%02d", minutes, secs, centis)
        }
    }
    
    // MARK: - Timeline Content

    private func timelineContent(geo: GeometryProxy) -> some View {
        let centerX = geo.size.width / 2
        let contentWidth = max(geo.size.width * zoomScale, geo.size.width)
        let secondsPerPixel = duration > 0 ? duration / Double(contentWidth) : 0
        let offset = timelineOffset(contentWidth)

        return ZStack {
            cachedWaveformView(width: contentWidth)
                .offset(x: centerX - offset)

            ForEach(Array(markers.enumerated()), id: \.element.id) { index, marker in
                let displayTime: Double = {
                    if draggedMarkerID == marker.id, let previewTime = draggedMarkerPreviewTime {
                        return previewTime
                    }
                    return marker.timeSeconds
                }()

                let normalizedPosition = displayTime / max(duration, 0.0001)
                let markerX = centerX - offset + (normalizedPosition * contentWidth)

                // Get tag color for this marker
                let markerColor: Color = {
                    if let tag = tags.first(where: { $0.id == marker.tagId }) {
                        return Color(hex: tag.colorHex)
                    }
                    return .orange // Fallback color
                }()

                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(markerColor)
                        .frame(width: Self.markerLineWidth, height: Self.barHeight)

                    // Marker number label at the top
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 18)
                        .background(markerColor)
                        .cornerRadius(3)
                }
                .position(x: markerX, y: Self.barHeight / 2)
                .simultaneousGesture(TapGesture().onEnded {
                    onSeek(marker.timeSeconds)
                })
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
        .gesture(doubleTapGesture())
        .gesture(playheadDrag(secondsPerPixel: secondsPerPixel))
        .simultaneousGesture(pinchGesture())
    }
    
    // MARK: - Add Audio Button

    private var addAudioButton: some View {
        Button {
            print("🎵 [AddAudio] Button tapped - calling onAddAudio")
            onAddAudio()
        } label: {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.12))
                .overlay {
                    Label("Добавить аудиофайл", systemImage: "plus")
                        .font(.headline)
                        .foregroundColor(.accentColor)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)  // Fill GeometryReader space
        .contentShape(Rectangle())  // Ensure entire area is tappable
    }

    // MARK: - Gestures

    private func doubleTapGesture() -> some Gesture {
        TapGesture(count: 1)
            .onEnded { _ in
                // Record tap time for double-tap-hold detection
                lastTapTime = Date()
            }
    }

    private func playheadDrag(secondsPerPixel: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard draggedMarkerID == nil, !isPinching else { return }

                // Check for double-tap-hold zoom gesture:
                // If there was a recent tap (< 400ms before drag started), enter zoom mode
                if !isDoubleTapZoomMode && doubleTapHoldStartLocation == nil {
                    if let tapTime = lastTapTime {
                        let timeSinceTap = Date().timeIntervalSince(tapTime)
                        if timeSinceTap < 0.4 {
                            // This is a double-tap-hold gesture - enable zoom mode
                            isDoubleTapZoomMode = true
                            doubleTapStartZoom = zoomScale
                            doubleTapHoldStartLocation = value.startLocation
                            doubleTapZoomStartX = value.startLocation.x
                        }
                    }
                }

                // Handle double-tap-hold zoom mode
                if isDoubleTapZoomMode {
                    let translation = value.location.x - doubleTapZoomStartX
                    // Dragging right increases zoom, left decreases zoom
                    // Sensitivity: every 50 pixels of drag = 1x zoom multiplier
                    let zoomMultiplier = 1.0 + (Double(translation) / 50.0)
                    let newScale = doubleTapStartZoom * max(zoomMultiplier, 0.1) // Allow zooming out more
                    let clamped = min(max(newScale, Self.minZoom), Self.maxZoom)
                    zoomScale = clamped
                    return
                }

                // Regular playhead seeking
                if dragStartTime == nil {
                    dragStartTime = currentTime
                    dragCurrentTime = currentTime
                    isTimelineDragging = true
                    dragEndTime = nil
                }
                guard let start = dragStartTime else { return }

                let delta = Double(value.translation.width) * secondsPerPixel * -1
                dragCurrentTime = clamp(start + delta)
                onSeek(dragCurrentTime)
            }
            .onEnded { _ in
                if isDoubleTapZoomMode {
                    // Reset zoom mode after drag ends
                    isDoubleTapZoomMode = false
                    doubleTapZoomStartX = 0
                    doubleTapHoldStartLocation = nil
                    lastTapTime = nil
                } else {
                    // Regular playhead seeking cleanup
                    dragStartTime = nil
                    isTimelineDragging = false
                    dragEndTime = Date()
                }
            }
    }
    
    private func pinchGesture() -> some Gesture {
        MagnificationGesture()
            .updating($pinchMagnification) { currentState, gestureState, _ in
                // Update gesture state - this automatically resets when gesture ends
                gestureState = currentState
            }
            .onChanged { value in
                if !isPinching {
                    isPinching = true
                    pinchBaseZoom = zoomScale
                }

                // Calculate new zoom directly from base zoom * magnification
                // This ensures zoom only changes with actual two-finger pinch
                let newScale = pinchBaseZoom * value
                let clamped = min(max(newScale, Self.minZoom), Self.maxZoom)
                zoomScale = clamped
            }
            .onEnded { _ in
                isPinching = false
                pinchBaseZoom = zoomScale
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
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard
                    case .second(true, let drag?) = value,
                    draggedMarkerID == marker.id
                else { return }

                let offset = timelineOffset(contentWidth)
                let originX = centerX - offset
                let normalizedPosition = (drag.location.x - originX) / contentWidth
                let rawTime = clamp(normalizedPosition * duration)

                // Apply snap to beat grid if enabled
                let newTime = snapToBeat(rawTime)

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

    // MARK: - Waveform

    @ViewBuilder
    private func cachedWaveformView(width: CGFloat) -> some View {
        directWaveformView(width: width)
    }

    private func directWaveformView(width: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: width, height: Self.barHeight)

            Canvas { context, size in
                let pairCount = waveform.count / 2
                guard pairCount > 0 else { return }

                let canvasWidth = size.width
                let amplitudeScale: CGFloat = 0.85
                let fillColor = Color.secondary.opacity(0.5)

                // For 4-channel audio, display two waveforms (top and bottom)
                let hasSecondWaveform = waveform2 != nil && (waveform2?.isEmpty == false)
                let waveformCount = hasSecondWaveform ? 2 : 1
                let barHeightPerWaveform = Self.barHeight / CGFloat(waveformCount)

                // Draw waveforms
                for waveformIndex in 0..<waveformCount {
                    let currentWaveform = waveformIndex == 0 ? waveform : (waveform2 ?? [])
                    let currentPairCount = currentWaveform.count / 2
                    guard currentPairCount > 0 else { continue }

                    let centerY = (CGFloat(waveformIndex) + 0.5) * barHeightPerWaveform

                    var upperPath = Path()
                    var lowerPath = Path()

                    for i in 0..<currentPairCount {
                        let minIndex = i * 2
                        let maxIndex = i * 2 + 1

                        guard maxIndex < currentWaveform.count else { break }

                        let minValue = currentWaveform[minIndex]
                        let maxValue = currentWaveform[maxIndex]

                        let normalizedPosition = Double(i) / Double(max(currentPairCount - 1, 1))
                        let x = normalizedPosition * canvasWidth

                        let topY = centerY - CGFloat(maxValue) * (barHeightPerWaveform / 2) * amplitudeScale
                        let bottomY = centerY - CGFloat(minValue) * (barHeightPerWaveform / 2) * amplitudeScale

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

                    context.fill(upperPath, with: .color(fillColor))
                    context.fill(lowerPath, with: .color(fillColor))
                }

                // Draw beat grid if enabled
                if isBeatGridEnabled, let bpm = bpm, bpm > 0, duration > 0 {
                    let beatInterval = 60.0 / bpm  // seconds per beat
                    let beatCount = Int(ceil(duration / beatInterval))

                    for i in 0...beatCount {
                        let beatTime = Double(i) * beatInterval
                        let normalizedPosition = beatTime / duration
                        let x = normalizedPosition * canvasWidth

                        // Draw vertical line
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))

                        // First beat of each bar (every 4 beats) is slightly brighter
                        let isBarLine = i % 4 == 0
                        let lineColor = isBarLine ? Color.secondary.opacity(0.35) : Color.secondary.opacity(0.2)
                        let lineWidth: CGFloat = isBarLine ? 1.8 : 1.5

                        context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
                    }
                }
            }
            .frame(width: width, height: Self.barHeight)
        }
    }

    // MARK: - Helpers

    private func effectiveCurrentTime() -> Double {
        if isCapsuleDragging {
            return capsuleDragTime
        } else if let endTime = capsuleDragEndTime {
            let timeSinceDragEnd = Date().timeIntervalSince(endTime)
            if timeSinceDragEnd < 0.1 && abs(capsuleDragTime - currentTime) > 0.05 {
                return capsuleDragTime
            }
        }

        if isTimelineDragging {
            return dragCurrentTime
        } else if let endTime = dragEndTime {
            let timeSinceDragEnd = Date().timeIntervalSince(endTime)
            if timeSinceDragEnd < 0.1 && abs(dragCurrentTime - currentTime) > 0.05 {
                return dragCurrentTime
            }
        }

        return currentTime
    }

    private func timelineOffset(_ contentWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(effectiveCurrentTime() / duration) * contentWidth
    }

    private func clamp(_ t: Double) -> Double {
        min(max(t, 0), duration)
    }

    /// Квантует время к ближайшему биту, если включена привязка к сетке
    private func snapToBeat(_ time: Double) -> Double {
        guard isSnapToGridEnabled, let bpm = bpm, bpm > 0 else {
            return time
        }

        let beatInterval = 60.0 / bpm  // seconds per beat
        let beatNumber = round(time / beatInterval)
        return beatNumber * beatInterval
    }
}
