#!/usr/bin/env python3
"""Mock of the Alquimia runtime's live-audio endpoint, for developing the iOS client without a runtime.

    uv run --with "websockets>=13" tools/mock_live_server.py --token dev --port 8080

Behaviour mirrors alquimia-runtime/runtime/src/routers/live.py:
  * WS  /live/{assistant_id}/{channel_id}?agentspace_id=&session_id=   (bearer header or ?token=)
  * text frames {"event":"audio","payload":<b64 pcm s16le 16k mono>} and {"event":"stop"}
  * energy VAD: 30 ms frames, activation 0.01, min speech 250 ms, silence 700 ms, max utterance 10 s
  * each utterance is "answered" after --reply-delay by echoing it back as a burst of 20 ms frames
  * binary frames close 1011; after "stop" the pending utterance is flushed, answered, then close 1000
  * GET /context/retrieve on the same port returns the fake history for the `sessionid` header
Switches: --silent (never reply), --clear-after-ms N (send {"event":"clear"} mid-burst), --max-sessions,
--session-ttl, --gain, --delay-close-ms.
"""
from __future__ import annotations

import argparse
import asyncio
import base64
import json
import math
import struct
import sys
import time
from collections import defaultdict
from http import HTTPStatus
from urllib.parse import parse_qs, urlsplit

from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

FRAME_MS = 30
FRAME_SAMPLES = 16_000 * FRAME_MS // 1000
FRAME_BYTES = FRAME_SAMPLES * 2
REPLY_FRAME_BYTES = 640  # 20 ms at 16 kHz s16le


class Segmenter:
    """Port of alquimia-core's EnergyVADTurnSegmenter (same semantics as the runtime defaults)."""

    def __init__(self, activation=0.01, min_speech_ms=250, silence_ms=700, max_utterance_ms=10_000):
        self.activation = activation
        self.min_speech_ms = min_speech_ms
        self.silence_ms = silence_ms
        self.max_utterance_ms = max_utterance_ms
        self.buffer = bytearray()
        self.elapsed_ms = 0
        self.speech_start_ms: int | None = None
        self.last_speech_end_ms: int | None = None
        self.frames: list[bytes] = []
        self.max_rms = 0.0

    @staticmethod
    def rms(frame: bytes) -> float:
        samples = struct.unpack(f"<{len(frame) // 2}h", frame)
        if not samples:
            return 0.0
        return math.sqrt(sum(s * s for s in samples) / len(samples)) / 32768

    def feed(self, pcm: bytes) -> list[bytes]:
        self.buffer.extend(pcm)
        utterances: list[bytes] = []
        while len(self.buffer) >= FRAME_BYTES:
            frame = bytes(self.buffer[:FRAME_BYTES])
            del self.buffer[:FRAME_BYTES]
            utterance = self._process(frame)
            if utterance:
                utterances.append(utterance)
        return utterances

    def _process(self, frame: bytes) -> bytes | None:
        frame_start = self.elapsed_ms
        self.elapsed_ms += FRAME_MS
        level = self.rms(frame)
        self.max_rms = max(self.max_rms, level)
        if level > self.activation:
            if self.speech_start_ms is None:
                self.speech_start_ms = frame_start
                self.frames = []
            self.last_speech_end_ms = self.elapsed_ms
        if self.speech_start_ms is not None:
            self.frames.append(frame)
            silence = self.elapsed_ms - self.last_speech_end_ms
            utterance_ms = self.elapsed_ms - self.speech_start_ms
            if silence >= self.silence_ms or utterance_ms >= self.max_utterance_ms:
                return self._finish()
        return None

    def _finish(self) -> bytes | None:
        span = (self.last_speech_end_ms or 0) - (self.speech_start_ms or 0)
        frames, self.frames = self.frames, []
        self.speech_start_ms = None
        self.last_speech_end_ms = None
        if span < self.min_speech_ms:
            return None
        return b"".join(frames)

    def flush(self) -> bytes | None:
        if self.speech_start_ms is None:
            return None
        return self._finish()


def apply_gain(pcm: bytes, gain: float) -> bytes:
    if gain == 1.0:
        return pcm
    samples = struct.unpack(f"<{len(pcm) // 2}h", pcm)
    scaled = [max(-32768, min(32767, int(s * gain))) for s in samples]
    return struct.pack(f"<{len(scaled)}h", *scaled)


class MockRuntime:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.history: dict[str, list[dict]] = defaultdict(list)
        self.turns: dict[str, int] = defaultdict(int)
        self.sessions_per_source: dict[str, int] = defaultdict(int)

    # ---- HTTP + handshake -------------------------------------------------
    def authorized(self, headers, query: dict[str, list[str]]) -> bool:
        auth = headers.get("Authorization", "")
        if auth.lower().startswith("bearer "):
            return auth.split(" ", 1)[1] == self.args.token
        return query.get("token", [None])[0] == self.args.token

    def process_request(self, connection, request):
        parts = urlsplit(request.path)
        query = parse_qs(parts.query)
        if parts.path.startswith("/context/retrieve"):
            if not self.authorized(request.headers, query):
                return connection.respond(HTTPStatus.UNAUTHORIZED, "Missing authentication token\n")
            session_id = request.headers.get("sessionid", "")
            body = json.dumps({
                "messages": self.history.get(session_id, []),
                "blobs": [],
                "session_id": session_id,
                "user_id": "api-token",
            })
            response = connection.respond(HTTPStatus.OK, body)
            response.headers["Content-Type"] = "application/json"
            print(f"[http] context/retrieve session={session_id} messages={len(self.history.get(session_id, []))}")
            return response
        if parts.path == "/health":
            return connection.respond(HTTPStatus.OK, "ok\n")
        if parts.path.startswith("/live/"):
            if not self.authorized(request.headers, query):
                print(f"[ws] rejected {parts.path}: bad token")
                return connection.respond(HTTPStatus.UNAUTHORIZED, "Missing authentication token\n")
            return None  # continue with the WebSocket handshake
        return connection.respond(HTTPStatus.NOT_FOUND, "not found\n")

    # ---- WebSocket --------------------------------------------------------
    async def handler(self, websocket):
        request = websocket.request
        parts = urlsplit(request.path)
        query = parse_qs(parts.query)
        segments = parts.path.split("/")  # ['', 'live', assistant..., channel]
        channel_id = segments[-1]
        assistant_id = "/".join(segments[2:-1])
        session_id = query.get("session_id", [f"browser-{int(time.time() * 1000):x}"])[0]
        source = websocket.remote_address[0] if websocket.remote_address else "?"
        key = f"{channel_id}:{source}"
        print(f"[ws] open assistant={assistant_id} channel={channel_id} session={session_id} from={source}")

        if assistant_id == "noaudio":
            await websocket.close(1008, f"Assistant {assistant_id} has no audio configuration")
            return
        if self.sessions_per_source[key] >= self.args.max_sessions:
            await websocket.close(1008, "Streaming session rate limit exceeded")
            return

        self.sessions_per_source[key] += 1
        segmenter = Segmenter()
        frames_in = 0
        started = time.monotonic()
        try:
            async with asyncio.timeout(self.args.session_ttl):
                async for message in websocket:
                    if isinstance(message, bytes):
                        await websocket.close(1011, "Internal server error")
                        return
                    try:
                        envelope = json.loads(message)
                    except json.JSONDecodeError:
                        continue
                    event = envelope.get("event") if isinstance(envelope, dict) else None
                    if event == "audio":
                        payload = envelope.get("payload") or ""
                        if not payload:
                            continue
                        try:
                            pcm = base64.b64decode(payload)
                        except (ValueError, TypeError):
                            continue
                        frames_in += 1
                        for utterance in segmenter.feed(pcm):
                            await self.answer(websocket, session_id, utterance)
                    elif event == "stop":
                        print(f"[ws] stop session={session_id}")
                        tail = segmenter.flush()
                        if tail:
                            await self.answer(websocket, session_id, tail)
                        if self.args.delay_close_ms:
                            await asyncio.sleep(self.args.delay_close_ms / 1000)
                        return
        except TimeoutError:
            await websocket.close(1008, "Streaming session lifetime exceeded")
        except ConnectionClosed as exc:
            print(f"[ws] client closed session={session_id} code={exc.code}")
        finally:
            self.sessions_per_source[key] -= 1
            print(
                f"[ws] end session={session_id} frames_in={frames_in} max_rms={segmenter.max_rms:.4f} "
                f"({20 * math.log10(segmenter.max_rms) if segmenter.max_rms else -99:.1f} dBFS) "
                f"duration={time.monotonic() - started:.1f}s"
            )

    async def answer(self, websocket, session_id: str, utterance: bytes):
        seconds = len(utterance) / 32_000
        self.turns[session_id] += 1
        turn = self.turns[session_id]
        print(f"[turn] session={session_id} #{turn} utterance={seconds:.2f}s")
        if self.args.silent:
            return
        await asyncio.sleep(self.args.reply_delay)
        self.history[session_id].append({"role": "human", "content": f"(user audio, turn {turn}, {seconds:.1f} s)"})
        self.history[session_id].append({
            "role": "assistant",
            "content": [{"type": "text", "text": f"Echo of turn {turn}. I heard you for {seconds:.1f} seconds."}],
        })
        reply = apply_gain(utterance, self.args.gain)
        sent_ms = 0
        for offset in range(0, len(reply), REPLY_FRAME_BYTES):
            frame = reply[offset:offset + REPLY_FRAME_BYTES]
            await websocket.send(json.dumps({"event": "audio", "payload": base64.b64encode(frame).decode("ascii")}))
            sent_ms += 20
            if self.args.clear_after_ms and sent_ms >= self.args.clear_after_ms:
                await websocket.send(json.dumps({"event": "clear"}))
                print(f"[turn] session={session_id} sent clear after {sent_ms} ms")
                break
        print(f"[turn] session={session_id} #{turn} replied {sent_ms} ms of audio")


def main():
    sys.stdout.reconfigure(line_buffering=True)
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--token", default="dev")
    parser.add_argument("--reply-delay", type=float, default=1.0, help="seconds between end of turn and reply")
    parser.add_argument("--gain", type=float, default=0.8)
    parser.add_argument("--silent", action="store_true")
    parser.add_argument("--clear-after-ms", type=int, default=0)
    parser.add_argument("--max-sessions", type=int, default=10)
    parser.add_argument("--session-ttl", type=int, default=3600)
    parser.add_argument("--delay-close-ms", type=int, default=0)
    args = parser.parse_args()

    runtime = MockRuntime(args)

    async def run():
        async with serve(runtime.handler, args.host, args.port, process_request=runtime.process_request, max_size=2**22):
            print(f"mock runtime on ws://{args.host}:{args.port}/live/<assistant>/<channel>  token={args.token}")
            await asyncio.Future()

    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
