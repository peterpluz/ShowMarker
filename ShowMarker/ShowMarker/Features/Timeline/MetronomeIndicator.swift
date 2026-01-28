import SwiftUI

/// GarageBand-style metronome indicator with beat flash animation
struct MetronomeIndicator: View {

    let isPlaying: Bool
    let currentBeat: Int  // 0-3 for 4/4 time
    let bpm: Double?
    let isEnabled: Bool
    let onToggle: () -> Void

    @State private var isFilled: Bool = false

    var body: some View {
        Button {
            onToggle()
        } label: {
            ZStack {
                // Background capsule
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 44, height: 44)

                // Metronome icon with flash animation
                Image(systemName: isFilled ? "metronome.fill" : "metronome")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(isEnabled ? .accentColor : .secondary)
                    .animation(.linear(duration: 0.1), value: isFilled)
            }
        }
        .onChange(of: currentBeat) { oldBeat, newBeat in
            // Flash to filled on beat only if enabled
            if isEnabled && isPlaying && newBeat != oldBeat {
                isFilled = true

                // Fade back to outline after brief moment
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                    isFilled = false
                }
            }
        }
        .onChange(of: isEnabled) { oldValue, newValue in
            if !newValue {
                isFilled = false
            }
        }
    }
}
