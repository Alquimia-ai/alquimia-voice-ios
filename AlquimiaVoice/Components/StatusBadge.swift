import SwiftUI

extension CallPhase {
    var isThinking: Bool {
        if case .thinking = self { return true }
        return false
    }

    func label(isUserSpeaking: Bool) -> String {
        switch self {
        case .idle: return L10n.Phase.idle
        case .connecting: return L10n.Phase.connecting
        case .listening: return isUserSpeaking ? L10n.Phase.userSpeaking : L10n.Phase.listening
        case .recording: return isUserSpeaking ? L10n.Phase.userSpeaking : L10n.Phase.recording
        case .thinking: return L10n.Phase.thinking
        case .speaking: return L10n.Phase.speaking
        case .ended: return L10n.Phase.ended
        }
    }

    func dotColor(isUserSpeaking: Bool) -> Color {
        switch self {
        case .idle, .ended: return Theme.Palette.mutedSoft
        case .connecting, .thinking: return Theme.Palette.muted
        case .listening, .recording: return isUserSpeaking ? Theme.Palette.ember : Theme.Palette.ink
        case .speaking: return Theme.Palette.ember
        }
    }
}

extension EndReason {
    var message: String {
        switch self {
        case .user: return L10n.Ended.user
        case .background: return L10n.Ended.background
        case .interrupted: return L10n.Ended.interrupted
        case .remote(let code, let reason):
            if let reason, !reason.isEmpty { return "\(L10n.Ended.remote): \(reason) (\(code))" }
            return "\(L10n.Ended.remote) (\(code))."
        case .error(let message): return "\(L10n.Ended.error): \(message)"
        }
    }
}

/// Dot + eyebrow describing the call phase; the thinking phase shimmers.
struct StatusBadge: View {
    let phase: CallPhase
    let isUserSpeaking: Bool

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Circle()
                .fill(phase.dotColor(isUserSpeaking: isUserSpeaking))
                .frame(width: 6, height: 6)
            if phase.isThinking {
                ShimmerText(text: phase.label(isUserSpeaking: false))
            } else {
                EyebrowLabel(phase.label(isUserSpeaking: isUserSpeaking), color: Theme.Palette.ink)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isUserSpeaking)
    }
}
