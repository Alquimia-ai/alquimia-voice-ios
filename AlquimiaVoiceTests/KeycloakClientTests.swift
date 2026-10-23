import Foundation
import Testing
@testable import AlquimiaVoice

/// Records requests and answers from a script, so the OAuth flows can be tested without a server.
final class StubTransport: @unchecked Sendable {
    struct Call: Sendable {
        let url: URL
        let body: [String: String]
    }

    private let lock = NSLock()
    private var responses: [(Int, String)]
    private(set) var calls: [Call] = []

    init(_ responses: [(Int, String)]) {
        self.responses = responses
    }

    var transport: KeycloakClient.Transport {
        { [self] request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            let fields = Dictionary(uniqueKeysWithValues: body.split(separator: "&").map { pair -> (String, String) in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                return (parts[0], parts.count > 1 ? parts[1].removingPercentEncoding ?? parts[1] : "")
            })
            let (status, json): (Int, String) = self.lock.withLock {
                self.calls.append(Call(url: request.url!, body: fields))
                return self.responses.isEmpty ? (500, "{}") : self.responses.removeFirst()
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(json.utf8), response)
        }
    }
}

private let realm = URL(string: "https://auth.example.com/realms/production")!

private func fakeJWT(username: String, exp: TimeInterval) -> String {
    let header = Data("{\"alg\":\"none\"}".utf8).base64EncodedString()
    let payload = Data("{\"sub\":\"abc\",\"preferred_username\":\"\(username)\",\"exp\":\(Int(exp))}".utf8)
        .base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    return "\(header).\(payload).sig"
}

@Suite("Keycloak client")
struct KeycloakClientTests {
    @Test func deviceAuthorizationRequestAndResponse() async throws {
        let stub = StubTransport([(200, """
        {"device_code":"dev-1","user_code":"ABCD-EFGH","verification_uri":"https://auth.example.com/device",
         "verification_uri_complete":"https://auth.example.com/device?user_code=ABCD-EFGH","expires_in":600,"interval":5}
        """)])
        let client = KeycloakClient(realmURL: realm, clientID: "alquimia-cli", transport: stub.transport)
        let authorization = try await client.startDeviceAuthorization()
        #expect(authorization.userCode == "ABCD-EFGH")
        #expect(authorization.verificationURIComplete?.absoluteString.hasSuffix("user_code=ABCD-EFGH") == true)
        #expect(authorization.pollInterval == .seconds(5))
        let call = try #require(stub.calls.first)
        #expect(call.url.absoluteString == "https://auth.example.com/realms/production/protocol/openid-connect/auth/device")
        #expect(call.body["client_id"] == "alquimia-cli")
        #expect(call.body["scope"] == "openid offline_access")
    }

    @Test func pollingMapsOAuthErrors() async throws {
        let authorization = DeviceAuthorization(deviceCode: "dev-1", userCode: "X", verificationURI: realm, verificationURIComplete: nil, expiresIn: 600, interval: 5)
        for (error, expected) in [("authorization_pending", KeycloakError.pending), ("slow_down", .slowDown), ("access_denied", .denied), ("expired_token", .expired)] {
            let stub = StubTransport([(400, "{\"error\":\"\(error)\",\"error_description\":\"x\"}")])
            let client = KeycloakClient(realmURL: realm, clientID: "c", transport: stub.transport)
            await #expect(throws: expected) { try await client.pollDeviceToken(authorization) }
            #expect(stub.calls.first?.body["grant_type"] == "urn:ietf:params:oauth:grant-type:device_code")
            #expect(stub.calls.first?.body["device_code"] == "dev-1")
        }
    }

    @Test func successfulTokenResponseBecomesTokenSet() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let authorization = DeviceAuthorization(deviceCode: "dev-1", userCode: "X", verificationURI: realm, verificationURIComplete: nil, expiresIn: 600, interval: 5)
        let stub = StubTransport([(200, """
        {"access_token":"\(fakeJWT(username: "alex", exp: 1_700_000_300))","expires_in":300,"refresh_expires_in":0,
         "refresh_token":"rt-1","token_type":"Bearer","scope":"openid offline_access"}
        """)])
        let client = KeycloakClient(realmURL: realm, clientID: "c", transport: stub.transport)
        let tokens = try await client.pollDeviceToken(authorization, now: now)
        #expect(tokens.refreshToken == "rt-1")
        #expect(tokens.expiresAt == now.addingTimeInterval(300))
        #expect(tokens.refreshExpiresAt == nil, "offline tokens report refresh_expires_in 0")
        #expect(tokens.claims?.preferredUsername == "alex")
        #expect(tokens.isAccessTokenValid(at: now))
        #expect(!tokens.isAccessTokenValid(at: now.addingTimeInterval(280)), "30 s leeway")
        #expect(tokens.canRefresh(at: now.addingTimeInterval(1_000_000)))
    }

    @Test func refreshUsesRefreshTokenAndMapsInvalidGrant() async throws {
        let now = Date()
        let tokens = TokenSet(accessToken: "old", refreshToken: "rt-1", expiresAt: now, refreshExpiresAt: nil, scope: nil)
        let ok = StubTransport([(200, "{\"access_token\":\"new\",\"expires_in\":300,\"refresh_expires_in\":3600,\"refresh_token\":\"rt-2\"}")])
        let refreshed = try await KeycloakClient(realmURL: realm, clientID: "c", transport: ok.transport).refresh(tokens, now: now)
        #expect(refreshed.accessToken == "new")
        #expect(refreshed.refreshToken == "rt-2")
        #expect(refreshed.refreshExpiresAt == now.addingTimeInterval(3600))
        #expect(ok.calls.first?.body["grant_type"] == "refresh_token")
        #expect(ok.calls.first?.body["refresh_token"] == "rt-1")

        let expired = StubTransport([(400, "{\"error\":\"invalid_grant\",\"error_description\":\"Token is not active\"}")])
        await #expect(throws: KeycloakError.sessionExpired) {
            try await KeycloakClient(realmURL: realm, clientID: "c", transport: expired.transport).refresh(tokens, now: now)
        }
        let noRefresh = TokenSet(accessToken: "old", refreshToken: nil, expiresAt: now, refreshExpiresAt: nil, scope: nil)
        await #expect(throws: KeycloakError.sessionExpired) {
            try await KeycloakClient(realmURL: realm, clientID: "c", transport: ok.transport).refresh(noRefresh, now: now)
        }
    }

    @Test func formEncodingAndRealmNormalisation() {
        let body = String(data: KeycloakClient.form(["scope": "openid offline_access", "client_id": "a b&c"]), encoding: .utf8)
        #expect(body == "client_id=a%20b%26c&scope=openid%20offline_access")
        #expect(KeycloakClient.realmURL(from: " https://auth.example.com/realms/production/ ")?.absoluteString == "https://auth.example.com/realms/production")
        #expect(KeycloakClient.realmURL(from: "auth.example.com") == nil)
        let client = KeycloakClient(realmURL: realm, clientID: "c")
        #expect(client.tokenEndpoint.absoluteString == "https://auth.example.com/realms/production/protocol/openid-connect/token")
    }

    @Test func jwtClaims() {
        let claims = JWTClaims(fakeJWT(username: "alex@example.com", exp: 1_700_000_300))
        #expect(claims?.preferredUsername == "alex@example.com")
        #expect(claims?.subject == "abc")
        #expect(claims?.expiry == Date(timeIntervalSince1970: 1_700_000_300))
        #expect(JWTClaims("not-a-jwt") == nil)
    }
}

@Suite("Auth manager")
@MainActor
struct AuthManagerTests {
    private func makeSettings(token: String = "") -> SettingsStore {
        let suite = "test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsStore(defaults: defaults, keychain: Keychain(service: suite))
        settings.token = token
        return settings
    }

    @Test func staticTokenIsUsedWhenNotSignedIn() async throws {
        let settings = makeSettings(token: " static-token ")
        let auth = AuthManager(settings: settings, keychain: Keychain(service: "test." + UUID().uuidString))
        #expect(!auth.isSignedIn)
        #expect(try await auth.validAccessToken() == "static-token")
    }

    @Test func missingCredentialsThrow() async {
        let auth = AuthManager(settings: makeSettings(), keychain: Keychain(service: "test." + UUID().uuidString))
        await #expect(throws: KeycloakError.notSignedIn) { try await auth.validAccessToken() }
    }

    @Test func expiredAccessTokenIsRefreshedOnceForConcurrentCallers() async throws {
        let service = "test." + UUID().uuidString
        let keychain = Keychain(service: service)
        let expired = TokenSet(accessToken: "old", refreshToken: "rt-1", expiresAt: .distantPast, refreshExpiresAt: nil, scope: nil)
        try keychain.set(String(data: try JSONEncoder().encode(expired), encoding: .utf8), for: "tokenSet")
        let stub = StubTransport([(200, "{\"access_token\":\"new\",\"expires_in\":300,\"refresh_expires_in\":0,\"refresh_token\":\"rt-2\"}")])
        let auth = AuthManager(settings: makeSettings(), keychain: keychain, transport: stub.transport)
        #expect(auth.isSignedIn)

        async let first = auth.validAccessToken()
        async let second = auth.validAccessToken()
        let tokens = try await [first, second]
        #expect(tokens == ["new", "new"])
        #expect(stub.calls.count == 1, "single-flight refresh")
        #expect(try await auth.validAccessToken() == "new", "cached while valid")
        #expect(stub.calls.count == 1)

        let reloaded = AuthManager(settings: makeSettings(), keychain: keychain)
        #expect(reloaded.tokens?.refreshToken == "rt-2", "persisted in the keychain")
        try? keychain.set(nil, for: "tokenSet")
    }

    @Test func expiredSessionSignsOut() async throws {
        let service = "test." + UUID().uuidString
        let keychain = Keychain(service: service)
        let expired = TokenSet(accessToken: "old", refreshToken: "rt-1", expiresAt: .distantPast, refreshExpiresAt: nil, scope: nil)
        try keychain.set(String(data: try JSONEncoder().encode(expired), encoding: .utf8), for: "tokenSet")
        let stub = StubTransport([(400, "{\"error\":\"invalid_grant\"}")])
        let auth = AuthManager(settings: makeSettings(), keychain: keychain, transport: stub.transport)
        await #expect(throws: KeycloakError.sessionExpired) { try await auth.validAccessToken() }
        #expect(!auth.isSignedIn)
        #expect(auth.signInState == .failed(KeycloakError.sessionExpired.localizedDescription))
    }
}
