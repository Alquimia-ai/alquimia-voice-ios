import SwiftUI

struct TranscriptView: View {
    let messages: [TranscriptMessage]
    let isLoading: Bool
    let error: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if messages.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Space.xxxl * 2)
                } else {
                    LazyVStack(spacing: Theme.Space.md) {
                        ForEach(messages) { message in
                            MessageBubble(message: message).id(message.id)
                        }
                    }
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.vertical, Theme.Space.lg)
                }
                if let error {
                    Text(error)
                        .font(Theme.Typography.bodySm)
                        .foregroundStyle(Theme.Palette.error)
                        .padding(.horizontal, Theme.Space.xl)
                        .padding(.bottom, Theme.Space.sm)
                }
                if isLoading {
                    EyebrowLabel(L10n.Transcript.loading)
                        .padding(.bottom, Theme.Space.sm)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                guard let last = messages.last else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.sm) {
            EyebrowLabel(L10n.Transcript.emptyEyebrow)
            Text(L10n.Transcript.emptyBody)
                .font(Theme.Typography.bodySm)
                .foregroundStyle(Theme.Palette.muted)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 280, alignment: .leading)
        }
        .padding(.horizontal, Theme.Space.xl)
    }
}
