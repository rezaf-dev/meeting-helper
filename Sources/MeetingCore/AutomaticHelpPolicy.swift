import Foundation

/// Tracks handled caption revisions, so old questions are context rather than new work.
public struct AutomaticHelpPolicy: Sendable {
    public static let quietInterval: TimeInterval = 1.2
    private var handled: [UUID: String] = [:]
    public init() {}

    public static func isSettled(_ ledger: TranscriptLedger, lastActivity: Date, now: Date = Date()) -> Bool {
        guard now.timeIntervalSince(lastActivity) >= quietInterval else { return false }
        let lastFinalTime = ledger.finalized.last?.timestamp ?? .distantPast
        return !ledger.partials.values.contains(where: { $0.timestamp >= lastFinalTime })
    }

    public mutating func markHandled(_ captions: [Caption]) {
        handled = Dictionary(uniqueKeysWithValues: captions.map { ($0.id, $0.text) })
    }

    public func newContext(in captions: [Caption]) -> String? {
        let changed = captions.filter { handled[$0.id] != $0.text }
        guard let latest = changed.lastIndex(where: { !Self.isAcknowledgment($0.text) }) else { return nil }
        // Your answer closes the previous prompt. Only a new meeting turn can
        // reopen automatic help; microphone-only sessions use the manual buttons.
        guard changed[latest].source == .system,
              !changed[latest...].contains(where: { $0.source == .microphone }) else { return nil }
        let lines = changed.map { "[\($0.source.label)] \($0.text)" }.joined(separator: "\n")
        return String(lines.suffix(6000))
    }

    public static func isAcknowledgment(_ text: String) -> Bool {
        let normalized = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
        return ["", "ok", "okay", "yes", "yeah", "yep", "no", "nope", "sure", "right", "alright",
                "thanks", "thank you", "got it", "understood", "i see", "sounds good", "makes sense",
                "that makes sense", "uh huh", "mm hmm", "no clarification needed"].contains(normalized)
    }
}

public enum LiveHelpResult {
    public static let noUpdate = "NO_UPDATE"
    public static func usefulText(_ text: String, previous: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased().trimmingCharacters(in: .punctuationCharacters)
        guard !trimmed.isEmpty, normalized != "no_update", normalized != "no clarification needed",
              trimmed != previous.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return trimmed
    }
}
