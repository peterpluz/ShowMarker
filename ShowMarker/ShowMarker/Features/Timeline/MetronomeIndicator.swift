import SwiftUI

/// GarageBand-style metronome indicator with discrete pendulum animation
struct MetronomeIndicator: View {

    let isPlaying: Bool
    let currentBeat: Int  // 0-3 for 4/4 time
    let bpm: Double?

    @State private var isFilled: Bool = false

    var body: some View {
        ZStack {
            // Background capsule
            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 44, height: 44)

            // Metronome icon with discrete pendulum movement
            Image(systemName: isFilled ? "metronome.fill" : "metronome")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(isPlaying ? .accentColor : .secondary)
                .offset(x: pendulumOffset)
                .animation(.linear(duration: 0.05), value: pendulumOffset)
                .animation(.linear(duration: 0.1), value: isFilled)
        }
        .onChange(of: currentBeat) { oldBeat, newBeat in
            // Flash to filled on beat
            if isPlaying && newBeat != oldBeat {
                isFilled = true

                // Fade back to outline after brief moment
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                    isFilled = false
                }
            }
        }
        .onChange(of: isPlaying) { oldValue, newValue in
            if !newValue {
                isFilled = false
            }
        }
    }

    /// Discrete pendulum positions based on beat (GarageBand style)
    /// Beat 1 (downbeat) = center-left
    /// Beat 2 = slight right
    /// Beat 3 = center-left
    /// Beat 4 = slight right
    private var pendulumOffset: CGFloat {
        guard isPlaying, bpm != nil else { return 0 }

        // Discrete positions for 4/4 time
        switch currentBeat {
        case 1, 3:
            return -3.0  // Left position
        case 2, 4:
            return 3.0   // Right position
        default:
            return 0
        }
    }
}
