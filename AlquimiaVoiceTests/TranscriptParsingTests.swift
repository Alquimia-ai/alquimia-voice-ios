import Foundation
import Testing
@testable import AlquimiaVoice

@Suite("Transcript parsing")
struct TranscriptParsingTests {
    @Test func parsesStringAndPartsContent() throws {
        let json = """
        {"messages": [
          {"role": "system", "content": "You are helpful."},
          {"role": "human", "content": "Hi, what can you do?"},
          {"role": "assistant", "content": [
             {"type": "text", "text": "I can help with your questions."},
             {"type": "image_url", "image_url": {"url": "x"}},
             {"type": "text", "text": "Where should we start?"}
          ], "tool_calls": []},
          {"role": "tool", "content": "{}", "tool_call_id": "1"},
          {"role": "human", "content": "   "},
          {"role": "assistant", "content": null}
        ], "blobs": [], "session_id": "ios-1", "user_id": "api-token"}
        """
        let messages = try TranscriptParser.messages(from: Data(json.utf8))
        #expect(messages.count == 2)
        #expect(messages[0].role == .user)
        #expect(messages[0].text == "Hi, what can you do?")
        #expect(messages[1].role == .assistant)
        #expect(messages[1].text == "I can help with your questions.\nWhere should we start?")
        #expect(messages[0].id != messages[1].id)
    }

    @Test func acceptsTypeInsteadOfRole() throws {
        let json = """
        {"messages": [{"type": "human", "content": "a"}, {"type": "ai", "content": "b"}]}
        """
        let messages = try TranscriptParser.messages(from: Data(json.utf8))
        #expect(messages.map(\.role) == [.user, .assistant])
    }

    @Test func emptyConversation() throws {
        #expect(try TranscriptParser.messages(from: Data("{\"messages\": []}".utf8)).isEmpty)
    }

    @Test func unknownContentShapeDoesNotFail() throws {
        let json = """
        {"messages": [{"role": "assistant", "content": {"weird": true}}, {"role": "human", "content": "ok"}]}
        """
        let messages = try TranscriptParser.messages(from: Data(json.utf8))
        #expect(messages.count == 1)
        #expect(messages[0].text == "ok")
    }
}
