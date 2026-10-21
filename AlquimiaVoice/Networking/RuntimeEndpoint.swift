import Foundation

/// Builds the URLs the app needs from the configured runtime base URL (`http://host:8080` or `https://host/prefix`).
struct RuntimeEndpoint: Equatable, Hashable, Sendable {
    let baseURL: URL

    init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }
        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        components.percentEncodedPath = path
        guard let url = components.url else { return nil }
        baseURL = url
    }

    var isSecure: Bool { baseURL.scheme == "https" }
    var socketScheme: String { isSecure ? "wss" : "ws" }

    /// `ws(s)://host/live/{assistant_id}/{channel_id}?agentspace_id=…&session_id=…`
    /// `assistantID` may contain `/` for versioned references (`space/agent:0.0.1`); those slashes are preserved.
    func liveURL(assistantID: String, channelID: String, agentspaceID: String, sessionID: String) -> URL {
        var components = urlComponents()
        components.scheme = socketScheme
        let assistantPath = assistantID
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { Self.encodeSegment(String($0)) }
            .joined(separator: "/")
        components.percentEncodedPath += "/live/" + assistantPath + "/" + Self.encodeSegment(channelID)
        components.queryItems = [
            URLQueryItem(name: "agentspace_id", value: agentspaceID),
            URLQueryItem(name: "session_id", value: sessionID),
        ]
        return components.url ?? baseURL
    }

    /// `GET /context/retrieve?limit=…&offset=…`
    func contextRetrieveURL(limit: Int = 0, offset: Int = -1) -> URL {
        var components = urlComponents()
        components.percentEncodedPath += "/context/retrieve"
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        return components.url ?? baseURL
    }

    private func urlComponents() -> URLComponents {
        URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
    }

    private static let segmentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/")
        return set
    }()

    static func encodeSegment(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? segment
    }
}

enum RuntimeRequests {
    static func live(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// The runtime reads the ids from headers (`CommonAttributes` aliases `sessionid`, `assistantid`, `agentspaceid`).
    static func contextRetrieve(
        endpoint: RuntimeEndpoint,
        token: String,
        sessionID: String,
        assistantID: String,
        agentspaceID: String,
        limit: Int = 0,
        offset: Int = -1
    ) -> URLRequest {
        var request = URLRequest(url: endpoint.contextRetrieveURL(limit: limit, offset: offset))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(sessionID, forHTTPHeaderField: "sessionid")
        request.setValue(assistantID, forHTTPHeaderField: "assistantid")
        request.setValue(agentspaceID, forHTTPHeaderField: "agentspaceid")
        return request
    }
}
