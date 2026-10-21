import SwiftUI

@main
struct AlquimiaVoiceApp: App {
    @State private var settings: SettingsStore
    @State private var session: CallSession

    init() {
        let settings = SettingsStore()
        _settings = State(initialValue: settings)
        _session = State(initialValue: CallSession(settings: settings, audio: AudioEngineController()))
        Log.ui.info("fonts: geist=\(Theme.Typography.geistAvailable) mono=\(Theme.Typography.monoAvailable)")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(session)
                .tint(Theme.Palette.ember)
        }
    }
}
