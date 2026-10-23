import SwiftUI

struct CallView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(CallSession.self) private var session
    @Environment(AuthManager.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Theme.Space.xl)
                .padding(.top, Theme.Space.sm)
                .padding(.bottom, Theme.Space.md)
            Rectangle()
                .fill(Theme.Palette.hairline)
                .frame(height: 1)
            TranscriptView(
                messages: session.transcript,
                isLoading: session.isLoadingTranscript,
                error: session.transcriptError
            )
            VoiceDock(session: session) { showSettings = true }
                .padding(.horizontal, Theme.Space.xl)
                .padding(.bottom, Theme.Space.lg)
        }
        .background(Theme.Palette.canvas.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { session.handleBackground() }
        }
        .task {
            if settings.isConfigured(signedIn: auth.isSignedIn) { session.refreshTranscript() }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                EyebrowLabel(L10n.App.eyebrow)
                Text(settings.trimmedAssistantID.isEmpty ? "—" : settings.trimmedAssistantID)
                    .font(Theme.Typography.monoLabel)
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                session.newConversation()
            } label: {
                HStack(spacing: Theme.Space.xs + 2) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                    Text(SessionID.short(settings.sessionID))
                        .font(Theme.Typography.monoLabel)
                }
            }
            .buttonStyle(ChipButtonStyle())
            .accessibilityLabel(Text(L10n.App.newConversation))
        }
    }
}
