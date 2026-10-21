import Foundation
import Observation

/// Persisted configuration. The token lives in the Keychain; everything else in `UserDefaults`.
@MainActor
@Observable
final class SettingsStore {
    private enum Keys {
        static let runtimeURL = "runtimeURL"
        static let assistantID = "assistantID"
        static let agentspaceID = "agentspaceID"
        static let channelID = "channelID"
        static let mode = "voiceMode"
        static let localBargeIn = "localBargeIn"
        static let sessionID = "sessionID"
        static let activationDBFS = "vadActivationDBFS"
    }

    private static let tokenAccount = "apiToken"

    private let defaults: UserDefaults
    private let keychain: Keychain

    var runtimeURL: String { didSet { defaults.set(runtimeURL, forKey: Keys.runtimeURL) } }
    var token: String { didSet { try? keychain.set(token, for: Self.tokenAccount) } }
    var assistantID: String { didSet { defaults.set(assistantID, forKey: Keys.assistantID) } }
    var agentspaceID: String { didSet { defaults.set(agentspaceID, forKey: Keys.agentspaceID) } }
    var channelID: String { didSet { defaults.set(channelID, forKey: Keys.channelID) } }
    var mode: VoiceMode { didSet { defaults.set(mode.rawValue, forKey: Keys.mode) } }
    var localBargeIn: Bool { didSet { defaults.set(localBargeIn, forKey: Keys.localBargeIn) } }
    private(set) var sessionID: String { didSet { defaults.set(sessionID, forKey: Keys.sessionID) } }
    /// Local VAD activation threshold in dBFS (the server uses −40 dBFS). UI only.
    var activationDBFS: Double { didSet { defaults.set(activationDBFS, forKey: Keys.activationDBFS) } }

    init(defaults: UserDefaults = .standard, keychain: Keychain = Keychain(service: "ai.alquimia.voice")) {
        self.defaults = defaults
        self.keychain = keychain
        runtimeURL = defaults.string(forKey: Keys.runtimeURL) ?? ""
        token = keychain.string(for: Self.tokenAccount) ?? ""
        assistantID = defaults.string(forKey: Keys.assistantID) ?? ""
        agentspaceID = defaults.string(forKey: Keys.agentspaceID) ?? "default"
        channelID = defaults.string(forKey: Keys.channelID) ?? Self.makeChannelID()
        mode = VoiceMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .handsFree
        localBargeIn = defaults.object(forKey: Keys.localBargeIn) as? Bool ?? true
        sessionID = defaults.string(forKey: Keys.sessionID) ?? SessionID.make()
        activationDBFS = defaults.object(forKey: Keys.activationDBFS) as? Double ?? Double(LevelMeter.serverThresholdDBFS)
        defaults.set(channelID, forKey: Keys.channelID)
        defaults.set(sessionID, forKey: Keys.sessionID)
        #if DEBUG
        applyEnvironmentOverrides()
        #endif
    }

    #if DEBUG
    /// Debug builds accept `ALQUIMIA_RUNTIME_URL`, `ALQUIMIA_TOKEN`, `ALQUIMIA_ASSISTANT_ID`,
    /// `ALQUIMIA_AGENTSPACE_ID` and `ALQUIMIA_MODE` (handsFree | pushToTalk) so a simulator can be
    /// launched pre-configured: `SIMCTL_CHILD_ALQUIMIA_TOKEN=dev xcrun simctl launch booted ai.alquimia.voice`.
    private func applyEnvironmentOverrides() {
        let env = ProcessInfo.processInfo.environment
        if let value = env["ALQUIMIA_RUNTIME_URL"], !value.isEmpty { runtimeURL = value }
        if let value = env["ALQUIMIA_TOKEN"], !value.isEmpty { token = value }
        if let value = env["ALQUIMIA_ASSISTANT_ID"], !value.isEmpty { assistantID = value }
        if let value = env["ALQUIMIA_AGENTSPACE_ID"], !value.isEmpty { agentspaceID = value }
        if let value = env["ALQUIMIA_MODE"], let parsed = VoiceMode(rawValue: value) { mode = parsed }
    }
    #endif

    // MARK: - Derived

    var endpoint: RuntimeEndpoint? { RuntimeEndpoint(string: runtimeURL) }
    var trimmedAssistantID: String { assistantID.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }

    var validationMessage: String? {
        if endpoint == nil { return L10n.Settings.invalidURL }
        if trimmedToken.isEmpty { return L10n.Settings.missingToken }
        if trimmedAssistantID.isEmpty { return L10n.Settings.missingAssistant }
        return nil
    }

    var isConfigured: Bool { validationMessage == nil }

    var vadParams: LocalVAD.Params {
        var params = LocalVAD.Params()
        params.activation = Float(pow(10, activationDBFS / 20))
        return params
    }

    /// Stricter threshold for interrupting a reply, to avoid false triggers from residual echo.
    var bargeInParams: LocalVAD.Params {
        var params = vadParams
        params.activation *= 3
        params.minSpeechMs = 150
        return params
    }

    func newSession() {
        sessionID = SessionID.make()
    }

    /// Validates URL + token against the runtime by fetching the (possibly empty) history of the current session.
    func testConnection(using client: TranscriptClient = TranscriptClient()) async -> Result<Int, any Error> {
        guard let endpoint else { return .failure(LiveError.invalidConfiguration) }
        do {
            let messages = try await client.fetch(
                endpoint: endpoint, token: trimmedToken, sessionID: sessionID,
                assistantID: trimmedAssistantID, agentspaceID: agentspaceID
            )
            return .success(messages.count)
        } catch {
            return .failure(error)
        }
    }

    private static func makeChannelID() -> String {
        "ios-" + String(UUID().uuidString.lowercased().prefix(8))
    }
}
