import SwiftUI

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(CallSession.self) private var session
    @Environment(AuthManager.self) private var auth
    @State private var showSettings = false

    var body: some View {
        CallView(showSettings: $showSettings)
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onAppear {
                if !settings.isConfigured(signedIn: auth.isSignedIn) { showSettings = true }
            }
            #if DEBUG
            .task {
                // Simulator automation only: `ALQUIMIA_AUTOSTART=1` starts a hands-free call on launch;
                // `ALQUIMIA_AUTOPTT_SECONDS=<n>` presses the hold-to-talk control, holds it n seconds and releases it.
                let environment = ProcessInfo.processInfo.environment
                guard settings.isConfigured(signedIn: auth.isSignedIn) else { return }
                if environment["ALQUIMIA_AUTOSTART"] == "1" {
                    session.startCall()
                }
                if let hold = environment["ALQUIMIA_AUTOPTT_SECONDS"].flatMap(Double.init), hold > 0 {
                    try? await Task.sleep(for: .seconds(1))
                    session.pressPTT()
                    try? await Task.sleep(for: .seconds(hold))
                    session.releasePTT()
                }
            }
            #endif
    }
}
