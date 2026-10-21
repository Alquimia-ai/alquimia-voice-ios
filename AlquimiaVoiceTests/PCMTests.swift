import Foundation
import Testing
@testable import AlquimiaVoice

@Suite("PCM helpers")
struct PCMTests {
    @Test func int16ToFloatRange() {
        let floats = PCM.float32(from: [-32768, 0, 32767])
        #expect(floats[0] == -1)
        #expect(floats[1] == 0)
        #expect(abs(floats[2] - 0.99997) < 0.0001)
    }

    @Test func floatToInt16Clamps() {
        let ints = PCM.int16(from: [-2, -1, 0, 0.5, 1, 2])
        #expect(ints == [-32767, -32767, 0, 16384, 32767, 32767])
    }

    @Test func decodeFromMisalignedSlice() {
        let data = Data([0xFF, 0x01, 0x02, 0x03, 0x04])
        let slice = data[1...]
        #expect(PCM.samples(from: slice) == [0x0201, 0x0403])
        #expect(PCM.samples(from: Data([0x01])) == [])
    }

    @Test func rmsIsNormalised() {
        #expect(PCM.rms([]) == 0)
        #expect(PCM.rms([0, 0, 0]) == 0)
        let fullScale = PCM.rms([32767, -32767, 32767, -32767])
        #expect(abs(fullScale - 1) < 0.0001)
        let tone = PCM.rms(TestSignals.sine(ms: 100, amplitude: 0.1))
        #expect(abs(tone - 0.0707) < 0.002)
    }

    @Test func chunkerEmitsFixedChunksAndKeepsRemainder() {
        var chunker = PCMChunker(chunkSamples: 640)
        let first = chunker.append(Array(repeating: 1, count: 1600))
        #expect(first.count == 2)
        #expect(first.allSatisfy { $0.count == 640 })
        #expect(chunker.pendingCount == 320)

        let second = chunker.append(Array(repeating: 2, count: 1601))
        #expect(second.count == 3)
        #expect(chunker.pendingCount == 1)

        let third = chunker.append(Array(repeating: 3, count: 1600))
        #expect(third.count == 2)
        #expect(chunker.pendingCount == 321)

        #expect(chunker.flush()?.count == 321)
        #expect(chunker.flush() == nil)
        #expect(chunker.append([]).isEmpty)
    }

    @Test func chunkerPreservesOrder() {
        var chunker = PCMChunker(chunkSamples: 4)
        let chunks = chunker.append([1, 2, 3, 4, 5, 6, 7, 8, 9])
        #expect(chunks == [[1, 2, 3, 4], [5, 6, 7, 8]])
        #expect(chunker.flush() == [9])
    }
}
