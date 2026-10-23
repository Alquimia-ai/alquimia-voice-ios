# Alquimia Voice (iOS)

Proof-of-concept SwiftUI app that talks to an Alquimia agent by voice through the runtime's live-audio
WebSocket (`/live/{assistant_id}/{channel_id}`). Two modes: **hands-free** (one socket per call, the server's
VAD segments turns) and **push to talk** (hold to speak, release to send `stop`). The transcript is fetched
from `GET /context/retrieve` after each reply. Styling follows [DESIGN.md](https://www.alquimia.ai/DESIGN.md).

## Requirements

- Xcode 26+ with an iOS 17+ simulator runtime (`xcodebuild -downloadPlatform iOS`)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- `uv` for the Python tools

## Build and test

```bash
xcodegen generate
xcodebuild test -scheme AlquimiaVoice -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Configure

The settings sheet asks for the runtime URL (`http`/`https` decides `ws`/`wss`), a bearer token, the assistant
id (its spec must have an `audio` block), the agentspace (`default`) and a channel id (any value; one per
device keeps the per-IP session limit separate). "Test connection" validates URL and token.

## Tools

```bash
# Protocol-exact mock of the runtime (echoes each utterance back, fake transcript, same close codes)
uv run --with "websockets>=13" tools/mock_live_server.py --token dev --port 8080

# Probe any runtime from the Mac before using the app (writes the reply to reply.wav)
uv run --with "websockets>=13" tools/live_probe.py --url wss://host/live/agent/probe --token "$TOKEN" --stop
```

Point the app at `http://localhost:8080`, token `dev`, assistant `mock` to use the mock.
`tools/voice-agent.example.json` is a minimal audio-enabled agent spec (`openai/transcribe` + `openai/tts`) for a
runtime with an `OPENAI_API_KEY` secret. `tools/voice-agent.groq-kokoro.example.json` is the configuration verified
end to end: Groq Whisper for STT and Groq `gpt-oss-20b` for the reply (secret `GROQ_API_KEY`), and a
[Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI) deployment as an OpenAI-compatible TTS (secrets
`KOKORO_API_KEY`, `TTS_PROVIDER_BASE_URL`, `STT_PROVIDER_BASE_URL`). Register with `POST /registry/agent`. Use headphones on the
Mac: the Simulator has no echo cancellation.

Debug builds also read `ALQUIMIA_RUNTIME_URL`, `ALQUIMIA_TOKEN`, `ALQUIMIA_ASSISTANT_ID`, `ALQUIMIA_MODE`
(`handsFree` | `pushToTalk`), `ALQUIMIA_AUTOSTART=1` (start a hands-free call) and `ALQUIMIA_AUTOPTT_SECONDS=<n>`
(press, hold n seconds and release the push-to-talk control) from the environment
(`SIMCTL_CHILD_… xcrun simctl launch booted ai.alquimia.voice`).

## Protocol notes

- Auth: `Authorization: Bearer <token>`; a bad token fails the handshake with 401/403.
- Client → server (text frames): `{"event":"audio","payload":"<base64 PCM s16le 16 kHz mono>"}`, `{"event":"stop"}`.
- Server → client: `{"event":"audio",…}` as unpaced 20 ms frames; no transcript or status events.
  `{"event":"clear"}` is handled if a future runtime sends it.
- Server VAD: 30 ms frames, activation ≈ −40 dBFS, min speech 250 ms, trailing silence 700 ms, max 10 s.
  Processing is sequential, so the app never streams the mic while a reply plays.
- Limits: 10 sessions per `(channel_id, IP)`, 3600 s per session (close 1008).

## Layout

`AlquimiaVoice/` — `App`, `Design` (tokens, Geist fonts), `Components`, `Features` (`Call`, `Transcript`,
`Settings`), `Audio` (engine, capture, local VAD, playback), `Networking` (endpoint, WebSocket actor),
`Support`. `AlquimiaVoiceTests/` holds the Swift Testing suites; `tools/` the mock server and probe.

## License

Apache License 2.0 ([LICENSE](LICENSE)). The bundled Geist fonts are under the SIL Open Font License 1.1
(`AlquimiaVoice/Design/Fonts/OFL.txt`).
