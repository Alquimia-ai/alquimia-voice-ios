import Foundation

enum TranscriptError: Error, Equatable, LocalizedError {
    case badResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse: return L10n.Errors.badResponse
        case .http(let status): return String(format: L10n.Errors.http, status)
        }
    }
}

/// Fetches the chat history for the current session after each turn (the live socket carries audio only).
struct TranscriptClient: Sendable {
    var session: URLSession = .shared

    func fetch(
        endpoint: RuntimeEndpoint,
        token: String,
        sessionID: String,
        assistantID: String,
        agentspaceID: String
    ) async throws -> [TranscriptMessage] {
        let request = RuntimeRequests.contextRetrieve(
            endpoint: endpoint, token: token, sessionID: sessionID, assistantID: assistantID, agentspaceID: agentspaceID
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranscriptError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw TranscriptError.http(http.statusCode) }
        return try TranscriptParser.messages(from: data)
    }
}
