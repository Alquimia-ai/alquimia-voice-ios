import Foundation

/// UI copy, centralized.
enum L10n {
    enum App {
        static let eyebrow = "Alquimia · Voice"
        static let newConversation = "New conversation"
        static let session = "Session"
        static let settings = "Settings"
        static let reconnect = "Reconnect"
    }

    enum Phase {
        static let idle = "Idle"
        static let connecting = "Connecting"
        static let listening = "Listening"
        static let userSpeaking = "Hearing you"
        static let recording = "Recording"
        static let thinking = "Thinking"
        static let speaking = "Speaking"
        static let ended = "Ended"
    }

    enum Actions {
        static let startCall = "Start conversation"
        static let endCall = "End"
        static let holdToTalk = "Hold to talk"
        static let mute = "Mute"
        static let unmute = "Unmute"
        static let testConnection = "Test connection"
        static let done = "Done"
        static let show = "Show"
        static let hide = "Hide"
    }

    enum Hints {
        static let noReply = "The agent did not reply. Still listening."
        static let noReplyPTT = "The agent did not reply. Try again."
        static let notHeard = "I didn't catch that. Hold the button and speak a little longer."
        static let holdToTalk = "Hold the button while you speak."
        static let waitingReply = "Waiting for the agent's reply…"
        static let closedWithCode = "Connection closed (code %d)."
        static let muted = "Microphone muted."
    }

    enum Ended {
        static let user = "Conversation ended."
        static let background = "The conversation ended when the app went to the background."
        static let interrupted = "The conversation ended because of an audio interruption."
        static let remote = "The server closed the connection"
        static let error = "Error"
    }

    enum Transcript {
        static let emptyEyebrow = "No messages"
        static let emptyBody = "The transcript of each turn appears here once the agent finishes speaking."
        static let you = "You"
        static let agent = "Agent"
        static let loading = "Updating…"
    }

    enum Settings {
        static let title = "Settings"
        static let runtimeSection = "Runtime"
        static let runtimeURL = "Runtime URL"
        static let runtimePlaceholder = "https://runtime.example.com"
        static let token = "Static token (optional, used when not signed in)"
        static let tokenPlaceholder = "API token or JWT"
        static let agentSection = "Agent"
        static let assistantID = "Assistant ID"
        static let assistantPlaceholder = "my-agent or space/agent:0.0.1"
        static let agentspaceID = "Agentspace"
        static let channelID = "Channel ID"
        static let voiceSection = "Voice"
        static let mode = "Mode"
        static let handsFree = "Hands-free"
        static let pushToTalk = "Push to talk"
        static let localBargeIn = "Cut playback when you speak"
        static let localBargeInHelp = "If you start talking while the agent is speaking, the app stops local playback. The server does not support interruptions yet."
        static let debugSection = "Local voice detection"
        static let activation = "Activation threshold"
        static let activationHelp = "The server uses −40 dBFS. This value only affects the on-screen “Thinking” state."
        static let invalidURL = "Enter a valid http:// or https:// URL."
        static let missingToken = "Sign in or paste a static token."
        static let missingAssistant = "Assistant id is missing."
        static let testing = "Testing…"
        static let testOK = "Connection and token are valid."
        static let testFailed = "Test failed: %@"
    }

    enum Auth {
        static let section = "Account"
        static let signIn = "Sign in with Alquimia"
        static let signOut = "Sign out"
        static let signedInAs = "Signed in as %@"
        static let tokenValidUntil = "Access token valid until %@; renewed automatically."
        static let openBrowser = "Open sign-in page"
        static let codeInstructions = "Open the sign-in page, enter this code and approve the access:"
        static let waiting = "Waiting for approval…"
        static let cancel = "Cancel"
        static let realmURL = "Keycloak realm URL"
        static let clientID = "Client ID"
        static let invalidRealm = "The Keycloak realm URL is not valid."
        static let denied = "The sign-in request was denied."
        static let codeExpired = "The sign-in code expired. Start again."
        static let sessionExpired = "The session expired. Sign in again."
        static let notSignedIn = "Sign in or paste a static token."
    }

    enum Errors {
        static let invalidURL = "The runtime URL is not valid."
        static let unauthorized = "The runtime rejected the token (HTTP %d)."
        static let handshake = "Could not open the WebSocket%@."
        static let transport = "Connection lost: %@"
        static let notConnected = "No active connection."
        static let microphoneDenied = "Microphone permission denied. Enable it in system Settings."
        static let noInput = "No audio input available."
        static let converter = "Could not set up the audio converter."
        static let engineStart = "Could not start the audio engine: %@"
        static let mediaReset = "The audio system was reset."
        static let badResponse = "Invalid response from the runtime."
        static let http = "The runtime responded with HTTP %d."
    }
}
