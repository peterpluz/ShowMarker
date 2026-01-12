import SwiftUI

struct TimecodePickerView: View {

    let fps: Int
    let onCancel: () -> Void
    let onDone: (Double) -> Void

    @State private var hours: Int
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var frames: Int

    init(
        seconds: Double,
        fps: Int,
        onCancel: @escaping () -> Void,
        onDone: @escaping (Double) -> Void
    ) {
        self.fps = fps
        self.onCancel = onCancel
        self.onDone = onDone

        let totalFrames = Int(seconds * Double(fps))
        _hours = State(initialValue: totalFrames / (3600 * fps))
        _minutes = State(initialValue: (totalFrames / (60 * fps)) % 60)
        _seconds = State(initialValue: (totalFrames / fps) % 60)
        _frames = State(initialValue: totalFrames % fps)
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // MARK: - Header (TRUE Liquid Glass)
                HStack {

                    // ❌ Cancel
                    glassButton(
                        systemName: "xmark",
                        foreground: .primary,
                        fill: nil,
                        action: onCancel
                    )

                    Spacer()

                    Text("Изменить время маркера")
                        .font(.headline)

                    Spacer()

                    // ✅ Done
                    glassButton(
                        systemName: "checkmark",
                        foreground: .white,
                        fill: Color.accentColor,
                        action: {
                            let totalFrames =
                                hours * 3600 * fps +
                                minutes * 60 * fps +
                                seconds * fps +
                                frames

                            onDone(Double(totalFrames) / Double(fps))
                        }
                    )
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()

                // MARK: - System wheel pickers
                HStack(spacing: 0) {
                    wheel(range: 0..<24, selection: $hours)
                    wheel(range: 0..<60, selection: $minutes)
                    wheel(range: 0..<60, selection: $seconds)
                    wheel(range: 0..<fps, selection: $frames)
                }
                .frame(height: 180)

                Spacer()
            }
        }
    }

    // MARK: - Liquid Glass Button (correct)
    private func glassButton(
        systemName: String,
        foreground: Color,
        fill: Color?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(foreground)
                .frame(width: 48, height: 48)
                .background {
                    if let fill {
                        Circle()
                            .fill(fill)
                    } else {
                        Circle()
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Wheel
    private func wheel(
        range: Range<Int>,
        selection: Binding<Int>
    ) -> some View {
        Picker("", selection: selection) {
            ForEach(range, id: \.self) {
                Text(String(format: "%02d", $0))
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
    }
}
