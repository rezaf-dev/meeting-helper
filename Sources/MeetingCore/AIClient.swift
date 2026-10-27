import Foundation

public enum AIClientError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

public struct AIClient: Sendable {
    // Reuse HTTPS connections across short requests to avoid repeated connection setup.
    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
    public init() {}
    public func analyze(key: String, model: String, action: AssistanceAction, transcript: String,
                 notes: String, memory: String, draft: String, intent: String = "",
                 profile: String = "", sessionID: String? = nil,
                 preferences: AIHelpPreferences = .init(),
                 newTranscript: String = "", previousAssistance: String = "",
                 session injectedSession: URLSession? = nil,
                 onDelta: @escaping @MainActor @Sendable (String) -> Void) async throws {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("MeetingHelper", forHTTPHeaderField: "X-OpenRouter-Title")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: AIPrompt.requestBody(
            model: model, action: action, transcript: transcript, notes: notes, memory: memory, draft: draft,
            intent: intent, profile: profile, sessionID: sessionID, preferences: preferences,
            newTranscript: newTranscript, previousAssistance: previousAssistance))
        let session = injectedSession ?? Self.sharedSession
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else {
            throw AIClientError.message("The AI service returned an invalid response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401, 403: throw AIClientError.message("API access was denied. Check your OpenRouter API key and model access in Settings.")
            case 402: throw AIClientError.message("OpenRouter credits are insufficient. Add credits to your OpenRouter account.")
            case 404: throw AIClientError.message("This model has no available OpenRouter endpoint. Choose another model in Settings.")
            case 429: throw AIClientError.message("OpenRouter rate limit reached. Wait briefly or choose another model.")
            case 400: throw AIClientError.message("OpenRouter rejected the request. Check the model ID in Settings.")
            default: throw AIClientError.message("AI service error (\(http.statusCode)). Captions still work; try again shortly.")
            }
        }
        var parser = SSEParser()
        var completed = false
        var received = 0
        var lineBytes: [UInt8] = []
        var eventBytes = 0
        // AsyncBytes.lines omits empty lines on Foundation, but SSE requires them as event boundaries.
        for try await byte in bytes {
            try Task.checkCancellation()
            if byte != 0x0A {
                lineBytes.append(byte)
                guard lineBytes.count <= 65_536 else {
                    throw AIClientError.message("The AI service returned an oversized stream event.")
                }
                continue
            }
            let line = String(decoding: lineBytes, as: UTF8.self)
            eventBytes += lineBytes.count
            lineBytes.removeAll(keepingCapacity: true)
            guard eventBytes <= 262_144 else {
                throw AIClientError.message("The AI service returned an oversized stream event.")
            }
            if line.isEmpty || line == "\r" { eventBytes = 0 }
            guard let payload = parser.consume(line: line) else { continue }
            switch try ChatStreamEvent.decode(payload) {
            case .delta(let delta):
                received += delta.count
                guard received <= 16_000 else { throw AIClientError.message("The AI response exceeded the display limit. Try a shorter request.") }
                await onDelta(delta)
            case .completed: completed = true
            case .failed(let message): throw AIClientError.message(message)
            case .ignored: break
            }
            if completed { break }
        }
        guard completed else { throw AIClientError.message("The AI connection ended early. The displayed answer may be incomplete.") }
        guard received > 0 else { throw AIClientError.message("The AI returned no text. Try again.") }
    }
}
