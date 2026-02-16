import SwiftUI

/// Displays keyframe tracks below the waveform, one row per tag.
/// Each track shows downward-triangle keyframe indicators at the same timecodes
/// as the corresponding markers. Scroll and playhead are synchronized with
/// the parent waveform via the same time/zoom model.
///
/// Layout: [Label Panel | Resize Handle | Keyframe Area]
/// - Label panel shows tag names (or first letter when collapsed).
/// - Resize handle allows dragging to collapse/expand the label panel.
/// - Keyframe area matches the waveform content width and supports
///   pinch-to-zoom, drag-to-seek, and double-tap-hold zoom gestures.
struct KeyframeTracksView: View {

    let duration: Double          // Audio duration (without preroll)
    let currentTime: Double       // Audio time (without preroll offset)
    let markers: [TimelineMarker]
    let tags: [Tag]
    let prerollSeconds: Double

    // Shared zoom — Binding so keyframe gestures can update it
    @Binding var zoomScale: CGFloat

    // Drag-aware display time (matches TimelineBarView's effectiveDisplayTime)
    let effectiveDisplayTime: Double

    // Gesture callbacks (same as TimelineBarView)
    let onSeek: (Double) -> Void
    var onScrubStart: (() -> Void)? = nil
    var onScrubEnd: (() -> Void)? = nil

    // MARK: - Label Resize State

    @State private var labelWidth: CGFloat = 60
    @State private var labelDragStartWidth: CGFloat? = nil

    private static let labelExpandedWidth: CGFloat = 60
    private static let labelCollapsedWidth: CGFloat = 24
    private static let labelCollapseThreshold: CGFloat = 42

    private var isLabelCollapsed: Bool {
        labelWidth < Self.labelCollapseThreshold
    }

    // MARK: - Zoom Gesture State

    @State private var isPinching: Bool = false
    @State private var pinchBaseZoom: CGFloat = 1.0
    @GestureState private var pinchMagnification: CGFloat = 1.0

    // MARK: - Drag-to-Seek State

    @State private var isDragging: Bool = false
    @State private var dragStartDisplayTime: Double = 0
    @State private var dragStartX: CGFloat = 0

    // MARK: - Double-Tap Zoom State

    @State private var lastTapTime: Date?
    @State private var isDoubleTapZoomMode: Bool = false
    @State private var doubleTapStartZoom: CGFloat = 1.0
    @State private var doubleTapZoomStartX: CGFloat = 0

    // MARK: - Constants

    private static let trackHeight: CGFloat = 22
    private static let keySize: CGFloat = 10

    private static let minZoom: CGFloat = 1.0
    private static let maxZoom: CGFloat = 500.0

    /// Effective timeline duration including preroll
    private var effectiveDuration: Double {
        duration + prerollSeconds
    }

    /// Convert audio time to display time
    private func audioToDisplayTime(_ audioTime: Double) -> Double {
        audioTime + prerollSeconds
    }

    /// Convert display time to audio time
    private func displayToAudioTime(_ displayTime: Double) -> Double {
        displayTime - prerollSeconds
    }

    /// Group markers by tagId
    private var markersByTag: [UUID: [TimelineMarker]] {
        Dictionary(grouping: markers, by: \.tagId)
    }

    /// Tags that have at least one marker, sorted by order
    private var activeTags: [Tag] {
        tags
            .filter { tag in markersByTag[tag.id] != nil }
            .sorted { $0.order < $1.order }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            labelPanel
            labelResizeHandle
            keyframeTracksContent
        }
        .padding(.vertical, 4)
    }

    // MARK: - Label Panel

    private var labelPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(activeTags.enumerated()), id: \.element.id) { index, tag in
                let tagColor = Color(hex: tag.colorHex)

                if index > 0 {
                    Divider().opacity(0.15)
                }

                Group {
                    if isLabelCollapsed {
                        Text(String(tag.name.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(tagColor)
                    } else {
                        Text(tag.name)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(tagColor)
                            .lineLimit(1)
                    }
                }
                .frame(
                    width: labelWidth,
                    height: Self.trackHeight,
                    alignment: isLabelCollapsed ? .center : .leading
                )
                .padding(.leading, isLabelCollapsed ? 0 : 4)
                .background(tagColor.opacity(0.06))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.04))
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Label Resize Handle

    private var labelResizeHandle: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 3)
            .contentShape(Rectangle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if labelDragStartWidth == nil {
                            labelDragStartWidth = labelWidth
                        }
                        guard let startWidth = labelDragStartWidth else { return }
                        let newWidth = startWidth + value.translation.width
                        labelWidth = max(Self.labelCollapsedWidth, min(Self.labelExpandedWidth, newWidth))
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            if labelWidth < Self.labelCollapseThreshold {
                                labelWidth = Self.labelCollapsedWidth
                            } else {
                                labelWidth = Self.labelExpandedWidth
                            }
                        }
                        labelDragStartWidth = nil
                    }
            )
    }

    // MARK: - Keyframe Tracks Content

    private var keyframeTracksContent: some View {
        VStack(spacing: 0) {
            ForEach(Array(activeTags.enumerated()), id: \.element.id) { index, tag in
                if index > 0 {
                    Divider().opacity(0.15)
                }
                keyframeRow(for: tag)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.04))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(gestureOverlay)
    }

    // MARK: - Gesture Overlay (zoom, seek, double-tap-hold)

    /// Transparent overlay that captures all gestures on the keyframe area.
    /// Uses GeometryReader to compute secondsPerPixel for drag-to-seek.
    private var gestureOverlay: some View {
        GeometryReader { geo in
            let viewportWidth = geo.size.width
            let contentWidth = viewportWidth * zoomScale
            let secondsPerPixel = effectiveDuration > 0 ? effectiveDuration / contentWidth : 0

            Color.clear
                .contentShape(Rectangle())
                .gesture(TapGesture(count: 1).onEnded { _ in lastTapTime = Date() })
                .gesture(seekDrag(secondsPerPixel: secondsPerPixel))
                .simultaneousGesture(pinchGesture())
        }
    }

    // MARK: - Keyframe Row

    private func keyframeRow(for tag: Tag) -> some View {
        let tagColor = Color(hex: tag.colorHex)
        let tagMarkers = markersByTag[tag.id] ?? []

        return GeometryReader { geo in
            let viewportWidth = geo.size.width
            let contentWidth = viewportWidth * zoomScale
            let secondsPerPixel = effectiveDuration > 0 ? effectiveDuration / contentWidth : 0
            let centerX = viewportWidth / 2

            // Offset so that effectiveDisplayTime is always at center
            let offset = effectiveDuration > 0
                ? (effectiveDisplayTime / effectiveDuration) * contentWidth
                : 0

            ZStack(alignment: .leading) {
                // Track background — content-width rect, matches waveform edge behavior
                Rectangle()
                    .fill(tagColor.opacity(0.08))
                    .frame(width: contentWidth, height: Self.trackHeight)
                    .position(x: centerX - offset + contentWidth / 2, y: Self.trackHeight / 2)

                // Playhead position indicator (thin vertical line)
                Rectangle()
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: 1, height: Self.trackHeight)
                    .position(x: centerX, y: Self.trackHeight / 2)

                // Keyframe triangles (downward-pointing)
                ForEach(tagMarkers, id: \.id) { marker in
                    let displayTime = audioToDisplayTime(marker.timeSeconds)
                    let normalizedPos = effectiveDuration > 0
                        ? displayTime / effectiveDuration
                        : 0
                    let markerX = centerX - offset + (normalizedPos * contentWidth)

                    // Only render if within visible viewport (with margin)
                    if markerX > -Self.keySize && markerX < viewportWidth + Self.keySize {
                        let isNearPlayhead = abs(marker.timeSeconds - currentTime) < (secondsPerPixel * 8)

                        KeyframeTriangle(
                            color: tagColor,
                            size: Self.keySize,
                            isHighlighted: isNearPlayhead
                        )
                        .position(x: markerX, y: Self.trackHeight / 2)
                    }
                }
            }
            .frame(height: Self.trackHeight)
            .clipped()
        }
        .frame(height: Self.trackHeight)
    }

    // MARK: - Gestures

    private func seekDrag(secondsPerPixel: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isPinching else { return }

                // Double-tap-hold zoom detection
                if !isDoubleTapZoomMode && !isDragging {
                    if let tapTime = lastTapTime {
                        let timeSinceTap = Date().timeIntervalSince(tapTime)
                        if timeSinceTap < 0.4 {
                            isDoubleTapZoomMode = true
                            doubleTapStartZoom = zoomScale
                            doubleTapZoomStartX = value.startLocation.x
                        }
                    }
                }

                if isDoubleTapZoomMode {
                    let translation = value.location.x - doubleTapZoomStartX
                    let zoomMultiplier = 1.0 + (Double(translation) / 50.0)
                    let newScale = doubleTapStartZoom * max(zoomMultiplier, 0.1)
                    zoomScale = min(max(newScale, Self.minZoom), Self.maxZoom)
                    return
                }

                // Seek drag
                if !isDragging {
                    isDragging = true
                    dragStartDisplayTime = effectiveDisplayTime
                    dragStartX = value.startLocation.x
                    onScrubStart?()
                }

                let deltaX = value.location.x - dragStartX
                let delta = Double(deltaX) * secondsPerPixel * -1
                let newDisplayTime = max(0, min(effectiveDuration, dragStartDisplayTime + delta))
                onSeek(displayToAudioTime(newDisplayTime))
            }
            .onEnded { _ in
                if isDoubleTapZoomMode {
                    isDoubleTapZoomMode = false
                    doubleTapZoomStartX = 0
                    lastTapTime = nil
                } else {
                    isDragging = false
                    onScrubEnd?()
                }
            }
    }

    private func pinchGesture() -> some Gesture {
        MagnificationGesture()
            .updating($pinchMagnification) { currentState, gestureState, _ in
                gestureState = currentState
            }
            .onChanged { value in
                if !isPinching {
                    isPinching = true
                    pinchBaseZoom = zoomScale
                }
                let newScale = pinchBaseZoom * value
                zoomScale = min(max(newScale, Self.minZoom), Self.maxZoom)
            }
            .onEnded { _ in
                isPinching = false
                pinchBaseZoom = zoomScale
            }
    }
}

// MARK: - Keyframe Triangle Shape

/// A small downward-pointing triangle indicator used on keyframe tracks.
private struct KeyframeTriangle: View {
    let color: Color
    let size: CGFloat
    let isHighlighted: Bool

    var body: some View {
        DownTriangle()
            .fill(color.opacity(isHighlighted ? 1.0 : 0.7))
            .frame(width: size, height: size)
            .shadow(
                color: isHighlighted ? color.opacity(0.6) : .clear,
                radius: isHighlighted ? 3 : 0
            )
    }
}

/// A downward-pointing triangle shape (apex at bottom center).
private struct DownTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))       // top-left
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))     // top-right
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))     // bottom-center
        path.closeSubpath()
        return path
    }
}
