import Foundation

public enum ChatTextKind: String, CaseIterable, Identifiable, Sendable {
    case transcript, answers, session
    public var id: Self { self }
    public var label: String {
        switch self {
        case .transcript: "Full transcript"
        case .answers: "All AI answers"
        case .session: "Full session"
        }
    }
    public var fileSuffix: String {
        switch self {
        case .transcript: "transcript"
        case .answers: "AI answers"
        case .session: "session"
        }
    }
}

extension SavedChat {
    public var transcriptText: String {
        captions.filter(\.isFinal).sorted { $0.timestamp < $1.timestamp }.map {
            "[\($0.timestamp.formatted(date: .abbreviated, time: .standard))] \($0.source.label): \($0.text)"
        }.joined(separator: "\n\n")
    }

    public var answersText: String { answers.map(\.exportText).joined(separator: "\n\n———\n\n") }

    public func text(for kind: ChatTextKind) -> String {
        switch kind {
        case .transcript: return transcriptText
        case .answers: return answersText
        case .session:
            var sections: [String] = []
            if !intent.isEmpty { sections.append("What I want to say\n\(intent)") }
            if !notes.isEmpty { sections.append("Meeting notes\n\(notes)") }
            if !draft.isEmpty { sections.append("Draft\n\(draft)") }
            if !transcriptText.isEmpty { sections.append("Transcript\n\(transcriptText)") }
            if !answersText.isEmpty { sections.append("AI answers\n\(answersText)") }
            guard !sections.isEmpty else { return "" }
            return "\(title)\n\(createdAt.formatted(date: .abbreviated, time: .standard))\n\n"
                + sections.joined(separator: "\n\n———\n\n")
        }
    }
}
