import SwiftUI

struct TimelineRow: View {
    let title: String

    var body: some View {
        Text(title)
            .foregroundColor(.primary)
            .padding(.vertical, 6)
    }
}
