import Foundation

public enum EnglishLevel: String, CaseIterable, Identifiable, Sendable {
    case basic, intermediate, advanced
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .basic: "Basic"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        }
    }
    var instruction: String {
        switch self {
        case .basic: "Use familiar words and short sentences. Explain unfamiliar expressions only when relevant."
        case .intermediate: "The user understands everyday English and most meeting content. Do not explain basic words or paraphrase obvious statements. Focus on idioms, important jargon, implied requests, and wording they can use."
        case .advanced: "Assume strong English comprehension. Focus only on subtle meaning, ambiguity, implications, or precise wording. Do not teach vocabulary unless asked or essential."
        }
    }
}

public enum AnswerLength: String, CaseIterable, Identifiable, Sendable {
    case brief, balanced, detailed
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

public enum SpeakingStyle: String, CaseIterable, Identifiable, Sendable {
    case hints, fullReply
    public var id: String { rawValue }
    public var label: String { self == .hints ? "Speaking hints" : "Full replies" }
}

public struct AIHelpPreferences: Equatable, Sendable {
    public let level: EnglishLevel
    public let length: AnswerLength
    public let importantOnly: Bool
    public let speakingStyle: SpeakingStyle

    public init(level: EnglishLevel = .intermediate, length: AnswerLength = .brief,
                importantOnly: Bool = true, speakingStyle: SpeakingStyle = .hints) {
        self.level = level
        self.length = length
        self.importantOnly = importantOnly
        self.speakingStyle = speakingStyle
    }

    public func wordLimit(for action: AssistanceAction) -> Int {
        switch length {
        case .brief:
            return action == .recap ? 80 : (action == .explain ? 45 : 35)
        case .balanced:
            return action == .recap ? 160 : (action == .explain ? 100 : 80)
        case .detailed:
            return action == .recap ? 240 : (action == .explain ? 180 : 100)
        }
    }

    public func tokenLimit(for action: AssistanceAction) -> Int {
        // Leave headroom for punctuation and varied tokenization; the prompt
        // controls brevity, rather than cutting off a sentence at its word limit.
        max(180, wordLimit(for: action) * 4)
    }

    public func instruction(for action: AssistanceAction) -> String {
        """
        Configured English level: \(level.rawValue). \(level.instruction)
        Configured answer length: \(length.rawValue). Maximum \(wordLimit(for: action)) words in total.
        \(length == .brief ? "Aim for one or two short sentences; a recap may use up to three compact bullets. Give one usable answer, not several alternatives. No headings, introductions, repeated transcript, or separate 'what was said' and 'interpretation' sections." : "Keep each point useful and avoid repetition. Add detail only when it helps the selected task.")
        \(importantOnly ? "Explain only what matters to understanding the question or responding correctly. Skip routine vocabulary and obvious statements. For automatic live help, if nothing useful is new, return only NO_UPDATE. Never produce a status message saying nothing needs clarification. For a manual explanation, briefly state that the meaning is straightforward if needed. Always flag consequential uncertainty about names, dates, numbers, or commitments." : "Explain expressions appropriate to the configured English level when they help understanding; avoid a general grammar lesson.")
        \(speakingStyle == .hints && (action == .reply || action == .live) ? "Speaking style: hints. Give at most two useful vocabulary items or collocations with a short meaning, and one reusable sentence pattern with [placeholders] tied to the current topic or live_intent. Help the user form their own words; do not write a complete ready-to-say answer, fill in the placeholders, or invent their position. This speaking style overrides instructions to draft or put a full spoken reply first. Skip routine words and avoid repeating earlier hints." : "For a reply, put the speakable reply first. Add a short explanation only if essential; do not annotate every sentence.")
        These configured preferences override conflicting English-level or verbosity preferences in saved_user_profile. Follow current live_intent within the chosen word limit.
        """
    }
}
