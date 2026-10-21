import Foundation

enum LiveError: Error, Equatable, LocalizedError, Sendable {
    case invalidConfiguration
    case unauthorized(status: Int)
    case handshakeFailed(status: Int?, message: String)
    case transport(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return L10n.Errors.invalidURL
        case .unauthorized(let status):
            return String(format: L10n.Errors.unauthorized, status)
        case .handshakeFailed(let status, let message):
            let detail = status.map { " (HTTP \($0))" } ?? (message.isEmpty ? "" : " (\(message))")
            return String(format: L10n.Errors.handshake, detail)
        case .transport(let message):
            return String(format: L10n.Errors.transport, message)
        case .notConnected:
            return L10n.Errors.notConnected
        }
    }
}
