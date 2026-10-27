// Compiled with the production LocalSpeech.swift by speech-smoke-test.sh.
// Uses a supplied audio file only. Never captures devices or calls the AI API.
import AVFoundation
import Foundation
import MeetingCore

@main
enum SpeechProbe {
    @MainActor static func main() async {
        guard CommandLine.arguments.count == 2 else {
            print("Usage: speech-probe /path/to/synthetic-fixture.aiff")
            exit(2)
        }
        var pipelines: [LocalSpeech] = []
        do {
            var results: [AudioSource: String] = [:]
            var failures: [String] = []
            var dropped = 0
            var partialCount = 0
            var callbacks: [@Sendable (OwnedAudio) -> Void] = []
            for source in AudioSource.allCases {
                let pipeline = LocalSpeech(source: source)
                pipelines.append(pipeline)
                callbacks.append(try await pipeline.start(
                    localeID: "en-US", vocabulary: ["authentication", "integration"],
                    status: { print($0) },
                    result: { caption in
                        if caption.isFinal { results[source, default: ""] += caption.text + " " }
                        else { partialCount += 1 }
                    },
                    failure: { failures.append($0) }, overflow: { dropped += 1 }))
            }
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: CommandLine.arguments[1]))
            guard file.length > 0 else { throw MeetingError.message("The fixture has no audio frames.") }
            print("Feeding \(Double(file.length) / file.processingFormat.sampleRate) seconds to two independent local pipelines")
            while file.framePosition < file.length {
                let count = AVAudioFrameCount(min(2048, file.length - file.framePosition))
                let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count)!
                try file.read(into: buffer, frameCount: count)
                if let frame = OwnedAudio(copying: buffer) { for callback in callbacks { callback(frame) } }
                try await Task.sleep(for: .seconds(Double(buffer.frameLength) / file.processingFormat.sampleRate))
            }
            for pipeline in pipelines { await pipeline.stop() }
            for source in AudioSource.allCases { print("\(source.label): \(results[source] ?? "<empty>")") }
            print("Partial updates: \(partialCount); dropped buffers: \(dropped)")
            guard failures.isEmpty else { throw MeetingError.message(failures.joined(separator: "\n")) }
            guard results.count == 2, results.values.allSatisfy({ $0.lowercased().contains("estimate") }) else {
                throw MeetingError.message("Expected both local pipelines to transcribe the fixture's word ‘estimate’.")
            }
            guard partialCount > 0, dropped == 0 else { throw MeetingError.message("Expected live partials without dropped audio.") }
            print("PASS: dual-source local transcription and finalization")
        } catch {
            for pipeline in pipelines { await pipeline.cancel() }
            print("FAIL: \(error.localizedDescription)")
            exit(1)
        }
    }
}
