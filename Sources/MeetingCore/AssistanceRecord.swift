import Foundation

public struct AssistanceRecord: Identifiable, Equatable, Sendable, Codable {
    public enum Status: String, Sendable, Codable { case complete, partial, failed }
    public let id: UUID
    public let title: String
    public let text: String
    public let date: Date
    public let model: String
    public let status: Status
    public let input: String?

    public init(id: UUID = UUID(), title: String, text: String, date: Date = Date(),
                model: String, status: Status = .complete, input: String? = nil) {
        self.id = id
        self.title = title
        self.text = text
        self.date = date
        self.model = model
        self.status = status
        self.input = input
    }

    public var exportText: String {
        "[\(date.formatted(date: .abbreviated, time: .standard))] \(title) · \(model)\(status == .complete ? "" : " (\(status.rawValue))")\n\(text)"
    }
}

/// Answers are never silently evicted.
public struct AssistanceHistory: Equatable, Sendable {
    public private(set) var entries: [AssistanceRecord] = []
    public init() {}

    public mutating func retain(_ answer: AssistanceRecord) {
        guard (!answer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || answer.input?.isEmpty == false),
              !entries.contains(where: { $0.id == answer.id }) else { return }
        entries.append(answer)
    }

    public mutating func clear() { entries.removeAll() }
    public var exportText: String { entries.map(\.exportText).joined(separator: "\n\n———\n\n") }
}
