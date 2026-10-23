import Foundation
import Observation

/// Owns the Keycloak session: device-flow sign-in, Keychain persistence and single-flight refresh.
/// `validAccessToken()` is what every runtime call uses; it falls back to the static token from settings.
@MainActor
@Observable
final class AuthManager {
    enum SignInState: Equatable {
        case idle
        case waitingForApproval(DeviceAuthorization)
        case failed(String)
    }

    private(set) var tokens: TokenSet?
    private(set) var signInState: SignInState = .idle

    private let settings: SettingsStore
    private let keychain: Keychain
    private let transport: KeycloakClient.Transport?
    private var refreshTask: Task<TokenSet, any Error>?
    private var signInTask: Task<Void, Never>?

    private static let tokenAccount = "tokenSet"

    init(
        settings: SettingsStore,
        keychain: Keychain = Keychain(service: "ai.alquimia.voice"),
        transport: KeycloakClient.Transport? = nil
    ) {
        self.settings = settings
        self.keychain = keychain
        self.transport = transport
        tokens = Self.load(from: keychain)
        #if DEBUG
        applyEnvironmentOverrides()
        #endif
    }

    var isSignedIn: Bool { tokens != nil }
    var username: String? { tokens?.claims?.preferredUsername }
    var accessTokenExpiry: Date? { tokens?.expiresAt }

    /// A bearer token that is valid for at least a few more seconds: the Keycloak access token
    /// (refreshed if needed) or, when not signed in, the static token from settings.
    func validAccessToken() async throws -> String {
        if let tokens, tokens.isAccessTokenValid() { return tokens.accessToken }
        if let tokens {
            guard tokens.canRefresh() else {
                signOut(reason: KeycloakError.sessionExpired)
                throw KeycloakError.sessionExpired
            }
            if refreshTask == nil {
                let client = try makeClient()
                refreshTask = Task { try await client.refresh(tokens) }
            }
            let task = refreshTask!
            defer { if refreshTask == task { refreshTask = nil } }
            do {
                let refreshed = try await task.value
                store(refreshed)
                Log.net.info("access token refreshed; valid until \(refreshed.expiresAt, privacy: .public)")
                return refreshed.accessToken
            } catch KeycloakError.sessionExpired {
                signOut(reason: KeycloakError.sessionExpired)
                throw KeycloakError.sessionExpired
            }
        }
        let staticToken = settings.trimmedToken
        guard !staticToken.isEmpty else { throw KeycloakError.notSignedIn }
        return staticToken
    }

    func beginSignIn() {
        signInTask?.cancel()
        signInState = .idle
        signInTask = Task { [weak self] in
            guard let self else { return }
            do {
                let client = try self.makeClient()
                let authorization = try await client.startDeviceAuthorization()
                self.signInState = .waitingForApproval(authorization)
                let tokens = try await client.waitForDeviceToken(authorization)
                self.store(tokens)
                self.signInState = .idle
                Log.net.info("signed in as \(tokens.claims?.preferredUsername ?? "?", privacy: .public)")
            } catch is CancellationError {
                self.signInState = .idle
            } catch {
                self.signInState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        signInState = .idle
    }

    func signOut(reason: (any Error)? = nil) {
        tokens = nil
        try? keychain.set(nil, for: Self.tokenAccount)
        if let reason { signInState = .failed(reason.localizedDescription) }
    }

    // MARK: - Internals

    private func makeClient() throws -> KeycloakClient {
        guard let realmURL = KeycloakClient.realmURL(from: settings.realmURL) else { throw KeycloakError.invalidRealmURL }
        return KeycloakClient(realmURL: realmURL, clientID: settings.trimmedClientID, transport: transport)
    }

    private func store(_ tokens: TokenSet) {
        self.tokens = tokens
        if let data = try? JSONEncoder().encode(tokens), let json = String(data: data, encoding: .utf8) {
            try? keychain.set(json, for: Self.tokenAccount)
        }
    }

    private static func load(from keychain: Keychain) -> TokenSet? {
        guard let json = keychain.string(for: tokenAccount), let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TokenSet.self, from: data)
    }

    #if DEBUG
    /// `ALQUIMIA_REFRESH_TOKEN` (optionally with `ALQUIMIA_TOKEN`) seeds a session that refreshes on first use.
    private func applyEnvironmentOverrides() {
        let env = ProcessInfo.processInfo.environment
        guard let refresh = env["ALQUIMIA_REFRESH_TOKEN"], !refresh.isEmpty else { return }
        store(TokenSet(accessToken: env["ALQUIMIA_TOKEN"] ?? "", refreshToken: refresh, expiresAt: .distantPast, refreshExpiresAt: nil, scope: nil))
    }
    #endif
}
