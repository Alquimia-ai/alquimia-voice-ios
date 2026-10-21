import SwiftUI

/// Uppercase, 11 pt, +0.16em tracking.
struct EyebrowLabel: View {
    let text: String
    var color: Color = Theme.Palette.muted

    init(_ text: String, color: Color = Theme.Palette.muted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typography.eyebrow)
            .tracking(Theme.Typography.eyebrowTracking)
            .foregroundStyle(color)
    }
}
