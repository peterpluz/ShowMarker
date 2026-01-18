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

            let timeRatio = duration > 0 ? currentTime / duration : 0
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

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: Self.indicatorHeight + 4)
                    .offset(x: xOffset + visibleWidth / 2 - 1)
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
                let interval = timeInterval(for: zoomScale)
                let smallInterval = interval / 5.0

                // ✅ ИСПРАВЛЕНО: расчет видимого диапазона с учетом полной ширины
                let visibleWidthSeconds = duration / zoomScale
                let visibleStartTime = max(0, currentTime - visibleWidthSeconds / 2)
                let visibleEndTime = min(duration, currentTime + visibleWidthSeconds / 2)

                // Начинаем с округленного значения
                let startTime = floor(visibleStartTime / smallInterval) * smallInterval

                var time = startTime
                while time <= visibleEndTime + smallInterval {
                    let normalizedPosition = time / duration
                    let x = centerX - offset + (normalizedPosition * contentWidth)

                    // ✅ ИСПРАВЛЕНО: расширенная область отрисовки
                    guard x >= -50 && x <= size.width + 50 else {
                        time += smallInterval
                        continue
                    }

                    let isMajor = abs(time.truncatingRemainder(dividingBy: interval)) < 0.001

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
        // ✅ ИСПРАВЛЕНО: более плавные переходы интервалов
        switch zoom {
        case 0...1.2: return 30.0
        case 1.2...2.0: return 10.0
        case 2.0...4.0: return 5.0
        case 4.0...8.0: return 2.0
        case 8.0...15: return 1.0
        case 15...30: return 0.5
        case 30...60: return 0.2
        case 60...120: return 0.1
        case 120...250: return 0.05
        default: return 0.02
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        if zoomScale > 100 {
            let ms = Int((seconds - floor(seconds)) * 1000)
            let totalSeconds = Int(seconds)
            let minutes = totalSeconds / 60
            let secs = totalSeconds % 60
            return String(format: "%d:%02d.%03d", minutes, secs, ms)
        } else {
            let totalSeconds = Int(seconds)
            let minutes = totalSeconds / 60
            let secs = totalSeconds % 60
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    // MARK: - Timeline Content

    private func timelineContent(geo: GeometryProxy) -> some View {
        let centerX = geo.size.width / 2
        let contentWidth = max(geo.size.width * zoomScale, geo.size.width)
        let secondsPerPixel = duration > 0 ? duration / Double(contentWidth) : 0

        return ZStack {
            // ✅ КРИТИЧНО: Кэшированная waveform view
            cachedWaveformView(width: contentWidth)
                .offset(x: centerX - timelineOffset(contentWidth))

            ForEach(markers) { marker in
                let displayTime: Double = {
                    if draggedMarkerID == marker.id, let previewTime = draggedMarkerPreviewTime {
                        return previewTime
                    }
                    return marker.timeSeconds
                }()

                let normalizedPosition = displayTime / max(duration, 0.0001)
                let markerX = centerX - timelineOffset(contentWidth) + (normalizedPosition * contentWidth)

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

                // ✅ CRITICAL: Use size.width from Canvas, not parameter
                let canvasWidth = size.width

                // ✅ ИСПРАВЛЕНО: адаптивная детализация под зум
                let targetPoints = Int(canvasWidth / 2) // Достаточно для плавности
                let step = max(1, pairCount / targetPoints)
                let pixelsPerSample = canvasWidth / CGFloat(min(pairCount, targetPoints))

                // ✅ ИСПРАВЛЕНО: фиксированная полная амплитуда
                let amplitudeScale: CGFloat = 0.85

                var upperPath = Path()
                var lowerPath = Path()

                var isFirstPoint = true
                var pointIndex = 0

                var i = 0
                while i < pairCount {
                    let minIndex = i * 2
                    let maxIndex = i * 2 + 1

                    guard maxIndex < waveform.count else { break }

                    let minValue = waveform[minIndex]
                    let maxValue = waveform[maxIndex]

                    let x = CGFloat(pointIndex) * pixelsPerSample

                    // ✅ ИСПРАВЛЕНО: симметричное отображение верх/низ
                    let topY = centerY - CGFloat(maxValue) * (Self.barHeight / 2) * amplitudeScale
                    let bottomY = centerY - CGFloat(minValue) * (Self.barHeight / 2) * amplitudeScale

                    if isFirstPoint {
                        upperPath.move(to: CGPoint(x: x, y: centerY))
                        lowerPath.move(to: CGPoint(x: x, y: centerY))
                        isFirstPoint = false
                    }

                    upperPath.addLine(to: CGPoint(x: x, y: topY))
                    lowerPath.addLine(to: CGPoint(x: x, y: bottomY))

                    i += step
                    pointIndex += 1
                }

                if pointIndex > 0 {
                    let lastX = canvasWidth
                    upperPath.addLine(to: CGPoint(x: lastX, y: centerY))
                    lowerPath.addLine(to: CGPoint(x: lastX, y: centerY))
                }

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

    private func timelineOffset(_ contentWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(currentTime / duration) * contentWidth
    }

    private func clamp(_ t: Double) -> Double {
        min(max(t, 0), duration)
    }
}
