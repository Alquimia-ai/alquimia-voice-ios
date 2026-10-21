import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var showToken = false
    @State private var testing = false
    @State private var testMessage: String?
    @State private var testFailed = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                    section(L10n.Settings.runtimeSection, number: "01") {
                        field(L10n.Settings.runtimeURL) {
                            TextField(L10n.Settings.runtimePlaceholder, text: $settings.runtimeURL)
                                .keyboardType(.URL)
                                .textContentType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .inputField()
                        }
                        field(L10n.Settings.token) {
                            HStack(spacing: Theme.Space.sm) {
                                Group {
                                    if showToken {
                                        TextField(L10n.Settings.tokenPlaceholder, text: $settings.token)
                                    } else {
                                        SecureField(L10n.Settings.tokenPlaceholder, text: $settings.token)
                                    }
                                }
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .inputField()
                                Button(showToken ? L10n.Actions.hide : L10n.Actions.show) { showToken.toggle() }
                                    .buttonStyle(OutlineButtonStyle())
                            }
                        }
                        HStack(spacing: Theme.Space.md) {
                            Button(testing ? L10n.Settings.testing : L10n.Actions.testConnection) { runTest() }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(testing || !settings.isConfigured)
                            if let testMessage {
                                Text(testMessage)
                                    .font(Theme.Typography.bodySm)
                                    .foregroundStyle(testFailed ? Theme.Palette.error : Theme.Palette.muted)
                            }
                        }
                        if let validation = settings.validationMessage {
                            Text(validation)
                                .font(Theme.Typography.bodySm)
                                .foregroundStyle(Theme.Palette.ember)
                        }
                    }

                    section(L10n.Settings.agentSection, number: "02") {
                        field(L10n.Settings.assistantID) {
                            TextField(L10n.Settings.assistantPlaceholder, text: $settings.assistantID)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .inputField()
                        }
                        HStack(spacing: Theme.Space.md) {
                            field(L10n.Settings.agentspaceID) {
                                TextField("default", text: $settings.agentspaceID)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .inputField()
                            }
                            field(L10n.Settings.channelID) {
                                TextField("ios", text: $settings.channelID)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .inputField()
                            }
                        }
                    }

                    section(L10n.Settings.voiceSection, number: "03") {
                        field(L10n.Settings.mode) {
                            HStack(spacing: Theme.Space.sm) {
                                Button(L10n.Settings.handsFree) { settings.mode = .handsFree }
                                    .buttonStyle(ChipButtonStyle(active: settings.mode == .handsFree))
                                Button(L10n.Settings.pushToTalk) { settings.mode = .pushToTalk }
                                    .buttonStyle(ChipButtonStyle(active: settings.mode == .pushToTalk))
                            }
                        }
                        Toggle(isOn: $settings.localBargeIn) {
                            Text(L10n.Settings.localBargeIn)
                                .font(Theme.Typography.bodyMd)
                                .foregroundStyle(Theme.Palette.ink)
                        }
                        .tint(Theme.Palette.ember)
                        Text(L10n.Settings.localBargeInHelp)
                            .font(Theme.Typography.bodySm)
                            .foregroundStyle(Theme.Palette.muted)
                    }

                    section(L10n.Settings.debugSection, number: "04") {
                        field("\(L10n.Settings.activation) · \(Int(settings.activationDBFS)) dBFS") {
                            Slider(value: $settings.activationDBFS, in: -55 ... -25, step: 1)
                                .tint(Theme.Palette.ember)
                        }
                        Text(L10n.Settings.activationHelp)
                            .font(Theme.Typography.bodySm)
                            .foregroundStyle(Theme.Palette.muted)
                    }
                }
                .padding(Theme.Space.xl)
                .padding(.bottom, Theme.Space.xxxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.Palette.canvas.ignoresSafeArea())
            .navigationTitle(L10n.Settings.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Actions.done) { dismiss() }
                        .disabled(!settings.isConfigured)
                }
            }
        }
        .interactiveDismissDisabled(!settings.isConfigured)
    }

    private func runTest() {
        testing = true
        testMessage = nil
        Task {
            let result = await settings.testConnection()
            switch result {
            case .success:
                testMessage = L10n.Settings.testOK
                testFailed = false
            case .failure(let error):
                testMessage = String(format: L10n.Settings.testFailed, error.localizedDescription)
                testFailed = true
            }
            testing = false
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, number: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            HStack(spacing: Theme.Space.sm) {
                Text(number)
                    .font(Theme.Typography.monoLabel)
                    .foregroundStyle(Theme.Palette.ember)
                EyebrowLabel(title)
            }
            content()
        }
        .padding(.top, Theme.Space.lg)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs + 2) {
            Text(label)
                .font(Theme.Typography.labelMd)
                .foregroundStyle(Theme.Palette.body)
            content()
        }
    }
}

private struct InputFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Typography.bodyMd)
            .foregroundStyle(Theme.Palette.ink)
            .padding(.horizontal, Theme.Space.md)
            .frame(height: 36)
            .background(Theme.Palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .hairline(Theme.Radius.control)
    }
}

private extension View {
    func inputField() -> some View { modifier(InputFieldModifier()) }
}
