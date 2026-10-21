import Testing
@testable import AlquimiaVoice

@Suite("Call reducer · hands-free")
struct HandsFreeReducerTests {
    private func run(_ events: [CallEvent], from state: CallState = CallState(mode: .handsFree)) -> (CallState, [CallEffect]) {
        var current = state
        var lastEffects: [CallEffect] = []
        for event in events {
            (current, lastEffects) = CallReducer.reduce(current, event)
        }
        return (current, lastEffects)
    }

    @Test func startOpensAudioAndSocket() {
        let (state, effects) = run([.startCall])
        #expect(state.phase == .connecting)
        #expect(effects == [.startAudio, .openSocket])
    }

    @Test func socketOpenedStartsListening() {
        let (state, effects) = run([.startCall, .socketOpened])
        #expect(state.phase == .listening)
        #expect(state.socketOpen)
        #expect(effects == [.micGate(open: true), .resetVAD, .fetchTranscript])
        #expect(state.allowsSending)
    }

    @Test func fullTurn() {
        var (state, effects) = run([.startCall, .socketOpened, .localSpeechStarted])
        #expect(state.isUserSpeaking)
        (state, effects) = run([.localTurnEnded], from: state)
        #expect(state.phase == .thinking)
        #expect(effects == [.startThinkingWatchdog])
        #expect(state.allowsSending, "mic keeps streaming while thinking")

        (state, effects) = run([.audioFrame], from: state)
        #expect(state.phase == .speaking)
        #expect(effects == [.cancelThinkingWatchdog, .micGate(open: false), .playbackEnqueue])
        #expect(!state.allowsSending)

        (state, effects) = run([.audioFrame, .localSpeechStarted, .localTurnEnded], from: state)
        #expect(state.phase == .speaking, "echo-driven VAD events are ignored while speaking")

        (state, effects) = run([.playbackDrained], from: state)
        #expect(state.phase == .listening)
        #expect(effects == [.micGate(open: true), .resetVAD, .fetchTranscript])
    }

    @Test func unsolicitedReplyWhileListening() {
        let (state, effects) = run([.startCall, .socketOpened, .audioFrame])
        #expect(state.phase == .speaking)
        #expect(effects == [.micGate(open: false), .playbackEnqueue])
    }

    @Test func thinkingTimeoutReturnsToListeningWithHint() {
        let (state, effects) = run([.startCall, .socketOpened, .localTurnEnded, .thinkingTimeout])
        #expect(state.phase == .listening)
        #expect(state.hint == L10n.Hints.noReply)
        #expect(effects == [.resetVAD])
        let (late, lateEffects) = run([.audioFrame], from: state)
        #expect(late.phase == .speaking)
        #expect(lateEffects == [.micGate(open: false), .playbackEnqueue])
    }

    @Test func socketClosedWhileSpeakingEndsAfterDrain() {
        var (state, _) = run([.startCall, .socketOpened, .localTurnEnded, .audioFrame])
        (state, _) = run([.socketClosed(code: 1008, reason: "Streaming session lifetime exceeded")], from: state)
        #expect(state.phase == .speaking)
        #expect(!state.socketOpen)
        let (ended, effects) = run([.playbackDrained], from: state)
        #expect(ended.phase == .ended(.remote(code: 1008, reason: "Streaming session lifetime exceeded")))
        #expect(effects == [.stopAudio, .fetchTranscript])
    }

    @Test func socketClosedWhileListeningEndsImmediately() {
        let (state, effects) = run([.startCall, .socketOpened, .socketClosed(code: 1011, reason: nil)])
        #expect(state.phase == .ended(.remote(code: 1011, reason: nil)))
        #expect(effects == [.cancelThinkingWatchdog, .micGate(open: false), .stopAudio, .fetchTranscript])
    }

    @Test func handshakeFailureEndsWithError() {
        let (state, effects) = run([.startCall, .socketFailed("401")])
        #expect(state.phase == .ended(.error("401")))
        #expect(effects.contains(.stopAudio))
        #expect(!effects.contains(.closeSocket))
    }

    @Test func clearAndLocalBargeInFlushPlayback() {
        let speaking = run([.startCall, .socketOpened, .audioFrame]).0
        for event in [CallEvent.clearReceived, .localBargeIn] {
            let (state, effects) = run([event], from: speaking)
            #expect(state.phase == .listening)
            #expect(effects == [.playbackFlush, .micGate(open: true), .resetVAD])
        }
    }

    @Test func endCallAndBackgroundTearDown() {
        let active = run([.startCall, .socketOpened]).0
        let (ended, effects) = run([.endCall], from: active)
        #expect(ended.phase == .ended(.user))
        #expect(effects == CallReducer.teardown)
        let (background, bgEffects) = run([.appBackgrounded], from: active)
        #expect(background.phase == .ended(.background))
        #expect(bgEffects == CallReducer.teardown)
        let (idle, idleEffects) = run([.appBackgrounded])
        #expect(idle.phase == .idle)
        #expect(idleEffects == [.stopAudio])
    }

    @Test func restartAfterEnded() {
        let ended = run([.startCall, .socketOpened, .endCall]).0
        let (state, effects) = run([.startCall], from: ended)
        #expect(state.phase == .connecting)
        #expect(effects == [.startAudio, .openSocket])
        #expect(state.hint == nil)
    }

    @Test func pttEventsAreIgnored() {
        let listening = run([.startCall, .socketOpened]).0
        let (state, effects) = run([.pressPTT, .releasePTT, .maxHoldElapsed], from: listening)
        #expect(state == listening)
        #expect(effects.isEmpty)
    }
}

@Suite("Call reducer · push-to-talk")
struct PushToTalkReducerTests {
    private func run(_ events: [CallEvent], from state: CallState = CallState(mode: .pushToTalk)) -> (CallState, [CallEffect]) {
        var current = state
        var lastEffects: [CallEffect] = []
        for event in events {
            (current, lastEffects) = CallReducer.reduce(current, event)
        }
        return (current, lastEffects)
    }

    @Test func pressOpensSocketAndRecordsOnOpen() {
        var (state, effects) = run([.pressPTT])
        #expect(state.phase == .connecting)
        #expect(state.pttHeld)
        #expect(effects == [.startAudio, .openSocket])
        (state, effects) = run([.socketOpened], from: state)
        #expect(state.phase == .recording)
        #expect(effects == [.micGate(open: true), .resetVAD, .startMaxHoldTimer])
        #expect(state.allowsSending)
    }

    @Test func releaseBeforeOpenClosesSocket() {
        let (state, effects) = run([.pressPTT, .releasePTT, .socketOpened])
        #expect(state.phase == .idle)
        #expect(state.hint == L10n.Hints.holdToTalk)
        #expect(effects == [.closeSocket])
    }

    @Test func releaseSendsStopAndWaits() {
        var (state, effects) = run([.pressPTT, .socketOpened, .releasePTT])
        #expect(state.phase == .thinking)
        #expect(!state.pttHeld)
        #expect(effects == [.micGate(open: false), .cancelMaxHoldTimer, .sendStop, .startThinkingWatchdog])
        (state, effects) = run([.audioFrame], from: state)
        #expect(state.phase == .speaking)
        #expect(effects == [.cancelThinkingWatchdog, .playbackEnqueue])
        (state, effects) = run([.socketClosed(code: 1000, reason: nil)], from: state)
        #expect(state.phase == .speaking)
        (state, effects) = run([.playbackDrained], from: state)
        #expect(state.phase == .idle)
        #expect(effects == [.fetchTranscript])
    }

    @Test func maxHoldBehavesLikeRelease() {
        let (state, effects) = run([.pressPTT, .socketOpened, .maxHoldElapsed])
        #expect(state.phase == .thinking)
        #expect(state.pttHeld)
        #expect(effects.contains(.sendStop))
    }

    @Test func closeWithoutAudioMeansNotHeard() {
        let (state, effects) = run([.pressPTT, .socketOpened, .releasePTT, .socketClosed(code: 1000, reason: nil)])
        #expect(state.phase == .idle)
        #expect(state.hint == L10n.Hints.notHeard)
        #expect(effects == [.cancelThinkingWatchdog])
    }

    @Test func closeWithReasonShowsReason() {
        let (state, _) = run([.pressPTT, .socketOpened, .releasePTT, .socketClosed(code: 1008, reason: "Assistant x has no audio configuration")])
        #expect(state.phase == .idle)
        #expect(state.hint == "Assistant x has no audio configuration")
    }

    @Test func thinkingTimeoutClosesSocket() {
        let (state, effects) = run([.pressPTT, .socketOpened, .releasePTT, .thinkingTimeout])
        #expect(state.phase == .idle)
        #expect(state.hint == L10n.Hints.noReplyPTT)
        #expect(effects == [.closeSocket])
    }

    @Test func forceSplitWhileHeld() {
        var (state, effects) = run([.pressPTT, .socketOpened, .audioFrame])
        #expect(state.phase == .speaking)
        #expect(effects == [.micGate(open: false), .cancelMaxHoldTimer, .playbackEnqueue])
        (state, effects) = run([.releasePTT], from: state)
        #expect(effects == [.sendStop])
        #expect(!state.pttHeld)
    }

    @Test func bargeInByPressingDuringReply() {
        let speaking = run([.pressPTT, .socketOpened, .releasePTT, .audioFrame]).0
        let (state, effects) = run([.pressPTT], from: speaking)
        #expect(state.phase == .connecting)
        #expect(state.pttHeld)
        #expect(effects == [.playbackFlush, .closeSocket, .openSocket])
    }

    @Test func pressWhileThinkingOnlyHints() {
        let (state, effects) = run([.pressPTT, .socketOpened, .releasePTT, .pressPTT])
        #expect(state.phase == .thinking)
        #expect(state.hint == L10n.Hints.waitingReply)
        #expect(effects.isEmpty)
    }

    @Test func socketFailureReturnsToIdleWithHint() {
        let (state, effects) = run([.pressPTT, .socketFailed("boom")])
        #expect(state.phase == .idle)
        #expect(state.hint == "boom")
        #expect(effects == [.cancelThinkingWatchdog, .cancelMaxHoldTimer, .micGate(open: false)])
    }

    @Test func backgroundWhileIdleStopsAudioOnly() {
        let (state, effects) = run([.appBackgrounded])
        #expect(state.phase == .idle)
        #expect(effects == [.stopAudio])
    }

    @Test func startCallOnlyWarmsAudio() {
        let (state, effects) = run([.startCall])
        #expect(state.phase == .idle)
        #expect(effects == [.startAudio])
    }
}
