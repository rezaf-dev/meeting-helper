import AVFoundation
import MeetingCore

@MainActor
final class AudioCapture {
    private var engine: AVAudioEngine?
    private var systemTap: SystemAudioTap?
    private var configurationObserver: NSObjectProtocol?

    func startMicrophone(receive: @escaping @Sendable (OwnedAudio) -> Void,
                         failure: @escaping @MainActor @Sendable (String) -> Void) async throws {
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard allowed else {
            throw MeetingError.message("Microphone access is off. Enable MeetingHelper in System Settings → Privacy & Security → Microphone.")
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MeetingError.message("No microphone is available. Connect one and try again.")
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            if let frame = OwnedAudio(copying: buffer) { receive(frame) }
        }
        do {
            engine.prepare()
            try engine.start()
            self.engine = engine
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { _ in
                Task { @MainActor in
                    failure("Your audio device changed. Stop captions and start again to use the new device.")
                }
            }
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    func startSystemAudio(receive: @escaping @Sendable (OwnedAudio) -> Void) async throws {
        let tap = SystemAudioTap()
        try tap.start(receive: receive)
        systemTap = tap
    }

    func stop() async {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        systemTap?.stop()
        systemTap = nil
    }
}
