import Foundation

/// Helpers for the wire format: PCM signed 16-bit little-endian, 16 kHz, mono.
enum PCM {
    static let sampleRate: Double = 16_000
    static let bytesPerMillisecond = 32

    /// Little-endian bytes (Apple platforms are little-endian; no byte swapping needed).
    static func data(from samples: [Int16]) -> Data {
        samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Alignment-safe decode. An odd trailing byte is dropped.
    static func samples(from data: Data) -> [Int16] {
        let count = data.count / 2
        guard count > 0 else { return [] }
        var samples = [Int16](repeating: 0, count: count)
        samples.withUnsafeMutableBufferPointer { destination in
            _ = data.copyBytes(to: destination)
        }
        return samples
    }

    static func float32(from samples: [Int16]) -> [Float] {
        samples.map { Float($0) / 32768 }
    }

    static func int16(from floats: [Float]) -> [Int16] {
        floats.map { value in
            let clamped = max(-1, min(1, value))
            return Int16((clamped * 32767).rounded())
        }
    }

    /// Normalised RMS in `0...1`, the same quantity the server's VAD thresholds against (`sqrt(mean(x²)) / 32768`).
    static func rms(_ samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var accumulator: Double = 0
        for sample in samples {
            let value = Double(sample)
            accumulator += value * value
        }
        return Float(sqrt(accumulator / Double(samples.count)) / 32768)
    }
}

/// Re-cuts arbitrary-sized sample arrays into fixed-size chunks (default 40 ms = 640 samples = 1280 bytes).
struct PCMChunker: Equatable, Sendable {
    let chunkSamples: Int
    private var pending: [Int16] = []

    init(chunkSamples: Int = 640) {
        self.chunkSamples = chunkSamples
    }

    var pendingCount: Int { pending.count }

    mutating func append(_ samples: [Int16]) -> [[Int16]] {
        pending.append(contentsOf: samples)
        var chunks: [[Int16]] = []
        while pending.count >= chunkSamples {
            chunks.append(Array(pending[..<chunkSamples]))
            pending.removeFirst(chunkSamples)
        }
        return chunks
    }

    /// Returns the remainder (any size) and clears it.
    mutating func flush() -> [Int16]? {
        defer { pending.removeAll(keepingCapacity: true) }
        return pending.isEmpty ? nil : pending
    }
}
