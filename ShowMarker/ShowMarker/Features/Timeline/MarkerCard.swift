import SwiftUI
import Combine

struct MarkerCard: View {

    let marker: TimelineMarker
    let fps: Int
    let markerFlashPublisher: PassthroughSubject<TimelineViewModel.MarkerFlashEvent, Never>
    let draggedMarkerID: UUID?
    let draggedMarkerPreviewTime: Double?

    @State private var flashOpacity: Double = 0
    @State private var pulsePhase: Double = 0

    var body: some View {
        HStack(spacing: 12) {

            Image(systemName: "bookmark.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(marker.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(timecode())
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

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
        .onReceive(markerFlashPublisher) { event in
            // Only process events for THIS marker
            guard event.markerID == marker.id else { return }
            
            print("   📥 [MarkerCard] '\(marker.name)' received event #\(event.eventID)")

            // ✅ ИСПРАВЛЕНИЕ: Убрана логика lastProcessedEventID
            // Каждое событие теперь вызывает flash, независимо от eventID
            // Это позволяет маркеру мигать при каждом пересечении playhead
            print("   ⚡️ [MarkerCard] '\(marker.name)' will trigger flash animation")
            triggerFlashEffect()
        }
        .onChange(of: isDragging) { dragging in
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
        print("      💥 [MarkerCard] '\(marker.name)' ANIMATION STARTED: flashOpacity 0.0 → 1.0")
        
        // Instant attack: immediately set to full opacity (no animation)
        flashOpacity = 1.0

        // Smooth decay: fade out over 0.5 seconds
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.5)) {
                flashOpacity = 0
            }
            
            // Log after animation completes
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
            print("      ✅ [MarkerCard] '\(marker.name)' ANIMATION COMPLETED: flashOpacity → 0.0")
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
