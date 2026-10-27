import Foundation
import Testing
@testable import MeetingCore

struct ChatTextTests {
    @Test func transcriptIncludesEveryFinalCaptionInChronologicalOrder() {
        let epoch = Date(timeIntervalSince1970: 1000)
        let captions = (0..<650).map {
            Caption(source: $0.isMultiple(of: 2) ? .microphone : .system,
                    text: "Sentence \($0).", start: Double($0), end: Double($0 + 1),
                    timestamp: epoch.addingTimeInterval(Double($0)), isFinal: true)
        }
        let provisional = Caption(source: .system, text: "Unfinished hypothesis", start: 651, end: 652, isFinal: false)
        let chat = SavedChat(captions: captions.reversed() + [provisional])
        let text = chat.text(for: .transcript)
        #expect(text.components(separatedBy: "\n\n").count == 650)
        #expect(text.hasSuffix("Meeting: Sentence 649."))
        #expect(text.contains("You: Sentence 0."))
        #expect(!text.contains("Unfinished hypothesis"))
    }

    @Test func answersAndCombinedSessionPreservePartialOutputAndSeparateContent() {
        let answer = AssistanceRecord(title: "Reply", text: "Let me check the scope.", model: "example/model", status: .partial)
        let chat = SavedChat(captions: [Caption(source: .system, text: "When is it ready?", start: 0, end: 1, isFinal: true)],
                             answers: [answer], notes: "Meeting notes", draft: "My draft", intent: "Ask for time")
        let answers = chat.text(for: .answers)
        #expect(answers.contains(answer.text))
        #expect(answers.contains("(partial)"))
        #expect(answers.contains("example/model"))
        #expect(!answers.contains("When is it ready?"))
        let session = chat.text(for: .session)
        for part in ["When is it ready?", answer.text, chat.notes, chat.draft, chat.intent] {
            #expect(session.contains(part))
        }
        for kind in ChatTextKind.allCases { #expect(SavedChat().text(for: kind).isEmpty) }
    }
}
