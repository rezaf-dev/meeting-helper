import Testing
import Foundation
@testable import MeetingCore

struct AIProtocolTests {
    @Test func sseFramingHandlesCommentsCRLFAndMultilineData() throws {
        var parser = SSEParser()
        #expect(parser.consume(line: ": heartbeat\r") == nil)
        #expect(parser.consume(line: "event: message\r") == nil)
        #expect(parser.consume(line: "data: {\"choices\":[{\"delta\":\r") == nil)
        #expect(parser.consume(line: "data: {\"content\":\"Hello\"}}]}\r") == nil)
        let framed = parser.consume(line: "\r")
        let payload = try #require(framed)
        #expect(try ChatStreamEvent.decode(payload) == .delta("Hello"))
        #expect(parser.consume(line: "") == nil)
    }

    @Test func completionRequiresDoneAndHandlesUsageErrorsAndOutputLimits() throws {
        #expect(try ChatStreamEvent.decode("[DONE]") == .completed)
        #expect(try ChatStreamEvent.decode(#"{"choices":[],"usage":{"total_tokens":5}}"#) == .ignored)
        #expect(try ChatStreamEvent.decode(#"{"choices":[{"delta":{"role":"assistant"}}]}"#) == .ignored)
        #expect(try ChatStreamEvent.decode(#"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#) == .ignored)
        for payload in [#"{"error":{"code":502}}"#,
                        #"{"choices":[{"delta":{},"finish_reason":"length"}]}"#] {
            if case .failed = try ChatStreamEvent.decode(payload) {} else { Issue.record("Must report failed/incomplete streams") }
        }
        #expect(throws: (any Error).self) { try ChatStreamEvent.decode("broken JSON") }
    }

    @Test func requestContainsOnlyBoundedTextAndKeepsPrivateIntentDistinctFromSpeech() throws {
        let body = AIPrompt.requestBody(model: OpenRouterModel.defaultID, action: .reply,
                                       transcript: String(repeating: "x", count: 20_000),
                                       notes: "meeting at 3", memory: "context", draft: "need one day",
                                       intent: "clarify scope; no promise of Friday")
        #expect(body["stream"] as? Bool == true)
        #expect(body["audio"] == nil)
        #expect(body["input"] == nil)
        #expect(body["max_tokens"] as? Int == 180)
        #expect((body["provider"] as? [String: String])?["sort"] == "latency")
        #expect((body["reasoning"] as? [String: Bool])?["enabled"] == false)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.count == 2)
        let json = try #require(messages.last?["content"])
        let fields = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String])
        #expect(fields["recent_final_transcript"]?.count == 12_000)
        #expect(fields["user_reply_draft"] == "need one day")
        #expect(fields["live_intent"] == "clarify scope; no promise of Friday")
        #expect(!fields["recent_final_transcript"]!.contains("no promise"))
        let instructions = try #require(messages.first?["content"])
        #expect(instructions.contains("untrusted data"))
        #expect(instructions.contains("current live_intent takes precedence"))
        #expect(instructions.contains("Never claim these private notes were spoken"))
        #expect(instructions.contains("Do not invent commitments"))
        _ = try JSONSerialization.data(withJSONObject: body)
    }

    @Test func liveDirectionIsBoundedAndAvailableWithoutTranscript() throws {
        let body = AIPrompt.requestBody(model: OpenRouterModel.defaultID, action: .reply, transcript: "",
                                       notes: "", memory: "", draft: "", intent: String(repeating: "a", count: 6000))
        let messages = try #require(body["messages"] as? [[String: String]])
        let content = try #require(messages.last?["content"])
        let fields = try #require(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: String])
        #expect(fields["live_intent"]?.count == 3000)
        #expect(fields["recent_final_transcript"] == "")
    }

    @Test func catalogFiltersNonTextModelsAndDeduplicates() throws {
        let payload = #"{"data":[{"id":"speech/only","name":"Speech","architecture":{"input_modalities":["audio"],"output_modalities":["audio"]}},{"id":"google/flash","name":"Flash","architecture":{"input_modalities":["text","image"],"output_modalities":["text"]}},{"id":"google/flash","name":"Duplicate","architecture":{"input_modalities":["text"],"output_modalities":["text"]}}]}"#
        let models = try OpenRouterModel.decodeCatalog(Data(payload.utf8))
        #expect(models.count == 1)
        #expect(models.first?.id == "google/flash")
        #expect(throws: (any Error).self) { try OpenRouterModel.decodeCatalog(Data("{}".utf8)) }
    }

    @Test func savedProfileIsBoundedStableAndSeparateFromCurrentIntent() throws {
        let profile = "My role is a designer. Prefer concise, polite English. " + String(repeating: "x", count: 3000)
        func messages(intent: String) throws -> [[String: String]] {
            let body = AIPrompt.requestBody(model: OpenRouterModel.defaultID, action: .reply,
                                           transcript: "[Meeting] Could you estimate?", notes: "", memory: "", draft: "",
                                           intent: intent, profile: profile, sessionID: "meeting-fixture")
            #expect(body["session_id"] as? String == "meeting-fixture")
            return try #require(body["messages"] as? [[String: String]])
        }
        let initial = try messages(intent: "use a detailed answer this time")
        let revised = try messages(intent: "ask for clarification instead")
        #expect(initial.count == 3)
        #expect(initial[1] == revised[1])
        let profileContent = try #require(initial[1]["content"])
        let fields = try #require(JSONSerialization.jsonObject(with: Data(profileContent.utf8)) as? [String: String])
        #expect(fields["saved_user_profile"]?.count == 2000)
        #expect(!initial.last!["content"]!.contains("My role is a designer"))
        #expect(initial[0]["content"]!.contains("Current live_intent overrides conflicting profile preferences"))
    }

    @Test func excludedOrEmptyProfileIsNotSentAndDoesNotAddAMessage() throws {
        let body = AIPrompt.requestBody(model: OpenRouterModel.defaultID, action: .reply,
                                       transcript: "Test", notes: "", memory: "", draft: "", profile: "   \n")
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.count == 2)
        #expect(messages.last?["content"]?.contains("saved_user_profile") == false)
        #expect(body["session_id"] == nil)
    }
    @Test func defaultHelpIsIntermediateBriefAndSelectiveWithoutProfile() throws {
        let body = AIPrompt.requestBody(model: OpenRouterModel.defaultID, action: .reply,
                                       transcript: "Can you give us a ballpark estimate?",
                                       notes: "", memory: "", draft: "")
        let messages = try #require(body["messages"] as? [[String: String]])
        let prompt = try #require(messages.first?["content"])
        #expect(messages.count == 2)
        #expect(prompt.contains("Configured English level: intermediate"))
        #expect(prompt.contains("Maximum 35 words in total"))
        #expect(prompt.contains("Do not explain basic words"))
        #expect(prompt.contains("No headings, introductions, repeated transcript"))
        #expect(prompt.contains("Do not invent commitments"))
        #expect(prompt.contains("Always flag consequential uncertainty"))
    }

    @Test func helpPreferencesControlEachActionAndOverrideOldProfileStyle() throws {
        for action in AssistanceAction.allCases {
            let brief = AIHelpPreferences()
            let detailed = AIHelpPreferences(level: .advanced, length: .detailed, importantOnly: false)
            let body = AIPrompt.requestBody(model: OpenRouterModel.defaultID, action: action,
                                           transcript: "Meeting", notes: "", memory: "", draft: "",
                                           profile: "I need beginner-level explanations.", preferences: detailed)
            let messages = try #require(body["messages"] as? [[String: String]])
            let prompt = try #require(messages.first?["content"])
            #expect(prompt.contains("Configured English level: advanced"))
            #expect(prompt.contains("Configured answer length: detailed"))
            #expect(prompt.contains("override conflicting English-level or verbosity preferences"))
            #expect(!prompt.contains("Explain only what matters"))
            #expect(body["max_tokens"] as? Int == detailed.tokenLimit(for: action))
            #expect(detailed.wordLimit(for: action) > brief.wordLimit(for: action))
        }
    }

}
