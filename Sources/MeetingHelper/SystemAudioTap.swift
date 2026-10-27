import AVFoundation
import CoreAudio

/// An audio-only HAL tap. Never enumerates windows or requests display capture.
@MainActor
final class SystemAudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    func start(receive: @escaping @Sendable (OwnedAudio) -> Void) throws {
        stop()
        do {
            let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            description.name = "MeetingHelper meeting audio"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            if let bundleID = Bundle.main.bundleIdentifier { description.bundleIDs = [bundleID] }
            try check(AudioHardwareCreateProcessTap(description, &tapID), operation: "create an audio tap")

            var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var streamDescription = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &streamDescription),
                      operation: "read the meeting audio format")
            guard let format = AVAudioFormat(streamDescription: &streamDescription),
                  format.sampleRate > 0, format.channelCount > 0 else {
                throw MeetingError.message("Meeting audio has an unsupported format. Try reconnecting your audio device.")
            }

            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "MeetingHelper audio input",
                kAudioAggregateDeviceUIDKey: "com.meetinghelper.tap.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]]
            ]
            try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID),
                      operation: "connect meeting audio")
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, deviceID, nil) { _, input, _, _, _ in
                // The HAL owns input; copy samples before returning from its callback.
                guard let frame = OwnedAudio(format: format, bufferList: input) else { return }
                receive(frame)
            }, operation: "prepare meeting audio")
            try check(AudioDeviceStart(deviceID, ioProcID), operation: "start meeting audio")
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let ioProcID {
            AudioDeviceStop(deviceID, ioProcID)
            AudioDeviceDestroyIOProcID(deviceID, ioProcID)
            self.ioProcID = nil
        }
        if deviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(deviceID)
            deviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status != noErr else { return }
        throw MeetingError.message("Could not \(operation) (Core Audio \(status)). Microphone access is separate from system-audio access. In System Settings → Privacy & Security → Screen & System Audio Recording, allow MeetingHelper to record system audio, then quit and reopen it. You can also turn off Meeting audio and use Microphone alone.")
    }
}
