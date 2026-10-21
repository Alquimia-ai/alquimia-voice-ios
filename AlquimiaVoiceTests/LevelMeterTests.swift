import Testing
@testable import AlquimiaVoice

@Suite("Level meter")
struct LevelMeterTests {
    @Test func dbfsMapping() {
        #expect(LevelMeter.dbfs(rms: 0) == LevelMeter.floorDBFS)
        #expect(abs(LevelMeter.dbfs(rms: 0.01) - (-40)) < 0.01)
        #expect(LevelMeter.dbfs(rms: 1) == 0)
        #expect(LevelMeter.dbfs(rms: 2) == 0)
    }

    @Test func normalisedRange() {
        #expect(LevelMeter.normalized(dbfs: -60) == 0)
        #expect(LevelMeter.normalized(dbfs: 0) == 1)
        #expect(abs(LevelMeter.normalized(dbfs: -40) - 0.3333) < 0.001)
    }

    @Test func attackIsFasterThanRelease() {
        var meter = LevelMeter()
        let up = meter.update(rms: 1)
        #expect(up > 0.5)
        let afterOne = meter.update(rms: 0)
        #expect(afterOne > 0.4)
        #expect(afterOne < up)
    }
}
