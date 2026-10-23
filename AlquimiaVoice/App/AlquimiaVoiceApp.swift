import SwiftUI

@main
struct AlquimiaVoiceApp: App {
    @State private var settings: SettingsStore
    @State private var auth: AuthManager
    @State private var session: CallSession

    init() {
        let settings = SettingsStore()
        let auth = AuthManager(settings: settings)
        _settings = State(initialValue: settings)
        _auth = State(initialValue: auth)
        _session = State(initialValue: CallSession(settings: settings, auth: auth, audio: AudioEngineController()))
        Log.ui.info("fonts: geist=\(Theme.Typography.geistAvailable) mono=\(Theme.Typography.monoAvailable)")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(auth)
                .environment(session)
                .tint(Theme.Palette.ember)
        }
    }
}
