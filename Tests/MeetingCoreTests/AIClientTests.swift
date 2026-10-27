import Foundation
import Testing
@testable import MeetingCore

private final class MockStreamProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions" else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let mode = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let status = mode.contains("unauthorized") ? 401 : (mode.contains("no-credit") ? 402 : 200)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                                                            httpVersion: "HTTP/1.1",
                                                            headerFields: ["Content-Type": "text/event-stream"])!,
                            cacheStoragePolicy: .notAllowed)
        if mode.contains("waiting") { return }
        let pieces: [String]
        if mode.contains("truncated") {
            pieces = ["data: {\"choices\":[{\"delta\":{\"content\":\"Partial\"}}]}\n\n"]
        } else if mode.contains("provider-failed") {
            pieces = ["data: {\"error\":{\"code\":\"server_error\"},\"choices\":[{\"delta\":{},\"finish_reason\":\"error\"}]}\n\n"]
        } else {
            pieces = [
                ": OPENROUTER PROCESSING\n\ndata: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\n\n",
                "data: {\"choices\":[{\"delta\":{\"reasoning\":\"Do not display this\"}}]}\n\n",
                "data: {\"choices\":[{\"delta\":{\"content\":\"They want \"}}]}\n\n",
                "data: {\"choices\":[{\"delta\":{\"content\":\"an estimate.\"},\"finish_reason\":\"stop\"}]}\n\n",
                "data: {\"choices\":[{\"delta\":{\"content\":\"\"},\"finish_reason\":\"stop\"}],\"usage\":{\"total_tokens\":10}}\n\n",
                "data: [DONE]\n\n"
            ]
        }
        for piece in pieces {
            let data = Data(piece.utf8)
            let middle = data.count / 2
            client?.urlProtocol(self, didLoad: data.prefix(middle))
            client?.urlProtocol(self, didLoad: data.suffix(data.count - middle))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
struct AIClientTests {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockStreamProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func streamedOpenRouterChunksReachUIInOrderWithoutReasoningOrUsage() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        var deltas: [String] = []
        try await AIClient().analyze(key: "fixture", model: OpenRouterModel.defaultID, action: .question,
                                    transcript: "[Meeting] Can you estimate?", notes: "", memory: "", draft: "",
                                    session: session) { deltas.append($0) }
        #expect(deltas == ["They want ", "an estimate."])
    }

    @Test func earlyDisconnectPreservesPartialTextAndReportsFailure() async {
        let session = session()
        defer { session.invalidateAndCancel() }
        var text = ""
        do {
            try await AIClient().analyze(key: "truncated", model: OpenRouterModel.defaultID, action: .live,
                                        transcript: "Test", notes: "", memory: "", draft: "",
                                        session: session) { text += $0 }
            Issue.record("A truncated stream must throw")
        } catch {
            #expect(text == "Partial")
            #expect(error.localizedDescription.contains("ended early"))
        }
    }

    @Test func authErrorsAreActionableAndDoNotExposeCredentials() async {
        let session = session()
        defer { session.invalidateAndCancel() }
        do {
            try await AIClient().analyze(key: "unauthorized-secret", model: OpenRouterModel.defaultID, action: .live,
                                        transcript: "Test", notes: "", memory: "", draft: "",
                                        session: session) { _ in }
            Issue.record("An unauthorized request must throw")
        } catch {
            #expect(error.localizedDescription.contains("API access was denied"))
            #expect(!error.localizedDescription.contains("unauthorized-secret"))
        }
    }

    @Test func openRouterCreditAndMidStreamFailuresAreReported() async {
        for mode in ["no-credit", "provider-failed"] {
            let session = session()
            defer { session.invalidateAndCancel() }
            do {
                try await AIClient().analyze(key: mode, model: OpenRouterModel.defaultID, action: .reply,
                                            transcript: "Test", notes: "", memory: "", draft: "", intent: "need two days",
                                            session: session) { _ in Issue.record("An error response must not emit a reply") }
                Issue.record("The failed request must throw")
            } catch {
                #expect(error.localizedDescription.contains(mode == "no-credit" ? "credits" : "provider"))
            }
        }
    }

    @Test func canceledStreamingRequestStopsWithoutOutput() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let task = Task {
            try await AIClient().analyze(key: "waiting", model: OpenRouterModel.defaultID, action: .live,
                                        transcript: "Test", notes: "", memory: "", draft: "",
                                        session: session) { _ in Issue.record("Canceled fixture should not emit text") }
        }
        try await Task.sleep(for: .milliseconds(80))
        task.cancel()
        do { try await task.value; Issue.record("Cancellation must end the request") }
        catch { #expect(task.isCancelled) }
    }
}
