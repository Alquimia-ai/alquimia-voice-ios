# Alquimia Voice (iOS proof of concept)

Native SwiftUI app that talks to an Alquimia agent by voice through the runtime's live-audio WebSocket
(`/live/{assistant_id}/{channel_id}`, the `browser-media-stream` protocol). Two interaction modes:

- **Manos libres** – one socket per call, the server's energy VAD segments turns, the mic is gated while the
  reply plays.
- **Mantener para hablar** – hold the button, release to send `stop`; one socket per turn, same `session_id`.

The transcript shown under the call is fetched from `GET /context/retrieve` after each reply (the socket itself
carries audio only). Styling follows https://www.alquimia.ai/DESIGN.md (Geist, canvas `#FAFAF7`, ember accent,
hairlines instead of shadows).

## Requirements

- Xcode 26/27 with the iOS 17+ simulator runtime. One-time setup if `xcodebuild` complains:
  ```bash
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept
  xcodebuild -downloadPlatform iOS
  ```
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- `uv` (only for the mock server)

## Build and test

```bash
xcodegen generate                      # writes AlquimiaVoice.xcodeproj from project.yml
open AlquimiaVoice.xcodeproj           # or:
xcodebuild test -scheme AlquimiaVoice -destination 'platform=iOS Simulator,name=iPhone 17'
```

The unit tests use Swift Testing and need no audio hardware (envelope encoding, PCM helpers, the local VAD,
`AVAudioConverter` resampling, URL building, the call reducer for both modes, transcript parsing).

## Configure

On first launch the settings sheet opens. Fill in:

| Field | Value |
|---|---|
| URL del runtime | `https://runtime.example.com` or `http://localhost:8080` (scheme decides `wss`/`ws`) |
| Token | the runtime's `API_TOKEN`, or a JWT/Keycloak access token |
| Assistant ID | an agent whose spec has an `audio` block (`stt` + `tts`, modalities include `audio`) |
| Agentspace | `default` unless the agent lives elsewhere |
| Channel ID | free-form; a per-device id keeps the per-IP session limit separate |

"Probar conexión" issues a `context/retrieve` for the current session and reports auth problems.

An audio-enabled agent spec example (from `alquimia-runtime/README.md`): `openai/transcribe` +
`openai/tts` pointed at the local speech container, or `elevenlabs/stt` + `elevenlabs/tts`.

## Mock server

Run the app against a protocol-exact mock when no runtime is available:

```bash
uv run --with "websockets>=13" tools/mock_live_server.py --token dev --port 8080
```

Then point the app at `http://localhost:8080`, token `dev`, assistant `mock`. The mock answers each utterance by
echoing it back one second later as a burst of 20 ms frames, keeps a fake transcript per session, enforces the
same close codes (1008/1011) and exposes switches to exercise edge cases (`--silent`, `--clear-after-ms`,
`--max-sessions`, `--session-ttl`). Use headphones on the Mac: the Simulator has no echo cancellation.

## Probe a runtime from the Mac

`tools/live_probe.py` speaks the same protocol as the app. Use it to confirm URL, token and assistant before
running the app against a real runtime (it writes the reply to `reply.wav`):

```bash
uv run --with "websockets>=13" tools/live_probe.py \
  --url wss://runtime.example.com/live/my-agent/ios-probe --token "$API_TOKEN" --tone-seconds 1 --stop
uv run --with "websockets>=13" tools/live_probe.py \
  --url ws://localhost:8080/live/mock/default --token dev --wav hola.wav --stop --out reply.wav
```

`--stop` behaves like push-to-talk; without it the probe keeps sending silence so the server VAD closes the turn.

## Simulator automation (Debug builds)

Debug builds read `ALQUIMIA_RUNTIME_URL`, `ALQUIMIA_TOKEN`, `ALQUIMIA_ASSISTANT_ID`, `ALQUIMIA_AGENTSPACE_ID`,
`ALQUIMIA_MODE` (`handsFree` | `pushToTalk`) and `ALQUIMIA_AUTOSTART=1` from the environment, so a simulator
can be launched pre-configured and already in a call:

```bash
xcrun simctl privacy booted grant microphone ai.alquimia.voice
SIMCTL_CHILD_ALQUIMIA_RUNTIME_URL=http://localhost:8080 SIMCTL_CHILD_ALQUIMIA_TOKEN=dev \
SIMCTL_CHILD_ALQUIMIA_ASSISTANT_ID=mock SIMCTL_CHILD_ALQUIMIA_AUTOSTART=1 \
xcrun simctl launch booted ai.alquimia.voice
xcrun simctl spawn booted log stream --predicate 'subsystem == "ai.alquimia.voice"' --style compact
```

## Protocol notes (verified against `alquimia-runtime` `develop`)

- Auth: `Authorization: Bearer <token>` header (or `?token=`). A bad token fails the HTTP handshake (401/403).
- Client → server, text frames only: `{"event":"audio","payload":"<base64 PCM s16le 16 kHz mono>"}`,
  `{"event":"stop"}`.
- Server → client: `{"event":"audio","payload":…}` as unpaced 20 ms frames. No transcript/status events.
  A future `{"event":"clear"}` is handled (flushes playback).
- Server VAD: 30 ms frames, activation 0.01 (≈ −40 dBFS), min speech 250 ms, trailing silence 700 ms,
  max utterance 10 s. Processing is sequential, so the client never streams the mic while the reply plays.
- `session_id` must match `[A-Za-z0-9._:-]{1,128}`; the app generates `ios-<uuid>` and reuses it until
  "Nueva conversación".
- Limits: 10 concurrent sessions per `(channel_id, source IP)`, 3600 s per session (close 1008).

## Layout

```
AlquimiaVoice/
  App/          entry point, root view
  Design/       tokens (Theme.swift), bundled Geist fonts (OFL)
  Components/   eyebrow, hairline card, buttons, shimmer, status badge, level meter, hold-to-talk, bubbles
  Features/
    Call/       CallState + CallReducer (pure), CallSession (coordinator), CallView, VoiceDock
    Transcript/ /context/retrieve client + models, TranscriptView
    Settings/   SettingsStore (UserDefaults + Keychain), SettingsView
  Audio/        AVAudioEngine controller, capture (AVAudioConverter → 16 kHz Int16), local VAD, playback queue
  Networking/   RuntimeEndpoint (URL building), LiveConnection (URLSessionWebSocketTask actor), envelopes
  Support/      logging, Keychain, session ids, strings
AlquimiaVoiceTests/   Swift Testing suites
tools/                mock_live_server.py, icon renderer
```

## Known limitations

- No live transcript: text appears after each reply via `/context/retrieve`.
- Barge-in depends on the server; locally the app can only cut playback (toggle in settings, device + AEC only).
- Tokens are pasted, never refreshed.
- Background audio is not enabled; backgrounding ends the call cleanly.

## License

Apache License 2.0. See [LICENSE](LICENSE). The bundled Geist fonts are licensed separately under the SIL Open Font License 1.1 (`AlquimiaVoice/Design/Fonts/OFL.txt`).
