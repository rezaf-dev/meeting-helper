import Foundation
import Testing
@testable import MeetingCore

struct AutomaticHelpTests {
    private func caption(_ source: AudioSource, _ text: String, at time: Double = 0) -> Caption {
        Caption(source: source, text: text, start: time, end: time + 1,
                timestamp: Date(timeIntervalSince1970: time), isFinal: true)
    }

    @Test func pauseWaitsForBothSilenceAndFinalization() {
        var ledger = TranscriptLedger()
        let epoch = Date(timeIntervalSince1970: 100)
        ledger.receive(caption(.system, "What is the estimate?"))
        #expect(!AutomaticHelpPolicy.isSettled(ledger, lastActivity: epoch, now: epoch.addingTimeInterval(0.8)))
        #expect(AutomaticHelpPolicy.isSettled(ledger, lastActivity: epoch, now: epoch.addingTimeInterval(1.3)))
        var response = caption(.microphone, "I need to", at: 2)
        response.isFinal = false
        ledger.receive(response)
        #expect(!AutomaticHelpPolicy.isSettled(ledger, lastActivity: epoch, now: epoch.addingTimeInterval(5)))
        response.isFinal = true
        ledger.receive(response)
        let finalTime = epoch.addingTimeInterval(5)
        #expect(!AutomaticHelpPolicy.isSettled(ledger, lastActivity: finalTime, now: finalTime.addingTimeInterval(0.5)))
        #expect(AutomaticHelpPolicy.isSettled(ledger, lastActivity: finalTime, now: finalTime.addingTimeInterval(1.3)))
    }

    @Test func acknowledgmentsNeverReopenHandledQuestions() {
        var policy = AutomaticHelpPolicy()
        let question = caption(.system, "Can you estimate the integration?")
        #expect(policy.newContext(in: [question]) != nil)
        policy.markHandled([question])
        for text in ["OK.", "Okay!", "Thanks", "Yes", "Got it", "That makes sense."] {
            for source in AudioSource.allCases {
                #expect(policy.newContext(in: [question, caption(source, text, at: 2)]) == nil)
            }
        }
        #expect(policy.newContext(in: [question]) == nil)
    }

    @Test func userAnswersClosePendingQuestionsIncludingShortYes() {
        let policy = AutomaticHelpPolicy()
        let question = caption(.system, "Can you deliver this on Friday?")
        for answer in ["I need to check the scope first.", "Yes.", "No", "Okay"] {
            let reply = caption(.microphone, answer, at: 2)
            #expect(policy.newContext(in: [question, reply]) == nil)
            #expect(policy.newContext(in: [question, reply, caption(.system, "Thanks", at: 4)]) == nil)
            #expect(policy.newContext(in: [question, reply, caption(.system, "What is blocking the work?", at: 4)]) != nil)
        }
    }

    @Test func onlyNewRevisionsAreSentAsNewContextAndMicAloneStaysQuiet() {
        var policy = AutomaticHelpPolicy()
        let question = caption(.system, "How about Tuesday?")
        policy.markHandled([question])
        #expect(policy.newContext(in: [question, caption(.microphone, "Let me check.", at: 2)]) == nil)
        let next = caption(.system, "What would you need?", at: 4)
        let text = policy.newContext(in: [question, next])
        #expect(text == "[Meeting] What would you need?")
        var corrected = question
        corrected.text = "How about Thursday?"
        #expect(policy.newContext(in: [corrected]) == "[Meeting] How about Thursday?")
        #expect(policy.newContext(in: [caption(.microphone, "Can you help me estimate?")]) == nil)
        #expect(!AutomaticHelpPolicy.isAcknowledgment("Okay, but the deadline moved to Friday."))
    }

    @Test func silentOrDuplicateUpdatesAreNotDisplayable() {
        for text in ["NO_UPDATE", " NO_UPDATE\n", "NO_UPDATE.", "No clarification needed.", "", "Previous advice"] {
            #expect(LiveHelpResult.usefulText(text, previous: "Previous advice") == nil)
        }
        #expect(LiveHelpResult.usefulText("Use ‘rough estimate’.", previous: "Previous advice") == "Use ‘rough estimate’.")
    }

    @Test func speakingHintsAndFullRepliesAreDistinctAndUpdatesAreBounded() throws {
        let hints = AIHelpPreferences().instruction(for: .reply)
        #expect(hints.contains("Speaking style: hints"))
        #expect(hints.contains("[placeholders]"))
        #expect(hints.contains("do not write a complete ready-to-say answer"))
        #expect(!AIHelpPreferences(speakingStyle: .fullReply).instruction(for: .reply).contains("Speaking style: hints"))
        #expect(!AIHelpPreferences().instruction(for: .recap).contains("Speaking style: hints"))
        let body = AIPrompt.requestBody(model: "fixture/model", action: .live, transcript: "background",
                                        notes: "", memory: "", draft: "", newTranscript: String(repeating: "x", count: 7000),
                                        previousAssistance: "Old advice")
        let messages = try #require(body["messages"] as? [[String: String]])
        let data = Data(try #require(messages.last?["content"]).utf8)
        let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(fields["new_transcript"]?.count == 6000)
        #expect(fields["previous_assistance"] == "Old advice")
        #expect(messages.first?["content"]?.contains("Return exactly NO_UPDATE") == true)
    }
}
