import SwiftUI

struct WaveformView: View {

    let samples: [Float]

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard !samples.isEmpty else { return }

                let midY = size.height / 2
                let stepX = size.width / CGFloat(samples.count)

                var path = Path()

                for (index, value) in samples.enumerated() {
                    let x = CGFloat(index) * stepX
                    let height = CGFloat(value) * midY
                    path.move(to: CGPoint(x: x, y: midY - height))
                    path.addLine(to: CGPoint(x: x, y: midY + height))
                }

                context.stroke(
                    path,
                    with: .color(.primary),
                    lineWidth: 1
                )
            }
        }
        .frame(height: 80)
    }
}
