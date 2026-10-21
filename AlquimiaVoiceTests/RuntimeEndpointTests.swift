import Foundation
import Testing
@testable import AlquimiaVoice

@Suite("Runtime endpoint URLs")
struct RuntimeEndpointTests {
    @Test func httpBecomesWs() throws {
        let endpoint = try #require(RuntimeEndpoint(string: "http://localhost:8080"))
        let url = endpoint.liveURL(assistantID: "mock", channelID: "default", agentspaceID: "default", sessionID: "ios-1")
        #expect(url.absoluteString == "ws://localhost:8080/live/mock/default?agentspace_id=default&session_id=ios-1")
    }

    @Test func httpsBecomesWssAndKeepsPrefix() throws {
        let endpoint = try #require(RuntimeEndpoint(string: "https://runtime.example.com/prefix/"))
        let url = endpoint.liveURL(assistantID: "agent", channelID: "ios-abc", agentspaceID: "sales", sessionID: "s.1:2-3")
        #expect(url.absoluteString == "wss://runtime.example.com/prefix/live/agent/ios-abc?agentspace_id=sales&session_id=s.1:2-3")
    }

    @Test func versionedAssistantKeepsSlashesAndColon() throws {
        let endpoint = try #require(RuntimeEndpoint(string: "http://10.0.0.5:8080"))
        let url = endpoint.liveURL(assistantID: "space/agent:0.0.1", channelID: "default", agentspaceID: "default", sessionID: "x")
        #expect(url.path == "/live/space/agent:0.0.1/default")
        #expect(url.absoluteString.contains("/live/space/agent:0.0.1/default?"))
    }

    @Test func unsafeCharactersArePercentEncoded() throws {
        let endpoint = try #require(RuntimeEndpoint(string: "http://host"))
        let url = endpoint.liveURL(assistantID: "mi agente", channelID: "canal ñ", agentspaceID: "a b", sessionID: "s")
        #expect(url.absoluteString == "ws://host/live/mi%20agente/canal%20%C3%B1?agentspace_id=a%20b&session_id=s")
    }

    @Test func contextRetrieveURL() throws {
        let endpoint = try #require(RuntimeEndpoint(string: "https://runtime.example.com"))
        #expect(endpoint.contextRetrieveURL().absoluteString == "https://runtime.example.com/context/retrieve?limit=0&offset=-1")
        #expect(endpoint.contextRetrieveURL(limit: 50, offset: 0).absoluteString == "https://runtime.example.com/context/retrieve?limit=50&offset=0")
    }

    @Test func rejectsInvalidBaseURLs() {
        #expect(RuntimeEndpoint(string: "") == nil)
        #expect(RuntimeEndpoint(string: "localhost:8080") == nil)
        #expect(RuntimeEndpoint(string: "ftp://host") == nil)
        #expect(RuntimeEndpoint(string: "ws://host") == nil)
        #expect(RuntimeEndpoint(string: "  https://host/  ")?.baseURL.absoluteString == "https://host")
        #expect(RuntimeEndpoint(string: "HTTP://Host:8080/?x=1#f")?.baseURL.absoluteString == "http://Host:8080")
    }

    @Test func liveRequestCarriesBearerHeader() throws {
        let endpoint = try #require(RuntimeEndpoint(string: "http://localhost:8080"))
        let url = endpoint.liveURL(assistantID: "a", channelID: "c", agentspaceID: "d", sessionID: "s")
        let request = RuntimeRequests.live(url: url, token: "secret")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.url == url)
    }

    @Test func contextRequestCarriesIdentityHeaders() throws {
        let endpoint = try #require(RuntimeEndpoint(string: "http://localhost:8080"))
        let request = RuntimeRequests.contextRetrieve(
            endpoint: endpoint, token: "t", sessionID: "sess", assistantID: "agent", agentspaceID: "space"
        )
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        #expect(request.value(forHTTPHeaderField: "sessionid") == "sess")
        #expect(request.value(forHTTPHeaderField: "assistantid") == "agent")
        #expect(request.value(forHTTPHeaderField: "agentspaceid") == "space")
    }
}
