# Alquimia Voice (iOS)

SwiftUI proof of concept: talk to an Alquimia agent by voice through the runtime's live-audio WebSocket
(`/live/{assistant_id}/{channel_id}`). Two modes, hands-free and push to talk; the transcript shows up after
each reply. Styled after [DESIGN.md](https://www.alquimia.ai/DESIGN.md).

## Run it

Requirements: Xcode 26+ with an iOS 17+ simulator runtime, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
open AlquimiaVoice.xcodeproj          # pick an iPhone simulator and press ⌘R
xcodebuild test -scheme AlquimiaVoice -destination 'platform=iOS Simulator,name=iPhone 17'
```

On first launch the settings sheet asks for:

- **Runtime URL** (`https://…` becomes `wss://…`), **assistant id** (its spec needs an `audio` block) and agentspace.
- **Credentials**: *Sign in with Alquimia* (Keycloak device flow; tokens live in the Keychain and the app
  refreshes them by itself) or a static token for runtimes using `AUTH_PROVIDER=api_token`.

Use headphones with the simulator: it has no echo cancellation.

## Voice agent

The runtime needs an agent whose spec has an `audio` block (speech-to-text + text-to-speech). The configuration
verified end to end is in `tools/voice-agent.groq-kokoro.example.json`: Groq Whisper and `gpt-oss-20b`
(secret `GROQ_API_KEY`) plus a [Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI) deployment as an
OpenAI-compatible TTS (secrets `KOKORO_API_KEY`, `TTS_PROVIDER_BASE_URL`, `STT_PROVIDER_BASE_URL`). Register it
with `POST /registry/agent`.

## Tools

```bash
# Mock runtime (echoes each utterance back, fake transcript, same close codes)
uv run --with "websockets>=13" tools/mock_live_server.py --token dev --port 8080
# Probe a real runtime from the Mac; writes the reply to reply.wav
uv run --with "websockets>=13" tools/live_probe.py --url wss://host/live/agent/probe --token "$TOKEN" --stop
```

Debug builds accept `ALQUIMIA_RUNTIME_URL`, `ALQUIMIA_ASSISTANT_ID`, `ALQUIMIA_TOKEN`, `ALQUIMIA_REFRESH_TOKEN`,
`ALQUIMIA_MODE`, `ALQUIMIA_AUTOSTART=1` and `ALQUIMIA_AUTOPTT_SECONDS=<n>` from the environment
(`SIMCTL_CHILD_…` with `xcrun simctl launch`) for simulator automation.

## Protocol

Bearer token on the handshake. The client sends text frames `{"event":"audio","payload":"<base64 PCM s16le
16 kHz mono>"}` and `{"event":"stop"}`; the server answers with `{"event":"audio",…}` frames only, after its
own VAD closes the turn (700 ms of silence). The mic is never streamed while a reply plays.

## License

Apache License 2.0 ([LICENSE](LICENSE)). The Geist fonts are under the SIL Open Font License 1.1
(`AlquimiaVoice/Design/Fonts/OFL.txt`).
