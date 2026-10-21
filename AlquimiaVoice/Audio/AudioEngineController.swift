import AVFoundation

enum AudioError: Error, Equatable, LocalizedError {
    case microphoneDenied
    case noInputAvailable
    case converterUnavailable
    case engineStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return L10n.Errors.microphoneDenied
        case .noInputAvailable: return L10n.Errors.noInput
        case .converterUnavailable: return L10n.Errors.converter
        case .engineStartFailed(let detail): return String(format: L10n.Errors.engineStart, detail)
        }
    }
}

/// Owns the single `AVAudioEngine` used for both capture and playback (one I/O unit, so echo cancellation
/// has the reply audio as its reference). Start order matters: session category → voice processing →
/// read input format → tap → player connection → prepare → start.
@AudioActor
final class AudioEngineController {
    enum Notice: Equatable, Sendable {
        case interruptionBegan
        case interruptionEnded
        case mediaServicesReset
        case configurationChanged
        case failed(String)
    }

    nonisolated let capture: AsyncStream<[Int16]>
    nonisolated let notices: AsyncStream<Notice>
    nonisolated let playbackEvents: AsyncStream<PlaybackQueue.Event>

    private let captureContinuation: AsyncStream<[Int16]>.Continuation
    private let noticeContinuation: AsyncStream<Notice>.Continuation
    private let playbackContinuation: AsyncStream<PlaybackQueue.Event>.Continuation

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var playback: PlaybackQueue?
    private var processor: CaptureProcessor?
    private var observers: [any NSObjectProtocol] = []
    private var watchdog: Task<Void, Never>?
    private var lastRebuild: ContinuousClock.Instant?

    private(set) var isRunning = false
    private(set) var voiceProcessingEnabled = false
    /// Set to `false` to skip echo cancellation (also flipped automatically when the tap stays silent).
    var wantsVoiceProcessing = true

    nonisolated init() {
        let (capture, captureContinuation) = AsyncStream.makeStream(of: [Int16].self, bufferingPolicy: .bufferingNewest(64))
        let (notices, noticeContinuation) = AsyncStream.makeStream(of: Notice.self, bufferingPolicy: .bufferingNewest(16))
        let (playback, playbackContinuation) = AsyncStream.makeStream(of: PlaybackQueue.Event.self, bufferingPolicy: .bufferingNewest(16))
        self.capture = capture
        self.captureContinuation = captureContinuation
        self.notices = notices
        self.noticeContinuation = noticeContinuation
        self.playbackEvents = playback
        self.playbackContinuation = playbackContinuation
    }

    // MARK: - Lifecycle

    func start() async throws {
        if isRunning { return }
        guard await Self.requestMicrophonePermission() else { throw AudioError.microphoneDenied }
        try configureSession()
        try buildEngine(voiceProcessing: wantsVoiceProcessing)
        installObservers()
        isRunning = true
        startWatchdog()
    }

    func stop() {
        watchdog?.cancel()
        watchdog = nil
        tearDownEngine()
        isRunning = false
        deactivateSession()
    }

    // MARK: - Playback

    func enqueuePlayback(_ samples: [Int16]) {
        playback?.enqueue(samples)
    }

    func flushPlayback() {
        playback?.flush()
    }

    /// Remainder of the capture chunker, sent before `stop` in push-to-talk mode.
    func flushCapture() -> [Int16]? {
        processor?.flush()
    }

    // MARK: - Session

    private static func requestMicrophonePermission() async -> Bool {
        #if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
        #else
        return true
        #endif
    }

    private func configureSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        #if targetEnvironment(simulator)
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        #else
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        #endif
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true, options: [])
        #endif
    }

    private func deactivateSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            Log.audio.debug("session deactivate: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    // MARK: - Graph

    private func buildEngine(voiceProcessing: Bool) throws {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let input = engine.inputNode
        voiceProcessingEnabled = false
        #if os(iOS) && !targetEnvironment(simulator)
        if voiceProcessing {
            do {
                try input.setVoiceProcessingEnabled(true)
                voiceProcessingEnabled = true
            } catch {
                Log.audio.warning("voice processing unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif

        // Read the format only after toggling voice processing: it changes the rate.
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioError.noInputAvailable
        }
        let continuation = captureContinuation
        guard let processor = CaptureProcessor(inputFormat: inputFormat, emit: { samples in
            continuation.yield(samples)
        }) else {
            throw AudioError.converterUnavailable
        }
        // `@Sendable` keeps the tap block nonisolated: it runs on CoreAudio's real-time messenger queue,
        // and an actor-isolated closure would trip Swift 6's dynamic isolation check there.
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { @Sendable buffer, _ in
            processor.process(buffer)
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: PlaybackQueue.makeFormat())
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioError.engineStartFailed(error.localizedDescription)
        }

        self.engine = engine
        self.player = player
        self.processor = processor
        self.playback = PlaybackQueue(player: player, engine: engine, continuation: playbackContinuation)
        lastRebuild = .now
        Log.audio.info(
            "engine started: input \(inputFormat.sampleRate, privacy: .public) Hz x\(inputFormat.channelCount, privacy: .public), voiceProcessing=\(self.voiceProcessingEnabled, privacy: .public)"
        )
    }

    private func tearDownEngine() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
        }
        playback?.flush()
        engine = nil
        player = nil
        playback = nil
        processor = nil
    }

    private func rebuild(voiceProcessing: Bool) {
        tearDownEngine()
        do {
            try buildEngine(voiceProcessing: voiceProcessing)
        } catch {
            Log.audio.error("engine rebuild failed: \(error.localizedDescription, privacy: .public)")
            isRunning = false
            noticeContinuation.yield(.failed(error.localizedDescription))
        }
    }

    /// If voice processing swallowed the input (no tap callbacks shortly after start), rebuild without it.
    private func startWatchdog() {
        watchdog?.cancel()
        guard voiceProcessingEnabled else { return }
        watchdog = Task { @AudioActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled, let self, self.isRunning else { return }
            if (self.processor?.processedBufferCount ?? 0) == 0 {
                Log.audio.warning("no input with voice processing enabled; rebuilding without it")
                self.wantsVoiceProcessing = false
                self.rebuild(voiceProcessing: false)
            }
        }
    }

    // MARK: - Notifications

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { [weak self] note in
            let identifier = (note.object as AnyObject?).map { ObjectIdentifier($0) }
            Task { @AudioActor in self?.handleConfigurationChange(engineID: identifier) }
        })
        #if os(iOS)
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = rawType == AVAudioSession.InterruptionType.began.rawValue
            Task { @AudioActor in self?.handleInterruption(began: began) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @AudioActor in self?.handleMediaServicesReset() }
        })
        #endif
    }

    private func handleConfigurationChange(engineID: ObjectIdentifier?) {
        guard isRunning, let engine, engineID == ObjectIdentifier(engine) else { return }
        if let lastRebuild, lastRebuild.duration(to: .now) < .milliseconds(300) { return }
        Log.audio.info("engine configuration changed; rebuilding")
        rebuild(voiceProcessing: voiceProcessingEnabled)
        noticeContinuation.yield(.configurationChanged)
    }

    private func handleInterruption(began: Bool) {
        if began {
            Log.audio.info("audio interruption began")
            tearDownEngine()
            isRunning = false
            noticeContinuation.yield(.interruptionBegan)
        } else {
            noticeContinuation.yield(.interruptionEnded)
        }
    }

    private func handleMediaServicesReset() {
        Log.audio.warning("media services were reset")
        tearDownEngine()
        isRunning = false
        noticeContinuation.yield(.mediaServicesReset)
    }
}
