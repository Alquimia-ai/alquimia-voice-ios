import Foundation

enum VoiceMode: String, Codable, CaseIterable, Sendable {
    case handsFree
    case pushToTalk
}

struct RemoteClose: Equatable, Sendable {
    var code: Int
    var reason: String?
}

enum EndReason: Equatable, Sendable {
    case user
    case background
    case interrupted
    case remote(code: Int, reason: String?)
    case error(String)
}

enum CallPhase: Equatable, Sendable {
    case idle
    case connecting
    /// Hands-free: mic streaming, waiting for the user to speak.
    case listening
    /// Push-to-talk: button held, mic streaming.
    case recording
    /// User turn ended; waiting for the first reply frame.
    case thinking
    /// Reply audio is playing; mic gated.
    case speaking
    case ended(EndReason)
}

struct CallState: Equatable, Sendable {
    var mode: VoiceMode
    var phase: CallPhase = .idle
    var socketOpen = false
    var pttHeld = false
    var receivedAudioThisTurn = false
    var isUserSpeaking = false
    var pendingClose: RemoteClose?
    var hint: String?

    init(
        mode: VoiceMode,
        phase: CallPhase = .idle,
        socketOpen: Bool = false,
        pttHeld: Bool = false,
        hint: String? = nil
    ) {
        self.mode = mode
        self.phase = phase
        self.socketOpen = socketOpen
        self.pttHeld = pttHeld
        self.hint = hint
    }

    /// A call is in progress (socket and/or audio engaged for a turn).
    var isActive: Bool {
        switch phase {
        case .idle, .ended: return false
        default: return true
        }
    }

    /// Whether microphone chunks may be sent to the server right now.
    var allowsSending: Bool {
        switch mode {
        case .handsFree: return phase == .listening || phase == .thinking
        case .pushToTalk: return phase == .recording
        }
    }
}

enum CallEvent: Equatable, Sendable {
    case startCall
    case endCall
    case pressPTT
    case releasePTT
    case maxHoldElapsed
    case socketOpened
    case socketClosed(code: Int, reason: String?)
    case socketFailed(String)
    case localSpeechStarted
    case localTurnEnded
    case localTurnDiscarded
    /// User started talking over the reply (only with echo cancellation and the local barge-in toggle).
    case localBargeIn
    case audioFrame
    case playbackDrained
    case clearReceived
    case thinkingTimeout
    case interruptionBegan
    case appBackgrounded
    case audioFailed(String)
}

enum CallEffect: Equatable, Sendable {
    case startAudio
    case stopAudio
    case openSocket
    case closeSocket
    case sendStop
    case micGate(open: Bool)
    case resetVAD
    case playbackEnqueue
    case playbackFlush
    case startThinkingWatchdog
    case cancelThinkingWatchdog
    case startMaxHoldTimer
    case cancelMaxHoldTimer
    case fetchTranscript
}
