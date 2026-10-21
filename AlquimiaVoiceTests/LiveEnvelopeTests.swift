import Foundation
import Testing
@testable import AlquimiaVoice

@Suite("Live envelope")
struct LiveEnvelopeTests {
    @Test func audioMessageMatchesWireFormatAndRoundTrips() throws {
        let samples: [Int16] = [0, 1, -1, 32767, -32768, 258]
        let text = LiveWire.audioMessage(samples)
        let expected = "{\"event\":\"audio\",\"payload\":\"" + PCM.data(from: samples).base64EncodedString() + "\"}"
        #expect(text == expected)

        let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: String]
        #expect(object?["event"] == "audio")
        #expect(LiveWire.decode(text) == .audio(samples))
    }

    @Test func samplesAreLittleEndian() {
        let data = PCM.data(from: [0x0102])
        #expect(Array(data) == [0x02, 0x01])
    }

    @Test func stopMessage() {
        #expect(LiveWire.stopMessage == "{\"event\":\"stop\"}")
    }

    @Test func decodesTwentyMillisecondFrame() {
        let samples = (0..<320).map { Int16($0 - 160) }
        let payload = PCM.data(from: samples).base64EncodedString()
        #expect(payload.hasSuffix("=") || payload.count % 4 == 0)
        let event = LiveWire.decode("{\"event\": \"audio\", \"payload\": \"\(payload)\"}")
        #expect(event == .audio(samples))
    }

    @Test func decodesClearAndUnknown() {
        #expect(LiveWire.decode("{\"event\":\"clear\"}") == .clear)
        #expect(LiveWire.decode("{\"event\":\"transcript\",\"payload\":\"hola\"}") == .unknown("transcript"))
    }

    @Test func ignoresMalformedAndEmpty() {
        #expect(LiveWire.decode("not json") == nil)
        #expect(LiveWire.decode("{\"payload\":\"AAA=\"}") == nil)
        #expect(LiveWire.decode("{\"event\":\"audio\"}") == nil)
        #expect(LiveWire.decode("{\"event\":\"audio\",\"payload\":\"\"}") == nil)
        #expect(LiveWire.decode("{\"event\":\"audio\",\"payload\":\"***\"}") == nil)
    }

    @Test func oddPayloadLengthDropsTrailingByte() {
        let payload = Data([0x01, 0x02, 0x03]).base64EncodedString()
        #expect(LiveWire.decode("{\"event\":\"audio\",\"payload\":\"\(payload)\"}") == .audio([0x0201]))
    }
}
