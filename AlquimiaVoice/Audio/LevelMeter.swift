import Foundation

/// Smooths the microphone RMS into a 0...1 level for the UI, with the dBFS value kept around for the threshold marker.
struct LevelMeter: Equatable, Sendable {
    static let floorDBFS: Float = -60
    /// The server's VAD activation ratio (0.01) expressed in dBFS.
    static let serverThresholdDBFS: Float = -40

    var attack: Float = 0.6
    var release: Float = 0.12
    private(set) var level: Float = 0
    private(set) var dbfs: Float = LevelMeter.floorDBFS

    static func dbfs(rms: Float) -> Float {
        guard rms > 0 else { return floorDBFS }
        return max(floorDBFS, min(0, 20 * log10(rms)))
    }

    /// Maps dBFS in `floor...0` to `0...1`.
    static func normalized(dbfs: Float) -> Float {
        let clamped = max(floorDBFS, min(0, dbfs))
        return (clamped - floorDBFS) / -floorDBFS
    }

    @discardableResult
    mutating func update(rms: Float) -> Float {
        dbfs = Self.dbfs(rms: rms)
        let target = Self.normalized(dbfs: dbfs)
        let factor = target > level ? attack : release
        level += (target - level) * factor
        if level < 0.001 { level = 0 }
        return level
    }

    mutating func reset() {
        level = 0
        dbfs = Self.floorDBFS
    }
}
