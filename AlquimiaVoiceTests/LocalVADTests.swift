import Testing
@testable import AlquimiaVoice

/// The VAD clock advances in whole 30 ms frames, exactly like the server, so durations here are
/// frame-aligned and trailing silence is measured from the end of the last *frame* that held speech.
@Suite("Local VAD mirrors the server segmenter")
struct LocalVADTests {
    @Test func shortSpeechIsDiscarded() {
        var vad = LocalVAD()
        var events = vad.consume(TestSignals.sine(ms: 240))
        #expect(events == [.speechStarted])
        #expect(vad.consume(TestSignals.silence(ms: 690)).isEmpty)
        events = vad.consume(TestSignals.silence(ms: 30))
        #expect(events == [.turnDiscarded])
        #expect(!vad.isSpeaking)
    }

    @Test func turnEndsAfterSevenHundredMillisecondsOfSilence() {
        var vad = LocalVAD()
        #expect(vad.consume(TestSignals.sine(ms: 300)) == [.speechStarted])
        #expect(vad.consume(TestSignals.silence(ms: 690)).isEmpty)
        #expect(vad.consume(TestSignals.silence(ms: 30)) == [.turnEnded(speechMs: 300)])
        #expect(!vad.isSpeaking)
    }

    @Test func interiorGapCountsTowardTheSameTurn() {
        var vad = LocalVAD()
        var events = vad.consume(TestSignals.sine(ms: 150))
        events += vad.consume(TestSignals.silence(ms: 420))
        events += vad.consume(TestSignals.sine(ms: 150))
        #expect(events == [.speechStarted])
        #expect(vad.isSpeaking)
        events = vad.consume(TestSignals.silence(ms: 720))
        #expect(events == [.turnEnded(speechMs: 720)])
    }

    @Test func longSpeechIsForceSplit() {
        var vad = LocalVAD()
        var events: [LocalVAD.Event] = []
        for _ in 0..<10 { events += vad.consume(TestSignals.sine(ms: 1_020)) }
        // Split at the first frame that reaches 10 s, then the remaining speech starts a new turn.
        #expect(events == [.speechStarted, .turnEnded(speechMs: 10_020), .speechStarted])
    }

    @Test func partialFramesAreCarriedOver() {
        var vad = LocalVAD()
        // 25 ms + 5 ms = one 30 ms frame; nothing is processed until the frame is complete.
        #expect(vad.consume(TestSignals.sine(ms: 25)).isEmpty)
        #expect(vad.consume(TestSignals.sine(ms: 5)) == [.speechStarted])
    }

    @Test func noiseBelowThresholdIsSilence() {
        var vad = LocalVAD()
        #expect(vad.consume(TestSignals.noise(ms: 600)).isEmpty)
        #expect(!vad.isSpeaking)
    }

    @Test func thresholdIsStrictlyGreater() {
        var vad = LocalVAD()
        // A square wave at ±327 has RMS 0.00998 (just under the 0.01 activation ratio): silence.
        let under: [Int16] = (0..<480).map { $0 % 2 == 0 ? 327 : -327 }
        #expect(vad.consume(under).isEmpty)
        #expect(!vad.isSpeaking)
        // ±336 → 0.01025: speech.
        let over: [Int16] = (0..<480).map { $0 % 2 == 0 ? 336 : -336 }
        #expect(vad.consume(over) == [.speechStarted])
    }

    @Test func resetClearsState() {
        var vad = LocalVAD()
        _ = vad.consume(TestSignals.sine(ms: 300))
        vad.reset()
        #expect(!vad.isSpeaking)
        #expect(vad.consume(TestSignals.silence(ms: 1_000)).isEmpty)
    }

    @Test func customThresholdApplies() {
        var params = LocalVAD.Params()
        params.activation = 0.2
        var vad = LocalVAD(params: params)
        #expect(vad.consume(TestSignals.sine(ms: 300, amplitude: 0.1)).isEmpty)
    }
}
