import AVFoundation
import CoreMedia
import Speech
import MeetingCore

enum MeetingError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Copies audio before the capture callback returns. No shared mutable sample storage.
struct OwnedAudio: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init?(format: AVAudioFormat, bufferList: UnsafePointer<AudioBufferList>) {
        guard let borrowed = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: bufferList,
                                              deallocator: nil) else { return nil }
        self.init(copying: borrowed)
    }

    init?(copying input: AVAudioPCMBuffer) {
        guard input.frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: input.frameLength) else { return nil }
        copy.frameLength = input.frameLength
        let source = UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard source.count == destination.count else { return nil }
        for (src, dst) in zip(source, destination) {
            guard let srcData = src.mData, let dstData = dst.mData else { return nil }
            memcpy(dstData, srcData, min(Int(src.mDataByteSize), Int(dst.mDataByteSize)))
        }
        buffer = copy
    }

    init?(sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let count = CMSampleBufferGetNumSamples(sampleBuffer)
        guard count > 0, count <= Int(Int32.max),
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return nil }
        pcm.frameLength = AVAudioFrameCount(count)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(count),
                                                          into: pcm.mutableAudioBufferList) == noErr else { return nil }
        buffer = pcm
    }
}

/// One converter per source, used only by that source's conversion task.
private final class PCMConverter {
    let target: AVAudioFormat
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    init(target: AVAudioFormat) { self.target = target }

    func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        if input.format == target { return input }
        if sourceFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: target)
            sourceFormat = input.format
        }
        guard let converter else { throw MeetingError.message("The audio format could not be converted. Try another audio device.") }
        let ratio = target.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw MeetingError.message("Could not allocate the audio conversion buffer.")
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true
            state.pointee = .haveData
            return input
        }
        if let error { throw error }
        if status == .error { throw MeetingError.message("Audio conversion failed. Restart captions.") }
        return output
    }
}

/// Anchor each independent speech timeline to its first captured frame, not model setup time.
private final class AudioClock: @unchecked Sendable {
    private let lock = NSLock()
    private var epoch: Date?
    func beginIfNeeded(_ frame: OwnedAudio) {
        lock.lock()
        defer { lock.unlock() }
        if epoch == nil {
            let duration = Double(frame.buffer.frameLength) / frame.buffer.format.sampleRate
            epoch = Date().addingTimeInterval(-duration)
        }
    }
    func date(at seconds: Double) -> Date {
        lock.lock()
        defer { lock.unlock() }
        return (epoch ?? Date()).addingTimeInterval(seconds.isFinite ? seconds : 0)
    }
}

@MainActor
final class LocalSpeech {
    let source: AudioSource
    private var analyzer: SpeechAnalyzer?
    private var rawContinuation: AsyncStream<OwnedAudio>.Continuation?
    private var conversionTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?

    init(source: AudioSource) { self.source = source }

    /// The returned callback only owns the thread-safe bounded continuation, not this main-actor object.
    func start(localeID: String, vocabulary: [String], fasterResults: Bool = false,
               status: @escaping @MainActor (String) -> Void,
               result: @escaping @MainActor (Caption) -> Void,
               failure: @escaping @MainActor (String) -> Void,
               overflow: @escaping @MainActor () -> Void) async throws -> @Sendable (OwnedAudio) -> Void {
        guard SpeechTranscriber.isAvailable else {
            throw MeetingError.message("Apple's on-device speech model is unavailable on this Mac.")
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else {
            throw MeetingError.message("This English locale is not supported. Choose another English locale in Settings.")
        }
        var reporting: Set<SpeechTranscriber.ReportingOption> = [.volatileResults]
        if fasterResults { reporting.insert(.fastResults) }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                             reportingOptions: reporting,
                                             attributeOptions: [.audioTimeRange])
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            status("Downloading the on-device English model…")
            try await installation.downloadAndInstall()
        }
        try Task.checkCancellation()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw MeetingError.message("No compatible format for on-device transcription.")
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber],
                                      options: .init(priority: .userInitiated, modelRetention: .whileInUse))
        self.analyzer = analyzer
        let context = AnalysisContext()
        context.contextualStrings[.general] = Array(vocabulary.prefix(100))
        try await analyzer.setContext(context)
        try await analyzer.prepareToAnalyze(in: format)
        let input = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(32))
        let raw = AsyncStream<OwnedAudio>.makeStream(bufferingPolicy: .bufferingNewest(32))
        rawContinuation = raw.continuation
        let source = self.source
        let clock = AudioClock()
        resultTask = Task {
            do {
                for try await update in transcriber.results {
                    guard !Task.isCancelled else { break }
                    let start = update.range.start.seconds
                    let end = CMTimeRangeGetEnd(update.range).seconds
                    result(Caption(source: source, text: String(update.text.characters),
                                   start: start, end: end,
                                   timestamp: clock.date(at: start),
                                   isFinal: update.isFinal))
                }
            } catch {
                if !Task.isCancelled { failure("\(source.label) transcription stopped: \(error.localizedDescription)") }
            }
        }
        // The converter is confined to this task. Capture threads only copy into a bounded stream.
        conversionTask = Task.detached(priority: .userInitiated) {
            let converter = PCMConverter(target: format)
            defer { input.continuation.finish() }
            do {
                for await frame in raw.stream {
                    try Task.checkCancellation()
                    let converted = try converter.convert(frame.buffer)
                    guard converted.frameLength > 0 else { continue }
                    if case .dropped = input.continuation.yield(AnalyzerInput(buffer: converted)) {
                        await overflow()
                    }
                }
            } catch {
                if !Task.isCancelled { await failure(error.localizedDescription) }
            }
        }
        do {
            try await analyzer.start(inputSequence: input.stream)
        } catch {
            await stop()
            throw error
        }
        return { frame in
            clock.beginIfNeeded(frame)
            if case .dropped = raw.continuation.yield(frame) {
                Task { @MainActor in overflow() }
            }
        }
    }

    func stop() async {
        let currentAnalyzer = analyzer
        // Finalization should not leave the UI stuck if a system speech service stalls.
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            await currentAnalyzer?.cancelAndFinishNow()
        }
        defer { watchdog.cancel() }
        rawContinuation?.finish()
        rawContinuation = nil
        if let conversionTask { await conversionTask.value }
        conversionTask = nil
        if let analyzer {
            do { try await analyzer.finalizeAndFinishThroughEndOfInput() }
            catch { await analyzer.cancelAndFinishNow() }
        }
        if let resultTask { await resultTask.value }
        resultTask = nil
        analyzer = nil
    }

    func cancel() async {
        rawContinuation?.finish()
        rawContinuation = nil
        conversionTask?.cancel()
        resultTask?.cancel()
        await analyzer?.cancelAndFinishNow()
        conversionTask = nil
        resultTask = nil
        analyzer = nil
    }
}
