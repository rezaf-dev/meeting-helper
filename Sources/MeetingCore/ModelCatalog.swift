import Foundation

public struct OpenRouterModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let guidance: String?

    public init(id: String, name: String, guidance: String? = nil) {
        self.id = id
        self.name = name
        self.guidance = guidance
    }

    public static let defaultID = "google/gemini-3.1-flash-lite"
    public static let suggested = OpenRouterModel(id: defaultID, name: "Gemini 3.1 Flash Lite",
        guidance: "Default for short, responsive meeting help.")

    // Verified against OpenRouter's public text-model catalog on 2026-10-27.
    // Presets are available offline; the full browser can fetch the current catalog.
    public static let presets: [Self] = [
        .suggested,
        .init(id: "openai/gpt-6-luna", name: "GPT-6 Luna",
              guidance: "Cost-efficient option for replies and everyday meeting help."),
        .init(id: "deepseek/deepseek-v4.1-flash-1017", name: "DeepSeek V4.1 Flash",
              guidance: "Try for technical questions and explanations. October 17 snapshot."),
        .init(id: "google/gemini-3.5-flash-lite", name: "Gemini 3.5 Flash Lite",
              guidance: "Another lightweight option for concise help and recaps."),
        .init(id: "qwen/qwen3.5-35b-a3b", name: "Qwen3.5 35B A3B",
              guidance: "Try for explanations and alternative ways to phrase a reply."),
        .init(id: "meta-llama/llama-3.3-70b-instruct", name: "Llama 3.3 70B Instruct",
              guidance: "Text-only alternative for summaries and simpler explanations.")
    ]

    public static func decodeCatalog(_ data: Data) throws -> [Self] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let entries = root?["data"] as? [[String: Any]] else {
            throw AIClientError.message("OpenRouter returned an invalid model catalog.")
        }
        var seen: Set<String> = []
        return entries.compactMap { entry in
            guard let id = entry["id"] as? String, let name = entry["name"] as? String,
                  !id.isEmpty, seen.insert(id).inserted,
                  let architecture = entry["architecture"] as? [String: Any],
                  (architecture["input_modalities"] as? [String])?.contains("text") == true,
                  (architecture["output_modalities"] as? [String])?.contains("text") == true else { return nil }
            return OpenRouterModel(id: id, name: name)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func fetch() async throws -> [Self] {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIClientError.message("Could not load the OpenRouter model list. You can still enter a model ID manually.")
        }
        return try decodeCatalog(data)
    }
}
