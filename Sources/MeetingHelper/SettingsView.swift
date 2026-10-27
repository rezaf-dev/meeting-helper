import SwiftUI
import MeetingCore

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: MeetingModel
    @Environment(\.dismiss) private var dismiss
    @ViewState private var enteredKey = ""
    @ViewState private var credentialMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("MeetingHelper settings").font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(24)
            Divider()
            Form {
                Section("English help") {
                    Picker("My English level", selection: $settings.englishLevel) {
                        ForEach(EnglishLevel.allCases) { level in Text(level.label).tag(level) }
                    }
                    Picker("Speaking support", selection: $settings.speakingStyle) {
                        ForEach(SpeakingStyle.allCases) { style in Text(style.label).tag(style) }
                    }
                    Text("Speaking hints gives useful words and a sentence pattern with blanks so you can speak in your own words. Choose Full replies for a complete suggested answer.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Picker("Answer length", selection: $settings.answerLength) {
                        ForEach(AnswerLength.allCases) { length in Text(length.label).tag(length) }
                    }
                    Toggle("Explain important things only", isOn: $settings.importantOnly)
                    Text("Intermediate assumes you understand everyday English. Brief keeps advice within about 35 words. Recaps can be longer. Applies to your next AI request, even when saved profile sharing is off.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("Example hint: ‘rough estimate’ = approximate amount. Pattern: “Before I estimate [work], I need [detail].”")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Section("Your profile") {
                    ProfileEditor(settings: settings)
                }
                Section("Local captions") {
                    Text("Microphone and system audio need separate permissions. Meeting audio uses an audio-only tap; screen video is never captured. If meeting captions are silent while other apps play audio, check System Audio Recording permission, then quit and reopen MeetingHelper.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Link("Open audio recording permissions", destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    Picker("English locale", selection: $settings.locale) {
                        Text("English (United States)").tag("en-US")
                        Text("English (United Kingdom)").tag("en-GB")
                        Text("English (Australia)").tag("en-AU")
                        Text("English (India)").tag("en-IN")
                    }.disabled(model.isRunning || model.isBusy)
                    HStack {
                        Text("Caption size")
                        Slider(value: $settings.fontSize, in: 16...34, step: 1)
                        Text("\(Int(settings.fontSize)) pt").monospacedDigit().frame(width: 40)
                    }
                    TextField("Names and vocabulary (comma separated)", text: $settings.vocabulary)
                        .disabled(model.isRunning || model.isBusy)
                    Toggle("Prefer caption speed over accuracy", isOn: $settings.fasterCaptions)
                        .disabled(model.isRunning || model.isBusy)
                    Text("Apple's speech model runs on your Mac. First use may download language assets. Source and locale changes apply to the next session.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Section("Floating captions") {
                    Text("The caption panel stays above normal app windows across desktops, Stage Manager, and eligible full-screen apps. It stays visible when another app is active.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Toggle("Request screen-capture exclusion", isOn: $settings.requestCaptureExclusion)
                    Text("Best effort only: macOS does not reliably exclude visible windows from screen sharing. This uses a legacy compatibility hint that modern sharing apps may ignore. Share a specific app window, or keep captions on a display you are not sharing. Use Hide on the panel or in the menu bar to remove it immediately.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Link("Apple's capture-exclusion limitation", destination: URL(string: "https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none")!)
                        .font(.system(size: 11))
                }
                Section("AI assistance") {
                    Toggle("Send meeting text through OpenRouter", isOn: $settings.cloudEnabled)
                    Text("Only text is sent to OpenRouter and the selected model provider: captions, meeting context, your live note, any enabled saved profile, a previous recap, and your reply draft. Audio stays on your Mac. Usage is billed to your OpenRouter account; provider data policies apply.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    ModelPickerView(settings: settings)
                        .onChange(of: settings.model) { _, _ in model.cancelAI() }
                    HStack {
                        SecureField(settings.hasAPIKey ? "Replace OpenRouter key" : "OpenRouter API key", text: $enteredKey)
                        Button("Save key") { saveKey() }.disabled(enteredKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    HStack {
                        Label(settings.hasAPIKey ? "API key saved in this app" : "No API key saved",
                              systemImage: settings.hasAPIKey ? "checkmark.circle" : "key")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if settings.hasAPIKey { Button("Remove key", role: .destructive) { removeKey() } }
                    }.font(.system(size: 11))
                    Text("Your API key is saved unencrypted in this app's local preferences. It stays on this Mac and is used to authenticate requests to OpenRouter.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    if let credentialMessage { Text(credentialMessage).font(.system(size: 11)).foregroundStyle(.secondary) }
                    Toggle("Automatic English help", isOn: $settings.automaticHelp).disabled(!settings.cloudEnabled)
                    Toggle("Update replies when my live note changes", isOn: $settings.followIntent).disabled(!settings.cloudEnabled)
                    Text("Automatic help waits for 1.2 seconds without changed captions, skips acknowledgments and your own answers, and shows only new useful help. This estimates a pause from transcript updates; it does not measure audio silence. It can incur ongoing API charges while listening.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Section("Session data") {
                    Text("Audio is not recorded to disk. Chats save automatically on this Mac, including finalized captions, AI answers, request context, notes, and drafts. History lets you search, read, and permanently delete saved chats. New chat saves the current chat before resetting the workspace. The latest chat is restored when you reopen the app. Saved text files are not encrypted by the app. Your saved profile is managed separately.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
        }
        .frame(width: 620, height: 780)
        .onAppear { settings.refreshCredentialStatus() }
    }

    private func saveKey() {
        CredentialStore.save(enteredKey.trimmingCharacters(in: .whitespacesAndNewlines))
        enteredKey = ""
        settings.refreshCredentialStatus()
        credentialMessage = "Saved locally in app preferences. Enable transcript sharing above to use AI assistance."
    }

    private func removeKey() {
        CredentialStore.delete()
        settings.cloudEnabled = false
        settings.refreshCredentialStatus()
        enteredKey = ""
        credentialMessage = "API key removed from app storage."
    }

}

private struct ProfileEditor: View {
    @ObservedObject var settings: AppSettings

    private var profileBinding: Binding<String> {
        Binding(get: { settings.profileNote }, set: { settings.profileNote = String($0.prefix(2000)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tell the assistant who you are and how you prefer to communicate.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                if settings.profileNote.isEmpty {
                    Text("My name and role…\nMy English level…\nI prefer short, polite replies…\nAvoid jargon; don't make commitments for me…")
                        .font(.system(size: 13)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 10).padding(.vertical, 10).allowsHitTesting(false)
                }
                TextEditor(text: profileBinding).font(.system(size: 13))
                    .scrollContentBackground(.hidden).padding(5)
                    .accessibilityLabel("Saved profile note")
            }
            .frame(height: 125)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.quaternary))
            HStack {
                Text("\(settings.profileNote.count)/2000 characters").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Clear profile") { settings.profileNote = "" }
                    .font(.system(size: 11)).disabled(settings.profileNote.isEmpty)
            }
            Toggle("Include my profile in AI requests", isOn: $settings.includeProfile)
            Text("Saved automatically on this Mac. Shared only when AI text sharing is on and this switch is enabled. Changes apply to the next request. Your live note can override these preferences for a particular reply.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text("No additional AI call: the short profile travels with the same request as your meeting text. Response time still depends on the model and network.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
