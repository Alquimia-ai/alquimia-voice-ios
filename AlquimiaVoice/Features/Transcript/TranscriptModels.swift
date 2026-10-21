import Foundation

struct TranscriptMessage: Identifiable, Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case user
        case assistant
    }

    let id: Int
    let role: Role
    let text: String
}

/// Shape of `GET /context/retrieve`. `content` is either a string or an array of content parts.
struct ConversationResponse: Decodable {
    struct Message: Decodable {
        var role: String?
        var type: String?
        var content: Content?
    }

    struct Part: Decodable {
        var type: String?
        var text: String?
    }

    enum Content: Decodable {
        case text(String)
        case parts([Part])

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .text("")
            } else if let text = try? container.decode(String.self) {
                self = .text(text)
            } else if let parts = try? container.decode([Part].self) {
                self = .parts(parts)
            } else {
                // Unknown shape: keep going with no text rather than failing the whole transcript.
                self = .text("")
            }
        }

        var text: String {
            switch self {
            case .text(let value):
                return value
            case .parts(let parts):
                return parts
                    .filter { ($0.type ?? "text") == "text" }
                    .compactMap(\.text)
                    .joined(separator: "\n")
            }
        }
    }

    var messages: [Message]
    var sessionID: String?

    enum CodingKeys: String, CodingKey {
        case messages
        case sessionID = "session_id"
    }
}

enum TranscriptParser {
    static func messages(from data: Data) throws -> [TranscriptMessage] {
        let response = try JSONDecoder().decode(ConversationResponse.self, from: data)
        var result: [TranscriptMessage] = []
        for (index, message) in response.messages.enumerated() {
            let roleName = (message.role ?? message.type ?? "").lowercased()
            let role: TranscriptMessage.Role
            switch roleName {
            case "human", "user": role = .user
            case "assistant", "ai": role = .assistant
            default: continue
            }
            let text = (message.content?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            result.append(TranscriptMessage(id: index, role: role, text: text))
        }
        return result
    }
}
