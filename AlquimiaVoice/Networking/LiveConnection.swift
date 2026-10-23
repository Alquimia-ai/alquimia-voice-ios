import Foundation

/// One WebSocket to `/live/{assistant_id}/{channel_id}`. Create a new instance per socket.
///
/// Hands-free mode keeps one connection for the whole call; push-to-talk opens one per turn.
/// Only the completion-handler flavours of `URLSessionWebSocketTask` are used so the non-Sendable
/// task never crosses an isolation boundary.
actor LiveConnection {
    nonisolated let events: AsyncThrowingStream<LiveEvent, any Error>

    private let request: URLRequest
    private let pingInterval: Duration
    private var continuation: AsyncThrowingStream<LiveEvent, any Error>.Continuation?
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var delegate: SocketDelegate?
    private var openContinuation: CheckedContinuation<Void, any Error>?
    private var closeInfo: (code: Int, reason: String?)?
    private var closedLocally = false
    private var finished = false
    private var pingTask: Task<Void, Never>?
    private(set) var isOpen = false

    init(request: URLRequest, pingInterval: Duration = .seconds(20)) {
        self.request = request
        self.pingInterval = pingInterval
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: LiveEvent.self, throwing: (any Error).self, bufferingPolicy: .unbounded
        )
        self.events = stream
        self.continuation = continuation
    }

    /// Resolves once the handshake completes; throws `LiveError.unauthorized` on 401/403.
    func connect() async throws {
        guard task == nil, !finished else { return }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300
        configuration.waitsForConnectivity = false
        let delegate = SocketDelegate(
            onOpen: { [weak self] in Task { await self?.handleOpen() } },
            onClose: { [weak self] code, reason in Task { await self?.handleClose(code: code, reason: reason) } },
            onComplete: { [weak self] status, error in Task { await self?.handleCompletion(status: status, error: error) } }
        )
        self.delegate = delegate
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: request)
        self.task = task
        Log.net.info("connecting to \(self.request.url?.absoluteString ?? "?", privacy: .public)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            openContinuation = continuation
            task.resume()
        }
        receiveNext()
        startPing()
    }

    func sendAudio(_ samples: [Int16]) {
        send(text: LiveWire.audioMessage(samples))
    }

    func sendStop() {
        Log.net.info("sending stop")
        send(text: LiveWire.stopMessage)
    }

    /// Closes with `goingAway` and ends the event stream without a `.closed` event.
    func close() {
        guard !finished else { return }
        closedLocally = true
        task?.cancel(with: .goingAway, reason: nil)
        finish(.cancelled)
    }

    // MARK: - Internals

    private enum Received: Sendable {
        case text(String)
        case binary(Int)
        case failure(any Error)
    }

    private enum Terminal {
        case closed(Int, String?)
        case failed(any Error)
        case cancelled
    }

    private func send(text: String) {
        guard isOpen, let task else { return }
        task.send(.string(text)) { error in
            if let error { Log.net.error("send failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    private func receiveNext() {
        guard let task, !finished else { return }
        task.receive { [weak self] result in
            let received: Received
            switch result {
            case .success(let message):
                switch message {
                case .string(let text): received = .text(text)
                case .data(let data): received = .binary(data.count)
                @unknown default: received = .binary(0)
                }
            case .failure(let error):
                received = .failure(error)
            }
            Task { await self?.handle(received) }
        }
    }

    private func handle(_ received: Received) async {
        guard !finished else { return }
        switch received {
        case .text(let text):
            if let event = LiveWire.decode(text) {
                continuation?.yield(event)
            } else {
                Log.net.debug("ignoring undecodable text frame")
            }
            receiveNext()
        case .binary(let count):
            Log.net.warning("ignoring binary frame (\(count) bytes)")
            receiveNext()
        case .failure(let error):
            await handleReceiveFailure(error)
        }
    }

    private func handleReceiveFailure(_ error: any Error) async {
        if closedLocally { finish(.cancelled); return }
        // The delegate's didClose may arrive a moment after receive() fails. Give it a beat.
        if closeInfo == nil, let task, task.closeCode == .invalid {
            try? await Task.sleep(for: .milliseconds(150))
        }
        if let info = closeInfo { finish(.closed(info.code, info.reason)); return }
        if let task, task.closeCode != .invalid {
            finish(.closed(task.closeCode.rawValue, Self.reasonString(task.closeReason)))
            return
        }
        // The socket was open and the peer dropped it without a close frame (the production runtime
        // ends a push-to-talk turn this way once the reply burst is sent). Report it as an abnormal
        // close (1006) so the call state machine finishes the turn instead of treating it as an error.
        Log.net.info("socket dropped without close frame: \(error.localizedDescription, privacy: .public)")
        finish(.closed(1006, nil))
    }

    private func handleOpen() {
        isOpen = true
        Log.net.info("socket open")
        openContinuation?.resume()
        openContinuation = nil
    }

    private func handleClose(code: Int, reason: String?) {
        Log.net.info("socket closed by peer: \(code) \(reason ?? "", privacy: .public)")
        closeInfo = (code, reason)
        isOpen = false
        finish(.closed(code, reason))
    }

    private func handleCompletion(status: Int?, error: (any Error)?) {
        if let openContinuation {
            self.openContinuation = nil
            let failure: LiveError
            if let status, status == 401 || status == 403 {
                failure = .unauthorized(status: status)
            } else {
                failure = .handshakeFailed(status: status, message: error?.localizedDescription ?? "")
            }
            Log.net.error("handshake failed: \(failure.localizedDescription, privacy: .public)")
            openContinuation.resume(throwing: failure)
            finish(.failed(failure))
            return
        }
        guard !finished else { return }
        if let info = closeInfo {
            finish(.closed(info.code, info.reason))
        } else if closedLocally {
            finish(.cancelled)
        } else if let error {
            // Same as the receive path: once open, a dropped connection is an abnormal close, not a failure.
            Log.net.info("socket completed with error after open: \(error.localizedDescription, privacy: .public)")
            finish(.closed(1006, nil))
        }
    }

    private func finish(_ terminal: Terminal) {
        guard !finished else { return }
        finished = true
        isOpen = false
        pingTask?.cancel()
        pingTask = nil
        if let openContinuation {
            self.openContinuation = nil
            openContinuation.resume(throwing: LiveError.notConnected)
        }
        if let continuation {
            switch terminal {
            case .closed(let code, let reason):
                continuation.yield(.closed(code: code, reason: reason))
                continuation.finish()
            case .failed(let error):
                continuation.finish(throwing: error)
            case .cancelled:
                continuation.finish()
            }
            self.continuation = nil
        }
        if let session {
            if closedLocally {
                // Give the goingAway close frame a moment to be written before tearing the session down.
                Task.detached {
                    try? await Task.sleep(for: .milliseconds(300))
                    session.invalidateAndCancel()
                }
            } else {
                session.invalidateAndCancel()
            }
        }
        session = nil
        task = nil
    }

    private func startPing() {
        pingTask = Task { [weak self, pingInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pingInterval)
                guard !Task.isCancelled else { return }
                await self?.ping()
            }
        }
    }

    private func ping() {
        guard isOpen, let task else { return }
        task.sendPing { error in
            if let error { Log.net.debug("ping failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    private static func reasonString(_ data: Data?) -> String? {
        guard let data, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }
}

private final class SocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    let onOpen: @Sendable () -> Void
    let onClose: @Sendable (Int, String?) -> Void
    let onComplete: @Sendable (Int?, (any Error)?) -> Void

    init(
        onOpen: @escaping @Sendable () -> Void,
        onClose: @escaping @Sendable (Int, String?) -> Void,
        onComplete: @escaping @Sendable (Int?, (any Error)?) -> Void
    ) {
        self.onOpen = onOpen
        self.onClose = onClose
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        onOpen()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let text = reason.flatMap { String(data: $0, encoding: .utf8) }.flatMap { $0.isEmpty ? nil : $0 }
        onClose(closeCode.rawValue, text)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let status = (task.response as? HTTPURLResponse)?.statusCode
        onComplete(status, error)
    }
}
