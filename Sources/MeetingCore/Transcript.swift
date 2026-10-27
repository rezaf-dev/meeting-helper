import Foundation

public enum AudioSource: String, CaseIterable, Identifiable, Sendable, Codable {
    case microphone, system
    public var id: String { rawValue }
    public var label: String { self == .microphone ? "You" : "Meeting" }
    public var symbol: String { self == .microphone ? "mic" : "speaker.wave.2" }
}

public struct Caption: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var source: AudioSource
    public var text: String
    public var start: Double
    public var end: Double
    public var timestamp: Date
    public var isFinal: Bool

    public init(id: UUID = UUID(), source: AudioSource, text: String, start: Double,
                end: Double, timestamp: Date = Date(), isFinal: Bool) {
        self.id = id
        self.source = source
        self.text = text
        self.start = start
        self.end = end
        self.timestamp = timestamp
        self.isFinal = isFinal
    }
}

public struct TranscriptLedger: Sendable {
    public private(set) var finalized: [Caption] = []
    public private(set) var partials: [AudioSource: Caption] = [:]
    public let capacity: Int

    public init(capacity: Int = 500) { self.capacity = max(1, capacity) }

    public var displayed: [Caption] {
        (finalized + Array(partials.values)).sorted { $0.timestamp < $1.timestamp }
    }

    public mutating func receive(_ caption: Caption) {
        guard !caption.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if caption.isFinal {
            // A finalized range replaces the volatile hypothesis for this source only.
            if let partial = partials[caption.source], partial.start < caption.end + 0.001 {
                partials[caption.source] = nil
            }
            if let index = finalized.firstIndex(where: {
                $0.source == caption.source && abs($0.start - caption.start) < 0.001
            }) {
                var replacement = caption
                replacement = Caption(id: finalized[index].id, source: replacement.source,
                                      text: replacement.text, start: replacement.start, end: replacement.end,
                                      timestamp: replacement.timestamp, isFinal: true)
                finalized[index] = replacement
            } else {
                finalized.append(caption)
            }
            finalized.sort { $0.timestamp < $1.timestamp }
            if finalized.count > capacity { finalized.removeFirst(finalized.count - capacity) }
        } else {
            // Ignore a late hypothesis for a range already finalized.
            guard !finalized.contains(where: {
                $0.source == caption.source && $0.start <= caption.start + 0.001 && $0.end >= caption.end
            }) else { return }
            let id = partials[caption.source]?.id ?? caption.id
            partials[caption.source] = Caption(id: id, source: caption.source, text: caption.text,
                                              start: caption.start, end: caption.end,
                                              timestamp: caption.timestamp, isFinal: false)
        }
    }

    public mutating func clearPartials() { partials.removeAll() }

    public func context(maxCharacters: Int = 12_000) -> String {
        let limit = max(0, maxCharacters)
        var lines: [String] = []
        var used = 0
        for caption in finalized.reversed() {
            let line = "[\(caption.source.label)] \(caption.text)"
            let cost = line.count + (lines.isEmpty ? 0 : 1)
            guard used + cost <= limit else {
                if lines.isEmpty { lines.append(String(line.suffix(limit))) }
                break
            }
            lines.append(line)
            used += cost
        }
        return lines.reversed().joined(separator: "\n")
    }

    public var exportText: String {
        finalized.map {
            "[\($0.timestamp.formatted(date: .omitted, time: .standard))] \($0.source.label): \($0.text)"
        }.joined(separator: "\n\n")
    }
}
