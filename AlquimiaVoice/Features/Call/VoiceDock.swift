import SwiftUI

/// The bottom card: phase badge, level meter, hint and the voice controls for the active mode.
struct VoiceDock: View {
    let session: CallSession
    let onOpenSettings: () -> Void

    private var state: CallState { session.state }

    var body: some View {
        HairlineCard(padding: Theme.Space.xl - 4) {
            VStack(spacing: Theme.Space.lg) {
                HStack(alignment: .center) {
                    StatusBadge(phase: state.phase, isUserSpeaking: state.isUserSpeaking)
                    Spacer()
                    if let start = session.callStartedAt {
                        TimelineView(.periodic(from: start, by: 1)) { context in
                            Text(Self.format(context.date.timeIntervalSince(start)))
                                .font(Theme.Typography.monoLabel)
                                .foregroundStyle(Theme.Palette.muted)
                                .monospacedDigit()
                        }
                    }
                    if session.echoCancellationActive {
                        EyebrowLabel("AEC", color: Theme.Palette.mutedSoft)
                            .padding(.leading, Theme.Space.sm)
                    }
                }

                LevelMeterView(level: session.inputLevel, dbfs: session.inputDBFS)

                if let message = statusMessage {
                    Text(message)
                        .font(Theme.Typography.bodySm)
                        .foregroundStyle(isErrorMessage ? Theme.Palette.error : Theme.Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }

                HStack(spacing: Theme.Space.xl) {
                    Button {
                        session.toggleMute()
                    } label: {
                        Image(systemName: session.isMuted ? "mic.slash.fill" : "mic.fill")
                    }
                    .buttonStyle(IconCircleButtonStyle(active: session.isMuted))
                    .accessibilityLabel(Text(session.isMuted ? L10n.Actions.unmute : L10n.Actions.mute))

                    Spacer()
                    mainControl
                    Spacer()

                    Button(action: onOpenSettings) {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(IconCircleButtonStyle())
                    .accessibilityLabel(Text(L10n.App.settings))
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: statusMessage)
    }

    @ViewBuilder
    private var mainControl: some View {
        switch session.mode {
        case .handsFree:
            Button {
                if state.isActive { session.endCall() } else { session.startCall() }
            } label: {
                ZStack {
                    Circle().fill(state.isActive ? Theme.Palette.ink : Theme.Palette.ember)
                    Image(systemName: state.isActive ? "stop.fill" : "waveform")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(state.isActive ? Theme.Palette.onPrimary : Color.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 88, height: 88)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(state.isActive ? L10n.Actions.endCall : L10n.Actions.startCall))

        case .pushToTalk:
            HoldToTalkButton(
                isHolding: state.pttHeld && (state.phase == .recording || state.phase == .connecting),
                isEnabled: !state.phase.isThinking,
                onPress: { session.pressPTT() },
                onRelease: { session.releasePTT() }
            )
        }
    }

    private var statusMessage: String? {
        if session.isMuted, state.isActive { return L10n.Hints.muted }
        if case .ended(let reason) = state.phase { return reason.message }
        if let hint = state.hint { return hint }
        if session.mode == .pushToTalk, state.phase == .idle { return L10n.Hints.holdToTalk }
        return nil
    }

    private var isErrorMessage: Bool {
        if case .ended(let reason) = state.phase {
            switch reason {
            case .error, .remote: return true
            default: return false
            }
        }
        return false
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
