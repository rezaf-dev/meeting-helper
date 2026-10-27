import Foundation

public struct SavedChat: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var captions: [Caption]
    public var answers: [AssistanceRecord]
    public var notes: String
    public var draft: String
    public var intent: String

    public init(id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date = Date(),
                captions: [Caption] = [], answers: [AssistanceRecord] = [],
                notes: String = "", draft: String = "", intent: String = "") {
        self.id = id; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.captions = captions; self.answers = answers
        self.notes = notes; self.draft = draft; self.intent = intent
    }

    public var isEmpty: Bool {
        captions.isEmpty && answers.isEmpty && [notes, draft, intent].allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public var title: String {
        let text = [intent, captions.first?.text ?? "", answers.first?.title ?? "", notes, draft]
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "Meeting"
        return String(text.replacingOccurrences(of: "\n", with: " ").prefix(70))
    }
}

/// Each chat is independently and atomically saved, so deleting one never rewrites another.
public struct ChatStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func load() throws -> [SavedChat] { try loadReport().chats }

    public func loadReport() throws -> (chats: [SavedChat], unreadableFiles: [String]) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return ([], []) }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        var chats: [SavedChat] = []
        var failed: [String] = []
        for file in files {
            do { chats.append(try JSONDecoder().decode(SavedChat.self, from: Data(contentsOf: file))) }
            catch { failed.append(file.lastPathComponent) }
        }
        // Keep unreadable files intact and surface the failure instead of silently dropping history.
        return (chats.sorted { $0.updatedAt > $1.updatedAt }, failed.sorted())
    }

    public func save(_ chat: SavedChat) throws {
        guard !chat.isEmpty || FileManager.default.fileExists(atPath: file(chat.id).path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(chat).write(to: file(chat.id), options: .atomic)
    }

    public func delete(id: UUID) throws {
        let url = file(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
}

