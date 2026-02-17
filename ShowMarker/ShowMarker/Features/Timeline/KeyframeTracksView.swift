import SwiftUI

/// Keyframe tracks below the waveform — one row per tag.
///
/// Architecture:
/// - Track rows use the FULL parent width — identical coordinate system to the waveform.
///   centerX = viewportWidth / 2, contentWidth = max(viewportWidth * zoomScale, viewportWidth).
///   No manual offset compensation. Left edge of tracks = left edge of waveform.
/// - Playhead is NOT rendered here — the parent provides a single unified playhead.
/// - Label panel floats as an .overlay(alignment: .leading) so it does NOT affect
///   the coordinate system. Changing label width cannot cause X desync.
/// - Resize divider is pinned at x = labelWidth (right edge of labels).
struct KeyframeTracksView: View {

    let duration: Double
    let currentTime: Double
    let markers: [TimelineMarker]
    let tags: [Tag]
    let prerollSeconds: Double

    @Binding var zoomScale: CGFloat
    let effectiveDisplayTime: Double

    let onSeek: (Double) -> Void
    var onScrubStart: (() -> Void)? = nil
    var onScrubEnd: (() -> Void)? = nil

    // MARK: - Label Resize

    @State private var labelWidth: CGFloat = Self.labelExpandedWidth
    @State private var labelDragStartWidth: CGFloat? = nil

    private static let labelExpandedWidth: CGFloat = 60
    private static let labelCollapsedWidth: CGFloat = 24
    private static let labelCollapseThreshold: CGFloat = 42

    private var isLabelCollapsed: Bool {
        labelWidth < Self.labelCollapseThreshold
    }

    // MARK: - Gesture State

    @State private var isPinching = false
    @State private var pinchBaseZoom: CGFloat = 1.0
    @GestureState private var pinchMagnification: CGFloat = 1.0

    @State private var isDragging = false
    @State private var dragStartDisplayTime: Double = 0
    @State private var dragStartX: CGFloat = 0

    @State private var lastTapTime: Date?
    @State private var isDoubleTapZoomMode = false
    @State private var doubleTapStartZoom: CGFloat = 1.0
    @State private var doubleTapZoomStartX: CGFloat = 0

    // MARK: - Constants

    static let trackHeight: CGFloat = 22
    private static let keySize: CGFloat = 10
    private static let minZoom: CGFloat = 1.0
    private static let maxZoom: CGFloat = 500.0

    private var effectiveDuration: Double { duration + prerollSeconds }

    private func audioToDisplayTime(_ t: Double) -> Double { t + prerollSeconds }
    private func displayToAudioTime(_ t: Double) -> Double { t - prerollSeconds }

    private var markersByTag: [UUID: [TimelineMarker]] {
        Dictionary(grouping: markers, by: \.tagId)
    }

    var activeTags: [Tag] {
        tags.filter { markersByTag[$0.id] != nil }.sorted { $0.order < $1.order }
    }

    // MARK: - Body

    var body: some View {
        // Full-width track rows — same coordinate space as waveform
        VStack(spacing: 0) {
            ForEach(Array(activeTags.enumerated()), id: \.element.id) { index, tag in
                if index > 0 { Divider().opacity(0.15) }
                keyframeRow(for: tag)
            }
        }
        .padding(.vertical, 4)
        .overlay(gestureOverlay)
        .overlay(alignment: .leading) { labelOverlay }
    }

    // MARK: - Label Overlay

    private var labelOverlay: some View {
        HStack(spacing: 0) {
            // Tag name labels — left edge = waveform left edge (no internal padding)
            VStack(spacing: 0) {
                ForEach(Array(activeTags.enumerated()), id: \.element.id) { index, tag in
                    let c = Color(hex: tag.colorHex)
                    if index > 0 { Divider().opacity(0.15) }

                    Group {
                        if isLabelCollapsed {
                            Text(String(tag.name.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(c)
                                .padding(.leading, 4)
                        } else {
                            Text(tag.name)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(c)
                                .lineLimit(1)
                                .padding(.leading, 4)
                        }
                    }
                    .frame(width: labelWidth, height: Self.trackHeight,
                           alignment: .leading)
                    .background(c.opacity(0.12))
                }
            }

            // Resize divider — pinned at x = labelWidth, same height as label column
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 3, height: CGFloat(activeTags.count) * Self.trackHeight)
                .contentShape(Rectangle().inset(by: -10))
                .gesture(labelResizeGesture)
        }
        .padding(.vertical, 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: labelWidth)
    }

    // MARK: - Label Resize Gesture

    private var labelResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if labelDragStartWidth == nil { labelDragStartWidth = labelWidth }
                guard let start = labelDragStartWidth else { return }
                withAnimation(.interactiveSpring()) {
                    labelWidth = max(Self.labelCollapsedWidth,
                                     min(Self.labelExpandedWidth, start + value.translation.width))
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    labelWidth = labelWidth < Self.labelCollapseThreshold
                        ? Self.labelCollapsedWidth
                        : Self.labelExpandedWidth
                }
                labelDragStartWidth = nil
            }
    }

    // MARK: - Gesture Overlay

    private var gestureOverlay: some View {
        GeometryReader { geo in
            let cw = max(geo.size.width * zoomScale, geo.size.width)
            let spp = effectiveDuration > 0 ? effectiveDuration / cw : 0
            Color.clear
                .contentShape(Rectangle())
                .gesture(TapGesture(count: 1).onEnded { _ in lastTapTime = Date() })
                .gesture(seekDrag(secondsPerPixel: spp))
                .simultaneousGesture(pinchGesture())
        }
    }

    // MARK: - Keyframe Row

    private func keyframeRow(for tag: Tag) -> some View {
        let tagColor = Color(hex: tag.colorHex)
        let tagMarkers = markersByTag[tag.id] ?? []

        return GeometryReader { geo in
            let vw = geo.size.width
            let cw = max(vw * zoomScale, vw)
            let spp = effectiveDuration > 0 ? effectiveDuration / cw : 0
            let cx = vw / 2
            let off = effectiveDuration > 0
                ? (effectiveDisplayTime / effectiveDuration) * cw : 0

            ZStack {
                // Background — same width as waveform content
                Rectangle()
                    .fill(tagColor.opacity(0.08))
                    .frame(width: cw, height: Self.trackHeight)
                    .position(x: cx - off + cw / 2, y: Self.trackHeight / 2)

                // Keyframe triangles
                ForEach(tagMarkers, id: \.id) { marker in
                    let dt = audioToDisplayTime(marker.timeSeconds)
                    let np = effectiveDuration > 0 ? dt / effectiveDuration : 0
                    let mx = cx - off + np * cw

                    if mx > -Self.keySize && mx < vw + Self.keySize {
                        KeyframeTriangle(
                            color: tagColor,
                            size: Self.keySize,
                            isHighlighted: abs(marker.timeSeconds - currentTime) < spp * 8
                        )
                        .position(x: mx, y: Self.trackHeight / 2)
                    }
                }
            }
        }
        .frame(height: Self.trackHeight)
    }

    // MARK: - Gestures

    private func seekDrag(secondsPerPixel spp: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isPinching else { return }

                if !isDoubleTapZoomMode && !isDragging,
                   let t = lastTapTime, Date().timeIntervalSince(t) < 0.4 {
                    isDoubleTapZoomMode = true
                    doubleTapStartZoom = zoomScale
                    doubleTapZoomStartX = value.startLocation.x
                }

                if isDoubleTapZoomMode {
                    let dx = value.location.x - doubleTapZoomStartX
                    let m = 1.0 + Double(dx) / 50.0
                    zoomScale = min(max(doubleTapStartZoom * max(m, 0.1),
                                        Self.minZoom), Self.maxZoom)
                    return
                }

                if !isDragging {
                    isDragging = true
                    dragStartDisplayTime = effectiveDisplayTime
                    dragStartX = value.startLocation.x
                    onScrubStart?()
                }
                let delta = Double(value.location.x - dragStartX) * spp * -1
                let t = max(0, min(effectiveDuration, dragStartDisplayTime + delta))
                onSeek(displayToAudioTime(t))
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
            .updating($pinchMagnification) { v, s, _ in s = v }
            .onChanged { value in
                if !isPinching { isPinching = true; pinchBaseZoom = zoomScale }
                zoomScale = min(max(pinchBaseZoom * value, Self.minZoom), Self.maxZoom)
            }
            .onEnded { _ in isPinching = false; pinchBaseZoom = zoomScale }
    }
}

// MARK: - Shapes

private struct KeyframeTriangle: View {
    let color: Color
    let size: CGFloat
    let isHighlighted: Bool

    var body: some View {
        DownTriangle()
            .fill(color.opacity(isHighlighted ? 1.0 : 0.7))
            .frame(width: size, height: size)
            .shadow(color: isHighlighted ? color.opacity(0.6) : .clear,
                    radius: isHighlighted ? 3 : 0)
    }
}

private struct DownTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
