import Foundation
import Observation

/// Wires microphone capture, the live socket and playback together and runs the state machine.
/// Everything here is on the main actor; audio objects live on `AudioActor`, the socket in its own actor.
@MainActor
@Observable
final class CallSession {
    private(set) var state: CallState
    private(set) var inputLevel: Float = 0
    private(set) var inputDBFS: Float = LevelMeter.floorDBFS
    private(set) var transcript: [TranscriptMessage] = []
    private(set) var transcriptError: String?
    private(set) var isLoadingTranscript = false
    private(set) var callStartedAt: Date?
    private(set) var echoCancellationActive = false
    var isMuted = false

    let thinkingTimeout: Duration
    let maxHold: Duration

    private let settings: SettingsStore
    private let auth: AuthManager
    private let audio: AudioEngineController
    private let transcriptClient: TranscriptClient

    private var connection: LiveConnection?
    private var connectionGeneration = 0
    private var connectionTask: Task<Void, Never>?
    private var audioStartTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var noticesTask: Task<Void, Never>?
    private var transcriptTask: Task<Void, Never>?
    private var thinkingWatchdog: Task<Void, Never>?
    private var maxHoldTimer: Task<Void, Never>?

    private var vad: LocalVAD
    private var bargeVAD: LocalVAD
    private var meter = LevelMeter()
    private var micOpen = false
    private var enqueueRequested = false

    init(
        settings: SettingsStore,
        auth: AuthManager,
        audio: AudioEngineController,
        transcriptClient: TranscriptClient = TranscriptClient(),
        thinkingTimeout: Duration = .seconds(45),
        maxHold: Duration = .milliseconds(9_500)
    ) {
        self.settings = settings
        self.auth = auth
        self.audio = audio
        self.transcriptClient = transcriptClient
        self.thinkingTimeout = thinkingTimeout
        self.maxHold = maxHold
        self.state = CallState(mode: settings.mode)
        self.vad = LocalVAD(params: settings.vadParams)
        self.bargeVAD = LocalVAD(params: settings.bargeInParams)
        startConsumers()
    }

    // MARK: - Public API

    var mode: VoiceMode { state.isActive ? state.mode : settings.mode }
    var hint: String? { state.hint }

    func startCall() {
        syncModeIfIdle()
        dispatch(.startCall)
    }

    func endCall() {
        dispatch(.endCall)
    }

    func pressPTT() {
        syncModeIfIdle()
        dispatch(.pressPTT)
    }

    func releasePTT() {
        dispatch(.releasePTT)
    }

    func toggleMute() {
        isMuted.toggle()
    }

    /// Ends any active call, rotates the session id and clears the transcript.
    func newConversation() {
        if state.isActive { dispatch(.endCall) }
        settings.newSession()
        transcript = []
        transcriptError = nil
        state = CallState(mode: settings.mode)
    }

    func handleBackground() {
        dispatch(.appBackgrounded)
    }

    func dispatch(_ event: CallEvent) {
        let (next, effects) = CallReducer.reduce(state, event)
        if next.phase != state.phase {
            Log.call.info("\(String(describing: event), privacy: .public) → \(String(describing: next.phase), privacy: .public)")
        }
        state = next
        for effect in effects { perform(effect) }
    }

    func refreshTranscript() {
        guard let endpoint = settings.endpoint else { return }
        transcriptTask?.cancel()
        let sessionID = settings.sessionID
        let assistantID = settings.trimmedAssistantID
        let agentspaceID = settings.agentspaceID
        let client = transcriptClient
        transcriptTask = Task { [weak self] in
            guard let self else { return }
            self.isLoadingTranscript = true
            defer { self.isLoadingTranscript = false }
            do {
                let token = try await self.auth.validAccessToken()
                guard !Task.isCancelled else { return }
                let messages = try await client.fetch(
                    endpoint: endpoint, token: token, sessionID: sessionID,
                    assistantID: assistantID, agentspaceID: agentspaceID
                )
                guard !Task.isCancelled else { return }
                self.transcript = messages
                self.transcriptError = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.transcriptError = error.localizedDescription
            }
        }
    }

    // MARK: - Effects

    private func perform(_ effect: CallEffect) {
        switch effect {
        case .startAudio:
            startAudio()
        case .stopAudio:
            callStartedAt = nil
            micOpen = false
            Task { await audio.stop() }
        case .openSocket:
            openSocket()
        case .closeSocket:
            closeSocket()
        case .sendStop:
            sendStop()
        case .micGate(let open):
            micOpen = open
            if open {
                vad.reset()
                bargeVAD.reset()
            }
        case .resetVAD:
            vad.reset()
            bargeVAD.reset()
        case .playbackEnqueue:
            enqueueRequested = true
        case .playbackFlush:
            Task { await audio.flushPlayback() }
        case .startThinkingWatchdog:
            startThinkingWatchdog()
        case .cancelThinkingWatchdog:
            thinkingWatchdog?.cancel()
            thinkingWatchdog = nil
        case .startMaxHoldTimer:
            startMaxHoldTimer()
        case .cancelMaxHoldTimer:
            maxHoldTimer?.cancel()
            maxHoldTimer = nil
        case .fetchTranscript:
            refreshTranscript()
        }
    }

    private func startAudio() {
        if callStartedAt == nil { callStartedAt = .now }
        vad = LocalVAD(params: settings.vadParams)
        bargeVAD = LocalVAD(params: settings.bargeInParams)
        audioStartTask?.cancel()
        audioStartTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.audio.start()
                self.echoCancellationActive = await self.audio.voiceProcessingEnabled
            } catch {
                guard !Task.isCancelled else { return }
                self.dispatch(.audioFailed(error.localizedDescription))
            }
        }
    }

    private func openSocket() {
        guard let endpoint = settings.endpoint else {
            dispatch(.socketFailed(L10n.Errors.invalidURL))
            return
        }
        let url = endpoint.liveURL(
            assistantID: settings.trimmedAssistantID,
            channelID: settings.channelID,
            agentspaceID: settings.agentspaceID,
            sessionID: settings.sessionID
        )
        connectionGeneration += 1
        let generation = connectionGeneration
        connectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Always connect with a token that is still valid (Keycloak access tokens last minutes).
                let token = try await self.auth.validAccessToken()
                guard generation == self.connectionGeneration else { return }
                let connection = LiveConnection(request: RuntimeRequests.live(url: url, token: token))
                self.connection = connection
                try await connection.connect()
                guard generation == self.connectionGeneration else {
                    await connection.close()
                    return
                }
                self.dispatch(.socketOpened)
                for try await event in connection.events {
                    guard generation == self.connectionGeneration else { break }
                    await self.handle(event)
                }
            } catch {
                guard generation == self.connectionGeneration else { return }
                self.dispatch(.socketFailed(error.localizedDescription))
            }
        }
    }

    private func closeSocket() {
        connectionGeneration += 1
        guard let connection else { return }
        self.connection = nil
        Task { await connection.close() }
    }

    private func sendStop() {
        guard let connection else { return }
        let audio = audio
        Task {
            if let tail = await audio.flushCapture(), !tail.isEmpty {
                await connection.sendAudio(tail)
            }
            await connection.sendStop()
        }
    }

    private func startThinkingWatchdog() {
        thinkingWatchdog?.cancel()
        thinkingWatchdog = Task { [weak self, thinkingTimeout] in
            try? await Task.sleep(for: thinkingTimeout)
            guard !Task.isCancelled else { return }
            self?.dispatch(.thinkingTimeout)
        }
    }

    private func startMaxHoldTimer() {
        maxHoldTimer?.cancel()
        maxHoldTimer = Task { [weak self, maxHold] in
            try? await Task.sleep(for: maxHold)
            guard !Task.isCancelled else { return }
            self?.dispatch(.maxHoldElapsed)
        }
    }

    private func syncModeIfIdle() {
        if !state.isActive, state.mode != settings.mode {
            state = CallState(mode: settings.mode)
        }
    }

    // MARK: - Stream consumers

    private func startConsumers() {
        captureTask = Task { [weak self] in
            guard let self else { return }
            for await samples in self.audio.capture {
                await self.handleCapture(samples)
            }
        }
        playbackTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.audio.playbackEvents {
                switch event {
                case .started: break
                case .drained: self.dispatch(.playbackDrained)
                }
            }
        }
        noticesTask = Task { [weak self] in
            guard let self else { return }
            for await notice in self.audio.notices {
                switch notice {
                case .interruptionBegan: self.dispatch(.interruptionBegan)
                case .interruptionEnded, .configurationChanged: break
                case .mediaServicesReset: self.dispatch(.audioFailed(L10n.Errors.mediaReset))
                case .failed(let message): self.dispatch(.audioFailed(message))
                }
            }
        }
    }

    private func handleCapture(_ samples: [Int16]) async {
        let rms = PCM.rms(samples)
        inputLevel = meter.update(rms: rms)
        inputDBFS = meter.dbfs

        if state.phase == .speaking, settings.localBargeIn, echoCancellationActive, !isMuted {
            for event in bargeVAD.consume(samples) where event == .speechStarted {
                dispatch(.localBargeIn)
            }
            return
        }

        guard micOpen, !isMuted, state.allowsSending, let connection else { return }
        for event in vad.consume(samples) {
            switch event {
            case .speechStarted: dispatch(.localSpeechStarted)
            case .turnEnded: dispatch(.localTurnEnded)
            case .turnDiscarded: dispatch(.localTurnDiscarded)
            }
        }
        guard micOpen, state.allowsSending else { return }
        await connection.sendAudio(samples)
    }

    private func handle(_ event: LiveEvent) async {
        switch event {
        case .audio(let samples):
            enqueueRequested = false
            dispatch(.audioFrame)
            if enqueueRequested {
                await audio.enqueuePlayback(samples)
            }
        case .clear:
            dispatch(.clearReceived)
        case .unknown(let name):
            Log.net.info("unknown live event: \(name, privacy: .public)")
        case .closed(let code, let reason):
            dispatch(.socketClosed(code: code, reason: reason))
        }
    }
}
