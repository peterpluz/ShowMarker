import SwiftUI

/// Displays keyframe tracks below the waveform, one row per tag.
/// Each track shows downward-triangle keyframe indicators at the same timecodes
/// as the corresponding markers.
///
/// Architecture:
/// - Track rows use the FULL parent width — identical coordinate system to the waveform.
///   centerX = viewportWidth / 2, contentWidth = viewportWidth * zoomScale.
///   No manual offset compensation. Left edge of tracks = left edge of waveform.
/// - Playhead is NOT rendered here — the parent TimelineContainer provides
///   a single unified playhead spanning waveform + keyframes.
/// - Label panel floats as an overlay on the leading edge, so changing its width
///   does NOT affect the coordinate system or cause X desync.
/// - Zoom/seek gestures are handled on the track area (same scale as waveform).
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

    @State private var labelWidth: CGFloat = Self.labelExpandedWidth
    @State private var labelDragStartWidth: CGFloat? = nil

    private static let labelExpandedWidth: CGFloat = 60
    private static let labelCollapsedWidth: CGFloat = 24
    private static let labelCollapseThreshold: CGFloat = 42
    private static let handleWidth: CGFloat = 14

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

    static let trackHeight: CGFloat = 22
    private static let keySize: CGFloat = 10

    private static let minZoom: CGFloat = 1.0
    private static let maxZoom: CGFloat = 500.0

    /// Effective timeline duration including preroll
    private var effectiveDuration: Double {
        duration + prerollSeconds
    }

    private func audioToDisplayTime(_ audioTime: Double) -> Double {
        audioTime + prerollSeconds
    }

    private func displayToAudioTime(_ displayTime: Double) -> Double {
        displayTime - prerollSeconds
    }

    private var markersByTag: [UUID: [TimelineMarker]] {
        Dictionary(grouping: markers, by: \.tagId)
    }

    /// Tags that have at least one marker, sorted by order
    var activeTags: [Tag] {
        tags
            .filter { tag in markersByTag[tag.id] != nil }
            .sorted { $0.order < $1.order }
    }

    // MARK: - Body

    var body: some View {
        // Track rows at FULL width (identical coordinate space as waveform)
        VStack(spacing: 0) {
            ForEach(Array(activeTags.enumerated()), id: \.element.id) { index, tag in
                if index > 0 {
                    Divider().opacity(0.15)
                }
                keyframeRow(for: tag)
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.04))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // Gesture overlay (zoom, seek, double-tap-hold) — uses full width
        .overlay(gestureOverlay)
        // Label panel floats on the leading edge — does NOT affect coordinate system
        .overlay(alignment: .leading) {
            labelOverlay
        }
    }

    // MARK: - Label Overlay (floating, does not shift coordinates)

    private var labelOverlay: some View {
        HStack(spacing: 0) {
            // Tag labels
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
                    .background(tagColor.opacity(0.1))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Sheet-style grab handle
            ZStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.06))
                Capsule()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 4, height: 32)
            }
            .frame(width: Self.handleWidth)
            .contentShape(Rectangle())
            .gesture(labelResizeGesture)
        }
        .padding(.vertical, 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: labelWidth)
    }

    // MARK: - Label Resize Gesture

    private var labelResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if labelDragStartWidth == nil {
                    labelDragStartWidth = labelWidth
                }
                guard let startWidth = labelDragStartWidth else { return }
                let newWidth = startWidth + value.translation.width
                // Animate during drag with interactive spring
                withAnimation(.interactiveSpring()) {
                    labelWidth = max(Self.labelCollapsedWidth, min(Self.labelExpandedWidth, newWidth))
                }
            }
            .onEnded { _ in
                // Snap to collapsed or expanded with spring
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    if labelWidth < Self.labelCollapseThreshold {
                        labelWidth = Self.labelCollapsedWidth
                    } else {
                        labelWidth = Self.labelExpandedWidth
                    }
                }
                labelDragStartWidth = nil
            }
    }

    // MARK: - Gesture Overlay

    private var gestureOverlay: some View {
        GeometryReader { geo in
            let viewportWidth = geo.size.width
            // Same formula as waveform: contentWidth = viewportWidth * zoomScale
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
            // Identical coordinate system to waveform — no compensation
            let contentWidth = viewportWidth * zoomScale
            let secondsPerPixel = effectiveDuration > 0 ? effectiveDuration / contentWidth : 0
            let centerX = viewportWidth / 2

            let offset = effectiveDuration > 0
                ? (effectiveDisplayTime / effectiveDuration) * contentWidth
                : 0

            ZStack(alignment: .leading) {
                // Track background — content-width rect, matches waveform edge behavior
                Rectangle()
                    .fill(tagColor.opacity(0.08))
                    .frame(width: contentWidth, height: Self.trackHeight)
                    .position(x: centerX - offset + contentWidth / 2, y: Self.trackHeight / 2)

                // No playhead here — unified playhead is in parent container

                // Keyframe triangles (downward-pointing)
                ForEach(tagMarkers, id: \.id) { marker in
                    let displayTime = audioToDisplayTime(marker.timeSeconds)
                    let normalizedPos = effectiveDuration > 0
                        ? displayTime / effectiveDuration
                        : 0
                    let markerX = centerX - offset + (normalizedPos * contentWidth)

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

private struct DownTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
