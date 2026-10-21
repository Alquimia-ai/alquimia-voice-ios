import AVFoundation

/// Schedules reply audio on an `AVAudioPlayerNode` connected at Float32 16 kHz mono (the mixer resamples
/// to the hardware rate). Replies arrive as an unpaced burst of 20 ms frames, so the queue primes ~100 ms
/// before the first `scheduleBuffer`, then schedules as frames arrive. Because the server sends no
/// end-of-reply event, "drained" is derived from the last `.dataPlayedBack` completion plus a quiet timer.
@AudioActor
final class PlaybackQueue {
    enum Event: Equatable, Sendable {
        case started
        case drained
    }

    static func makeFormat() -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: PCM.sampleRate, channels: 1)!
    }

    private let player: AVAudioPlayerNode
    private let engine: AVAudioEngine
    private let continuation: AsyncStream<Event>.Continuation
    private let format: AVAudioFormat
    private let primeSamples: Int
    private let idleDelay: Duration = .milliseconds(80)
    private let quietDelay: Duration = .milliseconds(300)

    private var pending: [Int16] = []
    private var generation = 0
    private var lastScheduledSeq = 0
    private var lastCompletedSeq = 0
    private var idleTask: Task<Void, Never>?
    private var quietTask: Task<Void, Never>?
    private(set) var isPlaying = false

    init(
        player: AVAudioPlayerNode,
        engine: AVAudioEngine,
        continuation: AsyncStream<Event>.Continuation,
        primeSamples: Int = 1600
    ) {
        self.player = player
        self.engine = engine
        self.continuation = continuation
        self.primeSamples = primeSamples
        self.format = Self.makeFormat()
    }

    func enqueue(_ samples: [Int16]) {
        quietTask?.cancel()
        quietTask = nil
        pending.append(contentsOf: samples)
        if pending.count >= primeSamples {
            scheduleAll()
        } else {
            armIdleTimer()
        }
    }

    /// Schedules anything held while the engine was not running.
    func kick() {
        if !pending.isEmpty { scheduleAll() }
    }

    /// Drops queued and scheduled audio (barge-in, `clear`, end of call).
    func flush() {
        generation += 1
        pending.removeAll(keepingCapacity: true)
        idleTask?.cancel()
        idleTask = nil
        quietTask?.cancel()
        quietTask = nil
        if engine.isRunning { player.stop() }
        isPlaying = false
        lastScheduledSeq = 0
        lastCompletedSeq = 0
    }

    // MARK: - Internals

    private func armIdleTimer() {
        idleTask?.cancel()
        idleTask = Task { @AudioActor [weak self, idleDelay] in
            try? await Task.sleep(for: idleDelay)
            guard !Task.isCancelled else { return }
            self?.scheduleAll()
        }
    }

    private func scheduleAll() {
        idleTask?.cancel()
        idleTask = nil
        guard !pending.isEmpty else { return }
        guard engine.isRunning else {
            Log.audio.debug("engine not running; holding \(self.pending.count) samples")
            return
        }
        let samples = pending
        pending.removeAll(keepingCapacity: true)
        guard let buffer = makeBuffer(samples) else { return }

        lastScheduledSeq += 1
        let seq = lastScheduledSeq
        let gen = generation
        // Completion handlers arrive on an internal AVFAudio queue; `@Sendable` keeps the closure
        // nonisolated and the Task hops back onto the audio actor.
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { @Sendable [weak self] _ in
            Task { @AudioActor in self?.completed(seq: seq, generation: gen) }
        }
        if !isPlaying {
            player.play()
            isPlaying = true
            continuation.yield(.started)
        }
    }

    private func completed(seq: Int, generation gen: Int) {
        guard gen == generation else { return }
        lastCompletedSeq = max(lastCompletedSeq, seq)
        guard seq == lastScheduledSeq, pending.isEmpty else { return }
        quietTask?.cancel()
        quietTask = Task { @AudioActor [weak self, quietDelay] in
            try? await Task.sleep(for: quietDelay)
            guard !Task.isCancelled else { return }
            self?.drainIfIdle()
        }
    }

    private func drainIfIdle() {
        guard isPlaying, pending.isEmpty, lastCompletedSeq == lastScheduledSeq else { return }
        if engine.isRunning { player.stop() }
        isPlaying = false
        lastScheduledSeq = 0
        lastCompletedSeq = 0
        continuation.yield(.drained)
    }

    private func makeBuffer(_ samples: [Int16]) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames
        let destination = channel[0]
        for (index, sample) in samples.enumerated() {
            destination[index] = Float(sample) / 32768
        }
        return buffer
    }
}
