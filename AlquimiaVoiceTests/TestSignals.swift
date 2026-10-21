import Foundation
@testable import AlquimiaVoice

/// Synthetic 16 kHz signals for VAD, meter and resampler tests.
enum TestSignals {
    static func sine(ms: Int, frequency: Double = 440, amplitude: Double = 0.1, sampleRate: Double = 16_000) -> [Int16] {
        let count = Int(sampleRate * Double(ms) / 1000)
        return (0..<count).map { index in
            let value = sin(2 * .pi * frequency * Double(index) / sampleRate) * amplitude * 32767
            return Int16(value.rounded())
        }
    }

    static func silence(ms: Int, sampleRate: Double = 16_000) -> [Int16] {
        [Int16](repeating: 0, count: Int(sampleRate * Double(ms) / 1000))
    }

    /// Low-level noise around −60 dBFS, below the −40 dBFS activation threshold.
    static func noise(ms: Int, sampleRate: Double = 16_000) -> [Int16] {
        let count = Int(sampleRate * Double(ms) / 1000)
        var generator = SystemRandomNumberGenerator()
        return (0..<count).map { _ in Int16.random(in: -32...32, using: &generator) }
    }
}
