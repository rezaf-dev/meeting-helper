import AVFoundation

/// Exercises the production HAL-buffer handoff without capturing any real audio.
@main
enum AudioBufferProbe {
    static func main() {
        for interleaved in [false, true] {
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                       channels: 2, interleaved: interleaved)!
            let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128)!
            source.frameLength = 128
            let buffers = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
            for entry in buffers {
                let samples = entry.mData!.assumingMemoryBound(to: Float.self)
                for index in 0..<(Int(entry.mDataByteSize) / MemoryLayout<Float>.size) {
                    samples[index] = Float(index + 1) / 1000
                }
            }
            let copied = OwnedAudio(format: format, bufferList: source.audioBufferList)!
            precondition(copied.buffer.frameLength == 128 && copied.buffer.format == format)
            let destination = UnsafeMutableAudioBufferListPointer(copied.buffer.mutableAudioBufferList)
            for (original, copy) in zip(buffers, destination) {
                precondition(copy.mData != original.mData)
                precondition(copy.mDataByteSize == original.mDataByteSize)
                precondition(memcmp(copy.mData!, original.mData!, Int(copy.mDataByteSize)) == 0)
                memset(original.mData!, 0, Int(original.mDataByteSize))
                precondition(copy.mData!.assumingMemoryBound(to: Float.self)[0] == 0.001)
            }
        }
        print("PASS: interleaved and planar stereo HAL buffers retain all samples after source reuse")
    }
}
