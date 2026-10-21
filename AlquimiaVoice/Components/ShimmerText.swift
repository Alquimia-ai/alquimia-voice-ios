import SwiftUI

/// The "thinking" treatment from the design system: an eyebrow whose fill shimmers muted → ink → muted.
struct ShimmerText: View {
    let text: String
    @State private var offset: CGFloat = -1

    var body: some View {
        label
            .foregroundStyle(Theme.Palette.muted)
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [.clear, Theme.Palette.ink, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.7)
                    .offset(x: offset * geometry.size.width)
                }
                .mask(label)
            }
            .onAppear {
                offset = -1
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    offset = 1
                }
            }
    }

    private var label: some View {
        Text(text.uppercased())
            .font(Theme.Typography.eyebrow)
            .tracking(Theme.Typography.eyebrowTracking)
    }
}
