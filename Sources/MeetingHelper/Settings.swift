import Foundation
import Security
import LocalAuthentication
import MeetingCore

enum CredentialStore {
    private static let keyName = "openrouter.apiKey"
    private static let migrationName = "openrouter.localKeyMigrationCompleted"

    static func read() -> String? {
        migrateIfAvailable()
        let key = UserDefaults.standard.string(forKey: keyName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return key?.isEmpty == false ? key : nil
    }

    static func save(_ key: String) {
        let defaults = UserDefaults.standard
        defaults.set(key.trimmingCharacters(in: .whitespacesAndNewlines), forKey: keyName)
        defaults.set(true, forKey: migrationName)
        removeLegacyKey()
    }

    static func delete() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: keyName)
        // A removed key must never reappear through migration.
        defaults.set(true, forKey: migrationName)
        removeLegacyKey()
    }

    private static var legacyQuery: [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.meetinghelper.openrouter",
                kSecAttrAccount as String: "personal-api-key",
                kSecUseAuthenticationContext as String: context]
    }

    private static func migrateIfAvailable() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationName) else { return }
        // Attempt once without showing a Keychain prompt. A key protected by the
        // old build's access policy can be entered again in Settings instead.
        defaults.set(true, forKey: migrationName)
        guard defaults.string(forKey: keyName) == nil else { return }
        var query = legacyQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        defaults.set(key, forKey: keyName)
        removeLegacyKey()
    }

    private static func removeLegacyKey() {
        // Best effort cleanup only; Keychain never blocks saving or using a local key.
        SecItemDelete(legacyQuery as CFDictionary)
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard
    @Published var microphone: Bool { didSet { defaults.set(microphone, forKey: "microphone") } }
    @Published var systemAudio: Bool { didSet { defaults.set(systemAudio, forKey: "systemAudio") } }
    @Published var locale: String { didSet { defaults.set(locale, forKey: "locale") } }
    @Published var model: String { didSet { defaults.set(model, forKey: "openrouter.model") } }
    @Published var cloudEnabled: Bool { didSet { defaults.set(cloudEnabled, forKey: "openrouter.cloudEnabled") } }
    @Published var automaticHelp: Bool { didSet { defaults.set(automaticHelp, forKey: "automaticHelp") } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    @Published var vocabulary: String { didSet { defaults.set(vocabulary, forKey: "vocabulary") } }
    @Published var fasterCaptions: Bool { didSet { defaults.set(fasterCaptions, forKey: "fasterCaptions") } }
    @Published var englishLevel: EnglishLevel { didSet { defaults.set(englishLevel.rawValue, forKey: "ai.englishLevel") } }
    @Published var speakingStyle: SpeakingStyle { didSet { defaults.set(speakingStyle.rawValue, forKey: "ai.speakingStyle") } }
    @Published var answerLength: AnswerLength { didSet { defaults.set(answerLength.rawValue, forKey: "ai.answerLength") } }
    @Published var importantOnly: Bool { didSet { defaults.set(importantOnly, forKey: "ai.importantOnly") } }
    @Published var hasAPIKey = false
    @Published var followIntent: Bool { didSet { defaults.set(followIntent, forKey: "followIntent") } }
    @Published var profileNote: String { didSet { defaults.set(profileNote, forKey: "profile.note") } }
    @Published var includeProfile: Bool { didSet { defaults.set(includeProfile, forKey: "profile.include") } }
    @Published var requestCaptureExclusion: Bool { didSet { defaults.set(requestCaptureExclusion, forKey: "floating.requestCaptureExclusion") } }

    init() {
        speakingStyle = SpeakingStyle(rawValue: defaults.string(forKey: "ai.speakingStyle") ?? "") ?? .hints
        englishLevel = EnglishLevel(rawValue: defaults.string(forKey: "ai.englishLevel") ?? "") ?? .intermediate
        answerLength = AnswerLength(rawValue: defaults.string(forKey: "ai.answerLength") ?? "") ?? .brief
        importantOnly = defaults.object(forKey: "ai.importantOnly") as? Bool ?? true
        microphone = defaults.object(forKey: "microphone") as? Bool ?? true
        systemAudio = defaults.object(forKey: "systemAudio") as? Bool ?? true
        locale = defaults.string(forKey: "locale") ?? "en-US"
        // Provider-specific settings prevent reusing an OpenAI credential with OpenRouter.
        model = defaults.string(forKey: "openrouter.model") ?? OpenRouterModel.defaultID
        cloudEnabled = defaults.bool(forKey: "openrouter.cloudEnabled")
        automaticHelp = defaults.object(forKey: "automaticHelp") as? Bool ?? true
        fontSize = defaults.object(forKey: "fontSize") as? Double ?? 23
        vocabulary = defaults.string(forKey: "vocabulary") ?? ""
        fasterCaptions = defaults.bool(forKey: "fasterCaptions")
        followIntent = defaults.object(forKey: "followIntent") as? Bool ?? true
        profileNote = defaults.string(forKey: "profile.note") ?? ""
        includeProfile = defaults.object(forKey: "profile.include") as? Bool ?? true
        requestCaptureExclusion = defaults.object(forKey: "floating.requestCaptureExclusion") as? Bool ?? true
        // Read local storage only when AI is requested or Settings opens.
    }

    var helpPreferences: AIHelpPreferences {
        AIHelpPreferences(level: englishLevel, length: answerLength, importantOnly: importantOnly, speakingStyle: speakingStyle)
    }

    var vocabularyTerms: [String] {
        vocabulary.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    func refreshCredentialStatus() { hasAPIKey = CredentialStore.read() != nil }
}
