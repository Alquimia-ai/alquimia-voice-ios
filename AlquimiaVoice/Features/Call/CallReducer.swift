import Foundation

/// Pure state machine for both interaction modes. `CallSession` executes the returned effects.
enum CallReducer {
    static let teardown: [CallEffect] = [
        .cancelThinkingWatchdog, .cancelMaxHoldTimer, .micGate(open: false), .closeSocket, .playbackFlush, .stopAudio,
    ]

    static func reduce(_ state: CallState, _ event: CallEvent) -> (CallState, [CallEffect]) {
        if let common = reduceCommon(state, event) { return common }
        switch state.mode {
        case .handsFree: return reduceHandsFree(state, event)
        case .pushToTalk: return reducePushToTalk(state, event)
        }
    }

    // MARK: - Mode independent

    private static func reduceCommon(_ state: CallState, _ event: CallEvent) -> (CallState, [CallEffect])? {
        var s = state
        switch event {
        case .endCall:
            if s.isActive {
                s.phase = .ended(.user)
                s.socketOpen = false
                s.pttHeld = false
                s.isUserSpeaking = false
                return (s, teardown)
            }
            s.phase = .idle
            s.hint = nil
            return (s, [.stopAudio])

        case .appBackgrounded, .interruptionBegan:
            let reason: EndReason = event == .appBackgrounded ? .background : .interrupted
            if s.isActive {
                s.phase = .ended(reason)
                s.socketOpen = false
                s.pttHeld = false
                s.isUserSpeaking = false
                return (s, teardown)
            }
            return (s, [.stopAudio])

        case .audioFailed(let message):
            if s.isActive {
                s.phase = .ended(.error(message))
                s.socketOpen = false
                s.pttHeld = false
                s.isUserSpeaking = false
                return (s, teardown)
            }
            s.hint = message
            return (s, [.stopAudio])

        case .socketFailed(let message):
            guard s.isActive else { return (s, []) }
            s.socketOpen = false
            s.pttHeld = false
            s.isUserSpeaking = false
            switch s.mode {
            case .handsFree:
                s.phase = .ended(.error(message))
                return (s, [.cancelThinkingWatchdog, .micGate(open: false), .playbackFlush, .stopAudio])
            case .pushToTalk:
                s.phase = .idle
                s.hint = message
                return (s, [.cancelThinkingWatchdog, .cancelMaxHoldTimer, .micGate(open: false)])
            }

        default:
            return nil
        }
    }

    // MARK: - Hands-free

    private static func reduceHandsFree(_ state: CallState, _ event: CallEvent) -> (CallState, [CallEffect]) {
        var s = state
        switch (s.phase, event) {
        case (.idle, .startCall), (.ended, .startCall):
            s = CallState(mode: .handsFree, phase: .connecting)
            return (s, [.startAudio, .openSocket])

        case (.connecting, .socketOpened):
            s.phase = .listening
            s.socketOpen = true
            return (s, [.micGate(open: true), .resetVAD, .fetchTranscript])

        case (.listening, .localSpeechStarted), (.thinking, .localSpeechStarted):
            s.isUserSpeaking = true
            return (s, [])

        case (.listening, .localTurnDiscarded), (.thinking, .localTurnDiscarded):
            s.isUserSpeaking = false
            return (s, [])

        case (.listening, .localTurnEnded):
            s.phase = .thinking
            s.isUserSpeaking = false
            s.hint = nil
            return (s, [.startThinkingWatchdog])

        case (.thinking, .localTurnEnded):
            s.isUserSpeaking = false
            return (s, [.startThinkingWatchdog])

        case (.listening, .audioFrame):
            s.phase = .speaking
            s.receivedAudioThisTurn = true
            s.isUserSpeaking = false
            return (s, [.micGate(open: false), .playbackEnqueue])

        case (.thinking, .audioFrame):
            s.phase = .speaking
            s.receivedAudioThisTurn = true
            return (s, [.cancelThinkingWatchdog, .micGate(open: false), .playbackEnqueue])

        case (.speaking, .audioFrame):
            return (s, [.playbackEnqueue])

        case (.thinking, .thinkingTimeout):
            s.phase = .listening
            s.hint = L10n.Hints.noReply
            return (s, [.resetVAD])

        case (.speaking, .clearReceived), (.speaking, .localBargeIn):
            s.phase = .listening
            s.receivedAudioThisTurn = false
            return (s, [.playbackFlush, .micGate(open: true), .resetVAD])

        case (.speaking, .playbackDrained):
            s.receivedAudioThisTurn = false
            if s.socketOpen {
                s.phase = .listening
                return (s, [.micGate(open: true), .resetVAD, .fetchTranscript])
            }
            let close = s.pendingClose
            s.pendingClose = nil
            s.phase = .ended(.remote(code: close?.code ?? 1000, reason: close?.reason))
            return (s, [.stopAudio, .fetchTranscript])

        case (.speaking, .socketClosed(let code, let reason)):
            s.socketOpen = false
            s.pendingClose = RemoteClose(code: code, reason: reason)
            return (s, [])

        case (.connecting, .socketClosed(let code, let reason)),
             (.listening, .socketClosed(let code, let reason)),
             (.thinking, .socketClosed(let code, let reason)):
            s.phase = .ended(.remote(code: code, reason: reason))
            s.socketOpen = false
            s.isUserSpeaking = false
            return (s, [.cancelThinkingWatchdog, .micGate(open: false), .stopAudio, .fetchTranscript])

        default:
            return (s, [])
        }
    }

    // MARK: - Push-to-talk

    private static func reducePushToTalk(_ state: CallState, _ event: CallEvent) -> (CallState, [CallEffect]) {
        var s = state
        switch (s.phase, event) {
        case (.idle, .startCall), (.ended, .startCall):
            s.phase = .idle
            s.hint = nil
            return (s, [.startAudio])

        case (.idle, .pressPTT), (.ended, .pressPTT):
            s = CallState(mode: .pushToTalk, phase: .connecting, pttHeld: true)
            return (s, [.startAudio, .openSocket])

        case (.connecting, .releasePTT):
            s.pttHeld = false
            return (s, [])

        case (.connecting, .socketOpened):
            if s.pttHeld {
                s.phase = .recording
                s.socketOpen = true
                return (s, [.micGate(open: true), .resetVAD, .startMaxHoldTimer])
            }
            s.phase = .idle
            s.socketOpen = false
            s.hint = L10n.Hints.holdToTalk
            return (s, [.closeSocket])

        case (.recording, .releasePTT), (.recording, .maxHoldElapsed):
            s.phase = .thinking
            s.isUserSpeaking = false
            if event == .releasePTT { s.pttHeld = false }
            return (s, [.micGate(open: false), .cancelMaxHoldTimer, .sendStop, .startThinkingWatchdog])

        case (.recording, .localSpeechStarted):
            s.isUserSpeaking = true
            return (s, [])

        case (.recording, .localTurnEnded), (.recording, .localTurnDiscarded):
            s.isUserSpeaking = false
            return (s, [])

        case (.recording, .audioFrame):
            // The server force-split a long utterance and replied while the button is still held.
            s.phase = .speaking
            s.receivedAudioThisTurn = true
            s.isUserSpeaking = false
            return (s, [.micGate(open: false), .cancelMaxHoldTimer, .playbackEnqueue])

        case (.thinking, .audioFrame):
            s.phase = .speaking
            s.receivedAudioThisTurn = true
            return (s, [.cancelThinkingWatchdog, .playbackEnqueue])

        case (.speaking, .audioFrame):
            return (s, [.playbackEnqueue])

        case (.speaking, .releasePTT):
            s.pttHeld = false
            return (s, s.socketOpen ? [.sendStop] : [])

        case (.thinking, .releasePTT):
            s.pttHeld = false
            return (s, [])

        case (.thinking, .pressPTT):
            s.hint = L10n.Hints.waitingReply
            return (s, [])

        case (.thinking, .socketClosed(let code, let reason)):
            s.socketOpen = false
            s.phase = .idle
            if s.receivedAudioThisTurn {
                s.hint = nil
            } else if code == 1000 {
                s.hint = L10n.Hints.notHeard
            } else {
                s.hint = closeHint(code: code, reason: reason)
            }
            s.receivedAudioThisTurn = false
            return (s, [.cancelThinkingWatchdog])

        case (.connecting, .socketClosed(let code, let reason)), (.recording, .socketClosed(let code, let reason)):
            s.socketOpen = false
            s.phase = .idle
            s.pttHeld = false
            s.isUserSpeaking = false
            s.hint = closeHint(code: code, reason: reason)
            return (s, [.micGate(open: false), .cancelMaxHoldTimer])

        case (.speaking, .socketClosed(let code, let reason)):
            s.socketOpen = false
            s.pendingClose = RemoteClose(code: code, reason: reason)
            return (s, [])

        case (.thinking, .thinkingTimeout):
            s.phase = .idle
            s.socketOpen = false
            s.hint = L10n.Hints.noReplyPTT
            return (s, [.closeSocket])

        case (.speaking, .playbackDrained):
            s.phase = .idle
            s.receivedAudioThisTurn = false
            s.pendingClose = nil
            let effects: [CallEffect] = s.socketOpen ? [.closeSocket, .fetchTranscript] : [.fetchTranscript]
            s.socketOpen = false
            return (s, effects)

        case (.speaking, .pressPTT):
            s = CallState(mode: .pushToTalk, phase: .connecting, pttHeld: true)
            return (s, [.playbackFlush, .closeSocket, .openSocket])

        case (.speaking, .clearReceived):
            s.phase = .idle
            s.receivedAudioThisTurn = false
            return (s, [.playbackFlush])

        default:
            return (s, [])
        }
    }

    static func closeHint(code: Int, reason: String?) -> String {
        if let reason, !reason.isEmpty { return reason }
        return String(format: L10n.Hints.closedWithCode, code)
    }
}
