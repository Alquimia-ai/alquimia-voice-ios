import AVFoundation
import Testing
@testable import AlquimiaVoice

final class ChunkCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [[Int16]] = []

    func append(_ chunk: [Int16]) {
        lock.withLock { chunks.append(chunk) }
    }

    var all: [Int16] {
        lock.withLock { chunks.flatMap { $0 } }
    }

    var count: Int {
        lock.withLock { chunks.count }
    }
}

@Suite("Capture processor resampling")
struct CaptureProcessorTests {
    @Test func resamplesContinuouslyAcrossBuffers() throws {
        let inputRate = 48_000.0
        let inputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: inputRate, channels: 1))
        let collector = ChunkCollector()
        let processor = try #require(CaptureProcessor(inputFormat: inputFormat) { collector.append($0) })

        let framesPerBuffer: AVAudioFrameCount = 4_800
        var sampleIndex = 0
        for _ in 0..<10 {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: framesPerBuffer))
            buffer.frameLength = framesPerBuffer
            let channel = try #require(buffer.floatChannelData)[0]
            for frame in 0..<Int(framesPerBuffer) {
                channel[frame] = Float(sin(2 * .pi * 440 * Double(sampleIndex) / inputRate) * 0.5)
                sampleIndex += 1
            }
            processor.process(buffer)
        }

        var output = collector.all
        if let tail = processor.flush() { output += tail }
        // One second of input → ~16 000 samples out; the resampler keeps ~15 ms (≈240 samples) of latency in flight.
        #expect(output.count > 15_600 && output.count <= 16_032, "got \(output.count) samples")
        #expect(processor.processedBufferCount == 10)

        var crossings = 0
        for index in 1..<output.count where (output[index - 1] < 0) != (output[index] < 0) {
            crossings += 1
        }
        // 440 Hz → 880 zero crossings per second; continuity across buffers keeps this tight.
        #expect(abs(crossings - 880) <= 24, "zero crossings: \(crossings)")

        let peak = output.map { abs(Int($0)) }.max() ?? 0
        #expect(peak > 15_000 && peak < 17_500, "peak \(peak)")
    }

    @Test func downmixesStereoInput() throws {
        let inputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let collector = ChunkCollector()
        let processor = try #require(CaptureProcessor(inputFormat: inputFormat) { collector.append($0) })
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4_410))
        buffer.frameLength = 4_410
        let channels = try #require(buffer.floatChannelData)
        for frame in 0..<4_410 {
            channels[0][frame] = 0.25
            channels[1][frame] = -0.25
        }
        processor.process(buffer)
        var output = collector.all
        if let tail = processor.flush() { output += tail }
        #expect(output.count > 1_200 && output.count <= 1_632, "got \(output.count) samples")
        // Channel map [0] keeps the left channel (positive) rather than averaging to zero.
        let mean = Double(output.reduce(0) { $0 + Int($1) }) / Double(max(output.count, 1))
        #expect(mean > 4_000, "mean \(mean)")
    }
}
