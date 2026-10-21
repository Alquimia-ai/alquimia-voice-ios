import SwiftUI

/// Assistant: white card with hairline. User: surface-soft. 12 pt radius, body-md.
struct MessageBubble: View {
    let message: TranscriptMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                EyebrowLabel(isUser ? L10n.Transcript.you : L10n.Transcript.agent)
                Text(message.text)
                    .font(Theme.Typography.bodyMd)
                    .foregroundStyle(Theme.Palette.ink)
                    .lineSpacing(15 * 0.55 - 15 * 0.2)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.md)
            .background(
                isUser ? Theme.Palette.surfaceSoft : Theme.Palette.card,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
            .hairline(color: isUser ? Color.clear : Theme.Palette.hairline)
            if !isUser { Spacer(minLength: 48) }
        }
    }
}
