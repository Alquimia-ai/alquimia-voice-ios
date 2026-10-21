import SwiftUI

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(CallSession.self) private var session
    @State private var showSettings = false

    var body: some View {
        CallView(showSettings: $showSettings)
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onAppear {
                if !settings.isConfigured { showSettings = true }
            }
            #if DEBUG
            .task {
                // `ALQUIMIA_AUTOSTART=1` starts a call on launch (simulator automation only).
                guard ProcessInfo.processInfo.environment["ALQUIMIA_AUTOSTART"] == "1", settings.isConfigured else { return }
                session.startCall()
            }
            #endif
    }
}
