import SwiftUI

struct HairlineCard<Content: View>: View {
    var padding: CGFloat = Theme.Space.xl
    var background: Color = Theme.Palette.card
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .hairline()
    }
}
