import SwiftUI

/// Metronome indicator with alternating beat animation
/// Uses square.and.line.vertical.and.square.filled and square.filled.and.line.vertical.and.square
/// to alternate icons in rhythm with the beat
struct MetronomeIndicator: View {

    let isPlaying: Bool
    let currentBeat: Int  // 0-3 for 4/4 time
    let bpm: Double?
    let isEnabled: Bool
    let onToggle: () -> Void

    /// Tracks which icon variant to show (alternates on each beat)
    @State private var isAlternate: Bool = false

    var body: some View {
        Button {
            onToggle()
        } label: {
            ZStack {
                // Background capsule
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 44, height: 44)

                // Alternating metronome icons that switch on each beat
                // When not enabled or not playing, show the first variant
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(isEnabled ? .accentColor : .secondary)
                    .animation(.easeInOut(duration: 0.1), value: isAlternate)
            }
        }
        .onChange(of: currentBeat) { oldBeat, newBeat in
            // Alternate icon on each beat only if enabled and playing
            if isEnabled && isPlaying && newBeat != oldBeat {
                isAlternate.toggle()
            }
        }
        .onChange(of: isEnabled) { oldValue, newValue in
            if !newValue {
                isAlternate = false
            }
        }
        .onChange(of: isPlaying) { oldValue, newValue in
            // Reset to default state when playback stops
            if !newValue {
                isAlternate = false
            }
        }
    }

    /// Returns the appropriate SF Symbol name based on state
    private var iconName: String {
        if isEnabled && isPlaying {
            // Alternate between two icons in rhythm
            return isAlternate
                ? "square.filled.and.line.vertical.and.square"
                : "square.and.line.vertical.and.square.filled"
        } else {
            // Default icon when not active
            return "square.and.line.vertical.and.square.filled"
        }
    }
}
