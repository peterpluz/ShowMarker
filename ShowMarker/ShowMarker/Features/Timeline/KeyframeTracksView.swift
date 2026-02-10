import SwiftUI

/// Displays keyframe tracks below the waveform, one row per tag.
/// Each track shows diamond-shaped keyframe indicators at the same timecodes
/// as the corresponding markers. Scroll and playhead are synchronized with
/// the parent waveform via the same time/zoom model.
struct KeyframeTracksView: View {

    let duration: Double          // Audio duration (without preroll)
    let currentTime: Double       // Audio time (without preroll offset)
    let markers: [TimelineMarker]
    let tags: [Tag]
    let prerollSeconds: Double
    let zoomScale: CGFloat

    // Drag-aware display time (matches TimelineBarView's effectiveDisplayTime)
    let effectiveDisplayTime: Double

    private static let trackHeight: CGFloat = 22
    private static let keySize: CGFloat = 10
    private static let labelWidth: CGFloat = 40

    /// Effective timeline duration including preroll
    private var effectiveDuration: Double {
        duration + prerollSeconds
    }

    /// Convert audio time to display time
    private func audioToDisplayTime(_ audioTime: Double) -> Double {
        audioTime + prerollSeconds
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

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(activeTags.enumerated()), id: \.element.id) { index, tag in
                if index > 0 {
                    Divider()
                        .opacity(0.3)
                }
                trackRow(for: tag)
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    // MARK: - Track Row

    private func trackRow(for tag: Tag) -> some View {
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
                // Track background line
                Rectangle()
                    .fill(tagColor.opacity(0.12))
                    .frame(height: 1)
                    .offset(y: 0)

                // Playhead position indicator (thin vertical line)
                Rectangle()
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: 1, height: Self.trackHeight)
                    .position(x: centerX, y: Self.trackHeight / 2)

                // Keyframe diamonds
                ForEach(tagMarkers, id: \.id) { marker in
                    let displayTime = audioToDisplayTime(marker.timeSeconds)
                    let normalizedPos = effectiveDuration > 0
                        ? displayTime / effectiveDuration
                        : 0
                    let markerX = centerX - offset + (normalizedPos * contentWidth)

                    // Only render if within visible viewport (with margin)
                    if markerX > -Self.keySize && markerX < viewportWidth + Self.keySize {
                        let isNearPlayhead = abs(marker.timeSeconds - currentTime) < (secondsPerPixel * 8)

                        KeyframeDiamond(
                            color: tagColor,
                            size: Self.keySize,
                            isHighlighted: isNearPlayhead
                        )
                        .position(x: markerX, y: Self.trackHeight / 2)
                    }
                }

                // Tag label (pinned to the left edge)
                Text(tag.name)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(tagColor)
                    .lineLimit(1)
                    .frame(width: Self.labelWidth, alignment: .leading)
                    .padding(.leading, 4)
                    .position(x: Self.labelWidth / 2 + 4, y: Self.trackHeight / 2)
            }
            .frame(height: Self.trackHeight)
            .clipped()
        }
        .frame(height: Self.trackHeight)
    }
}

// MARK: - Keyframe Diamond Shape

/// A small diamond/rhombus indicator used on keyframe tracks.
private struct KeyframeDiamond: View {
    let color: Color
    let size: CGFloat
    let isHighlighted: Bool

    var body: some View {
        Diamond()
            .fill(color.opacity(isHighlighted ? 1.0 : 0.7))
            .frame(width: size, height: size)
            .shadow(
                color: isHighlighted ? color.opacity(0.6) : .clear,
                radius: isHighlighted ? 3 : 0
            )
    }
}

/// A diamond (rotated square) shape.
private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let hw = rect.width / 2
        let hh = rect.height / 2
        path.move(to: CGPoint(x: cx, y: cy - hh))     // top
        path.addLine(to: CGPoint(x: cx + hw, y: cy))   // right
        path.addLine(to: CGPoint(x: cx, y: cy + hh))   // bottom
        path.addLine(to: CGPoint(x: cx - hw, y: cy))   // left
        path.closeSubpath()
        return path
    }
}
