import Foundation

/// Client-side mirror of the runtime's `EnergyVADTurnSegmenter`, used only to drive UI state
/// (the server performs the real turn segmentation). Same semantics:
/// - 30 ms analysis windows, frame-count clock (not wall clock)
/// - speech when normalised RMS > activation
/// - the speech span runs from the first speech frame to the end of the last speech frame
/// - silence is measured from the end of the last speech frame
/// - a turn ends after `silenceMs` of trailing silence or `maxUtteranceMs` since speech started
/// - spans shorter than `minSpeechMs` are discarded
struct LocalVAD: Equatable, Sendable {
    struct Params: Equatable, Sendable {
        var sampleRate = 16_000
        var frameMs = 30
        var activation: Float = 0.01
        var minSpeechMs = 250
        var silenceMs = 700
        var maxUtteranceMs = 10_000

        var frameSamples: Int { sampleRate * frameMs / 1000 }
    }

    enum Event: Equatable, Sendable {
        case speechStarted
        case turnEnded(speechMs: Int)
        case turnDiscarded
    }

    var params: Params
    private var pending: [Int16] = []
    private var elapsedMs = 0
    private var speechStartMs: Int?
    private var lastSpeechEndMs: Int?

    init(params: Params = Params()) {
        self.params = params
    }

    var isSpeaking: Bool { speechStartMs != nil }

    mutating func consume(_ samples: [Int16]) -> [Event] {
        pending.append(contentsOf: samples)
        var events: [Event] = []
        let size = params.frameSamples
        while pending.count >= size {
            let frame = Array(pending[..<size])
            pending.removeFirst(size)
            events.append(contentsOf: process(frame: frame))
        }
        return events
    }

    mutating func reset() {
        pending.removeAll(keepingCapacity: true)
        elapsedMs = 0
        speechStartMs = nil
        lastSpeechEndMs = nil
    }

    private mutating func process(frame: [Int16]) -> [Event] {
        let frameStart = elapsedMs
        elapsedMs += params.frameMs
        var events: [Event] = []
        if PCM.rms(frame) > params.activation {
            if speechStartMs == nil {
                speechStartMs = frameStart
                events.append(.speechStarted)
            }
            lastSpeechEndMs = elapsedMs
        }
        guard let start = speechStartMs, let lastEnd = lastSpeechEndMs else { return events }
        let trailingSilence = elapsedMs - lastEnd
        let utterance = elapsedMs - start
        if trailingSilence >= params.silenceMs || utterance >= params.maxUtteranceMs {
            let span = lastEnd - start
            events.append(span >= params.minSpeechMs ? .turnEnded(speechMs: span) : .turnDiscarded)
            speechStartMs = nil
            lastSpeechEndMs = nil
        }
        return events
    }
}
