import Foundation

/// Access + refresh token pair issued by Keycloak, stored in the Keychain as JSON.
struct TokenSet: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    /// `nil` for offline tokens, which do not expire with the session.
    var refreshExpiresAt: Date?
    var scope: String?

    func isAccessTokenValid(at date: Date = .now, leeway: TimeInterval = 30) -> Bool {
        expiresAt.timeIntervalSince(date) > leeway
    }

    func canRefresh(at date: Date = .now) -> Bool {
        guard let refreshToken, !refreshToken.isEmpty else { return false }
        if let refreshExpiresAt { return refreshExpiresAt > date }
        return true
    }

    var claims: JWTClaims? { JWTClaims(accessToken) }
}

/// The few JWT claims the app displays. Decoded without signature verification; the runtime verifies.
struct JWTClaims: Equatable, Sendable {
    var subject: String?
    var preferredUsername: String?
    var expiry: Date?

    init?(_ token: String) {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        subject = object["sub"] as? String
        preferredUsername = object["preferred_username"] as? String
        if let exp = object["exp"] as? TimeInterval { expiry = Date(timeIntervalSince1970: exp) }
    }
}

/// Response of the OAuth device authorization endpoint.
struct DeviceAuthorization: Codable, Equatable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURI: URL
    let verificationURIComplete: URL?
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case verificationURIComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }

    var pollInterval: Duration { .seconds(max(interval, 1)) }
}

enum KeycloakError: Error, Equatable, LocalizedError {
    case invalidRealmURL
    case badResponse
    case pending
    case slowDown
    case denied
    case expired
    case sessionExpired
    case notSignedIn
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidRealmURL: return L10n.Auth.invalidRealm
        case .badResponse: return L10n.Errors.badResponse
        case .pending, .slowDown: return L10n.Auth.waiting
        case .denied: return L10n.Auth.denied
        case .expired: return L10n.Auth.codeExpired
        case .sessionExpired: return L10n.Auth.sessionExpired
        case .notSignedIn: return L10n.Auth.notSignedIn
        case .server(let message): return message
        }
    }
}

/// OAuth 2.0 device authorization grant + refresh against a Keycloak realm, the same flow the Alquimia CLI uses.
struct KeycloakClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    var realmURL: URL
    var clientID: String
    var scope = "openid offline_access"
    var transport: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw KeycloakError.badResponse }
        return (data, http)
    }

    init(realmURL: URL, clientID: String, scope: String = "openid offline_access", transport: Transport? = nil) {
        self.realmURL = realmURL
        self.clientID = clientID
        self.scope = scope
        if let transport { self.transport = transport }
    }

    static func realmURL(from string: String) -> URL? {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed), let scheme = url.scheme, scheme == "https" || scheme == "http",
              url.host() != nil else { return nil }
        return url
    }

    var deviceEndpoint: URL { realmURL.appending(path: "protocol/openid-connect/auth/device") }
    var tokenEndpoint: URL { realmURL.appending(path: "protocol/openid-connect/token") }

    func startDeviceAuthorization() async throws -> DeviceAuthorization {
        let (data, response) = try await post(deviceEndpoint, ["client_id": clientID, "scope": scope])
        guard response.statusCode == 200 else { throw Self.serverError(data, response) }
        do {
            return try JSONDecoder().decode(DeviceAuthorization.self, from: data)
        } catch {
            throw KeycloakError.badResponse
        }
    }

    /// One poll of the token endpoint; throws `.pending` or `.slowDown` while the user has not approved yet.
    func pollDeviceToken(_ authorization: DeviceAuthorization, now: Date = .now) async throws -> TokenSet {
        let (data, response) = try await post(tokenEndpoint, [
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "client_id": clientID,
            "device_code": authorization.deviceCode,
        ])
        return try Self.tokenSet(from: data, response: response, now: now)
    }

    /// Polls until the user approves, the code expires or the request is denied.
    func waitForDeviceToken(_ authorization: DeviceAuthorization) async throws -> TokenSet {
        let deadline = ContinuousClock.now + .seconds(authorization.expiresIn)
        var interval = authorization.pollInterval
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: interval)
            do {
                return try await pollDeviceToken(authorization)
            } catch KeycloakError.pending {
                continue
            } catch KeycloakError.slowDown {
                interval += .seconds(5)
                continue
            }
        }
        throw KeycloakError.expired
    }

    func refresh(_ tokens: TokenSet, now: Date = .now) async throws -> TokenSet {
        guard let refreshToken = tokens.refreshToken, !refreshToken.isEmpty else { throw KeycloakError.sessionExpired }
        let (data, response) = try await post(tokenEndpoint, [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken,
        ])
        do {
            return try Self.tokenSet(from: data, response: response, now: now)
        } catch KeycloakError.server(let message) where message.contains("invalid_grant") {
            throw KeycloakError.sessionExpired
        }
    }

    // MARK: - Internals

    private func post(_ url: URL, _ fields: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.form(fields)
        return try await transport(request)
    }

    static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.keys.sorted().map { key in
            let value = fields[key]!.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(key)=\(value)"
        }.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    static func tokenSet(from data: Data, response: HTTPURLResponse, now: Date) throws -> TokenSet {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let error = object["error"] as? String {
            switch error {
            case "authorization_pending": throw KeycloakError.pending
            case "slow_down": throw KeycloakError.slowDown
            case "access_denied": throw KeycloakError.denied
            case "expired_token": throw KeycloakError.expired
            default:
                let description = object["error_description"] as? String ?? ""
                throw KeycloakError.server("\(error): \(description)")
            }
        }
        guard response.statusCode == 200, let accessToken = object["access_token"] as? String else {
            throw serverError(data, response)
        }
        let expiresIn = (object["expires_in"] as? TimeInterval) ?? 300
        let refreshExpiresIn = object["refresh_expires_in"] as? TimeInterval
        return TokenSet(
            accessToken: accessToken,
            refreshToken: object["refresh_token"] as? String,
            expiresAt: now.addingTimeInterval(expiresIn),
            refreshExpiresAt: (refreshExpiresIn ?? 0) > 0 ? now.addingTimeInterval(refreshExpiresIn!) : nil,
            scope: object["scope"] as? String
        )
    }

    private static func serverError(_ data: Data, _ response: HTTPURLResponse) -> KeycloakError {
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .server("HTTP \(response.statusCode)\(text.isEmpty ? "" : ": \(text.prefix(160))")")
    }
}
