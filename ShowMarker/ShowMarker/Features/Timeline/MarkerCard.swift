import SwiftUI
import Combine

struct MarkerCard: View {

    let marker: TimelineMarker
    let tag: Tag?  // Tag for this marker
    let fps: Int
    let markerFlashPublisher: PassthroughSubject<TimelineViewModel.MarkerFlashEvent, Never>
    let draggedMarkerID: UUID?
    let draggedMarkerPreviewTime: Double?
    let currentTime: Double  // Current playhead time
    let markerIndex: Int  // 1-based index number for display
    let onTagEdit: () -> Void  // Callback for tag editing

    @State private var flashOpacity: Double = 0
    @State private var pulsePhase: Double = 0

    var body: some View {
        HStack(spacing: 12) {

            // Vertical colored stripe instead of bookmark icon
            Rectangle()
                .fill(tag.map { Color(hex: $0.colorHex) } ?? Color.accentColor)
                .opacity(currentTime > marker.timeSeconds ? 0.4 : 1.0)
                .frame(width: 4, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("\(markerIndex)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 24, alignment: .trailing)

                    Text(marker.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                .opacity(currentTime > marker.timeSeconds ? 0.4 : 1.0)

                Text(timecode())
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .opacity(currentTime > marker.timeSeconds ? 0.4 : 1.0)
            }

            Spacer()

            // Tag indicator (larger text)
            if let tag = tag {
                Text(tag.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: tag.colorHex))
                    .opacity(currentTime > marker.timeSeconds ? 0.4 : 1.0)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(overlayOpacity))
                .allowsHitTesting(false)
        )
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets())
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onTagEdit()
            } label: {
                Label("Тег", systemImage: "tag.fill")
            }
            .tint(.orange)
        }
        .onLongPressGesture {
            onTagEdit()
        }
        .onReceive(markerFlashPublisher) { event in
            // Only process events for THIS marker
            guard event.markerID == marker.id else { return }
            
            print("   📥 [MarkerCard] '\(marker.name)' received event #\(event.eventID)")
            print("   ⚡️ [MarkerCard] '\(marker.name)' will trigger flash animation")
            triggerFlashEffect()
        }
        .onChange(of: isDragging) { oldValue, dragging in
            if dragging {
                startPulseAnimation()
            } else {
                stopPulseAnimation()
            }
        }
        .onAppear {
            if isDragging {
                startPulseAnimation()
            }
        }
    }

    // MARK: - Computed Properties

    private var isDragging: Bool {
        draggedMarkerID == marker.id
    }

    private var overlayOpacity: Double {
        if isDragging {
            // Pulsing animation: sine wave between 0.15 and 0.45
            return 0.3 + 0.15 * sin(pulsePhase)
        } else {
            // Normal flash effect
            return flashOpacity * 0.3
        }
    }

    // MARK: - Helper Methods

    private func timecode() -> String {
        // Use preview time if this marker is being dragged, otherwise use actual time
        let timeToDisplay = (isDragging && draggedMarkerPreviewTime != nil)
            ? draggedMarkerPreviewTime!
            : marker.timeSeconds

        let totalFrames = Int(timeToDisplay * Double(fps))
        let frames = totalFrames % fps
        let totalSeconds = totalFrames / fps
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60

        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }

    private func triggerFlashEffect() {
        print("      💥 [MarkerCard] '\(marker.name)' FLASH TRIGGERED")
        
        // ✅ CRITICAL FIX: Use withAnimation(.none) to ensure instant attack
        // This prevents SwiftUI from applying implicit animations
        withAnimation(.none) {
            flashOpacity = 1.0
        }
        print("      ⚡️ [MarkerCard] '\(marker.name)' flashOpacity set to 1.0 (instant)")
        
        // ✅ Add small delay before decay to ensure attack completes
        // This gives SwiftUI time to render the full opacity before starting fade
        Task { @MainActor in
            // Wait one frame to ensure the full opacity is rendered
            try? await Task.sleep(nanoseconds: 16_000_000)  // ~1 frame at 60fps
            
            print("      🌊 [MarkerCard] '\(marker.name)' starting decay animation")
            withAnimation(.easeOut(duration: 0.5)) {
                flashOpacity = 0
            }
            
            // Log after animation completes
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
            print("      ✅ [MarkerCard] '\(marker.name)' FLASH COMPLETED")
        }
    }

    private func startPulseAnimation() {
        // Start continuous sine wave animation
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
            pulsePhase = .pi * 2
        }
    }

    private func stopPulseAnimation() {
        // Stop animation and reset phase
        withAnimation(.linear(duration: 0.2)) {
            pulsePhase = 0
        }
    }
}
