import SwiftUI

struct PlayheadView: View {

    let progress: Double   // 0...1

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.red)
                .frame(width: 2)
                .offset(x: max(0, min(progress, 1)) * geo.size.width)
        }
    }
}
