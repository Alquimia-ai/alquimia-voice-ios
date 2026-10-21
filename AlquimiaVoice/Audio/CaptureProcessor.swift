import AVFoundation

/// Runs on the audio tap thread only. Converts whatever the input node delivers into 16 kHz mono Int16
/// and emits fixed-size chunks. `@unchecked Sendable` because the engine calls `process` from a single
/// real-time thread and `flush`/`processedBufferCount` take the lock.
final class CaptureProcessor: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let lock = NSLock()
    private var chunker: PCMChunker
    private var buffersProcessed = 0
    private let emit: @Sendable ([Int16]) -> Void

    init?(inputFormat: AVAudioFormat, chunkSamples: Int = 640, emit: @escaping @Sendable ([Int16]) -> Void) {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: PCM.sampleRate, channels: 1, interleaved: true
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return nil }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        if inputFormat.channelCount > 1 {
            converter.channelMap = [0]
        }
        self.converter = converter
        self.outputFormat = outputFormat
        self.chunker = PCMChunker(chunkSamples: chunkSamples)
        self.emit = emit
    }

    var processedBufferCount: Int {
        lock.withLock { buffersProcessed }
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        // Feed the single input buffer once, then report `.noDataNow` (never `.endOfStream`, which would
        // finalise the converter and drop the resampler state between tap callbacks).
        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        switch status {
        case .haveData, .inputRanDry:
            let count = Int(output.frameLength)
            guard count > 0, let channel = output.int16ChannelData else { return }
            let samples = Array(UnsafeBufferPointer(start: channel[0], count: count))
            let chunks: [[Int16]] = lock.withLock {
                buffersProcessed += 1
                return chunker.append(samples)
            }
            for chunk in chunks { emit(chunk) }
        case .error:
            Log.audio.error("conversion failed: \(conversionError?.localizedDescription ?? "unknown", privacy: .public)")
        case .endOfStream:
            Log.audio.error("converter reached end of stream unexpectedly")
        @unknown default:
            break
        }
    }

    /// Remainder smaller than one chunk (sent before `stop` in push-to-talk mode).
    func flush() -> [Int16]? {
        lock.withLock { chunker.flush() }
    }
}
