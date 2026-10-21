import Foundation

/// Events the app derives from the `/live` socket.
enum LiveEvent: Equatable, Sendable {
    /// Reply audio: PCM s16le, 16 kHz, mono (already decoded from base64).
    case audio([Int16])
    /// Future barge-in signal: drop queued playback.
    case clear
    /// Any other event name; logged and ignored.
    case unknown(String)
    /// The peer closed the socket.
    case closed(code: Int, reason: String?)
}

struct ClientEnvelope: Codable, Equatable, Sendable {
    var event: String
    var payload: String?
}

struct ServerEnvelope: Decodable, Equatable, Sendable {
    var event: String
    var payload: String?
}

/// Wire encoding for the browser-media-stream protocol: JSON text frames with a base64 PCM payload.
enum LiveWire {
    static let stopMessage = #"{"event":"stop"}"#

    /// Hand-built on purpose: base64 contains no JSON-special characters and this runs 25 times per second.
    static func audioMessage(_ samples: [Int16]) -> String {
        #"{"event":"audio","payload":""# + PCM.data(from: samples).base64EncodedString() + #""}"#
    }

    /// Returns `nil` for malformed JSON or an audio frame with no usable payload (both are ignored by the server too).
    static func decode(_ text: String) -> LiveEvent? {
        guard let data = text.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(ServerEnvelope.self, from: data)
        else { return nil }
        switch envelope.event {
        case "audio":
            guard let payload = envelope.payload, !payload.isEmpty,
                  let bytes = Data(base64Encoded: payload)
            else { return nil }
            return .audio(PCM.samples(from: bytes))
        case "clear":
            return .clear
        default:
            return .unknown(envelope.event)
        }
    }
}
