import SwiftUI
import Combine

/// Keyframe tracks below the waveform — one row per tag.
///
/// Architecture:
/// - Track rows use the FULL parent width — identical coordinate system to the waveform.
///   centerX = viewportWidth / 2, contentWidth = max(viewportWidth * zoomScale, viewportWidth).
/// - Playhead is NOT rendered here — the parent provides a single unified playhead.
/// - Label column is a separate opaque overlay rendered ON TOP of the gesture layer,
///   so label area gestures (resize drag) take priority over timeline gestures.
/// - Keyframe flash is event-based, synced with marker card flash via markerFlashPublisher.
struct KeyframeTracksView: View {

    let duration: Double
    let currentTime: Double
    let markers: [TimelineMarker]
    let tags: [Tag]
    let prerollSeconds: Double

    @Binding var zoomScale: CGFloat
    let effectiveDisplayTime: Double
    let markerFlashPublisher: PassthroughSubject<TimelineViewModel.MarkerFlashEvent, Never>

    let onSeek: (Double) -> Void
    var onScrubStart: (() -> Void)? = nil
    var onScrubEnd: (() -> Void)? = nil

    // MARK: - Label Resize

    @State private var labelWidth: CGFloat = Self.labelExpandedWidth
    @State private var labelDragStartWidth: CGFloat? = nil

    private static let labelExpandedWidth: CGFloat = 80
    private static let labelCollapsedWidth: CGFloat = 20
    private static let labelCollapseThreshold: CGFloat = 40
    private static let labelMinWidth: CGFloat = 20
    private static let labelMaxWidth: CGFloat = 120

    private var isLabelCollapsed: Bool {
        labelWidth < Self.labelCollapseThreshold
    }

    // MARK: - Flash State

    @State private var flashingMarkerIDs: Set<UUID> = []

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
        VStack(spacing: 0) {
            ForEach(Array(activeTags.enumerated()), id: \.element.id) { index, tag in
                if index > 0 { Divider().opacity(0.15) }
                keyframeRow(for: tag)
            }
        }
        .padding(.vertical, 4)
        // 1. Gesture overlay — seek/pinch/zoom on the timeline area
        .overlay(gestureOverlay)
        // 2. Opaque label column ON TOP — its gestures take priority over gesture overlay
        .overlay { labelColumnOverlay }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: labelWidth)
        .onReceive(markerFlashPublisher) { event in
            flashingMarkerIDs.insert(event.markerID)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                flashingMarkerIDs.remove(event.markerID)
            }
        }
    }

    // MARK: - Keyframe Row (only scrollable content — no labels)

    private func keyframeRow(for tag: Tag) -> some View {
        let tagColor = Color(hex: tag.colorHex)
        let tagMarkers = markersByTag[tag.id] ?? []

        return GeometryReader { geo in
            let vw = geo.size.width
            let cw = max(vw * zoomScale, vw)
            let cx = vw / 2
            let off = effectiveDuration > 0
                ? (effectiveDisplayTime / effectiveDuration) * cw : 0
            let midY = Self.trackHeight / 2

            ZStack {
                // Background strip — scrolls with timeline
                Rectangle()
                    .fill(tagColor.opacity(0.08))
                    .frame(width: cw, height: Self.trackHeight)
                    .position(x: cx - off + cw / 2, y: midY)

                // Keyframe triangles — scroll with timeline
                ForEach(tagMarkers, id: \.id) { marker in
                    let dt = audioToDisplayTime(marker.timeSeconds)
                    let np = effectiveDuration > 0 ? dt / effectiveDuration : 0
                    let mx = cx - off + np * cw
                    let isFlashing = flashingMarkerIDs.contains(marker.id)

                    if mx > -Self.keySize && mx < vw + Self.keySize {
                        KeyframeTriangle(
                            color: tagColor,
                            size: Self.keySize,
                            isHighlighted: isFlashing
                        )
                        .position(x: mx, y: midY)
                    }
                }
            }
        }
        .frame(height: Self.trackHeight)
    }

    // MARK: - Label Column Overlay

    /// Opaque label panel rendered as a GeometryReader overlay with explicit .position().
    /// Sits ON TOP of the gesture overlay so resize drag is never intercepted.
    private var labelColumnOverlay: some View {
        GeometryReader { geo in
            let totalH = geo.size.height
            let midY = totalH / 2

            // Opaque column background — fully covers keyframes underneath
            Rectangle()
                .fill(Color(UIColor.secondarySystemBackground))
                .frame(width: labelWidth, height: totalH)
                .position(x: labelWidth / 2, y: midY)

            // Per-row label texts
            VStack(spacing: 0) {
                ForEach(Array(activeTags.enumerated()), id: \.element.id) { index, tag in
                    let c = Color(hex: tag.colorHex)
                    if index > 0 {
                        Divider().frame(width: labelWidth).opacity(0.2)
                    }

                    HStack(spacing: 0) {
                        if isLabelCollapsed {
                            Text(String(tag.name.prefix(1)).uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(c)
                        } else {
                            Text(tag.name)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(c)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 4)
                    .frame(height: Self.trackHeight)
                }
            }
            .frame(width: labelWidth)
            .padding(.vertical, 4)
            .position(x: labelWidth / 2, y: midY)

            // Resize divider — draggable vertical line at right edge of label column
            Rectangle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 2, height: totalH)
                .position(x: labelWidth + 1, y: midY)

            // Invisible wide hit area for the resize gesture
            Color.clear
                .frame(width: 20, height: totalH)
                .contentShape(Rectangle())
                .position(x: labelWidth + 1, y: midY)
                .gesture(labelResizeGesture)
        }
        .allowsHitTesting(true)
    }

    // MARK: - Label Resize Gesture

    private var labelResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if labelDragStartWidth == nil { labelDragStartWidth = labelWidth }
                guard let start = labelDragStartWidth else { return }
                let newWidth = start + value.translation.width
                withAnimation(.interactiveSpring()) {
                    labelWidth = max(Self.labelMinWidth, min(Self.labelMaxWidth, newWidth))
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    if labelWidth < Self.labelCollapseThreshold {
                        labelWidth = Self.labelCollapsedWidth
                    } else if labelWidth < Self.labelExpandedWidth {
                        labelWidth = Self.labelExpandedWidth
                    }
                    // If dragged wider than default, keep the custom width
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
            .frame(width: isHighlighted ? size * 1.3 : size,
                   height: isHighlighted ? size * 1.3 : size)
            .shadow(color: isHighlighted ? color.opacity(0.8) : .clear,
                    radius: isHighlighted ? 4 : 0)
            .animation(.easeOut(duration: 0.15), value: isHighlighted)
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
