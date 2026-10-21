#!/usr/bin/env python3
"""Protocol probe for the runtime's /live endpoint (works against the mock and a real runtime).

Sends a tone or a WAV file as 40 ms base64 PCM frames, paced in real time like the app, then waits for the
reply burst and writes it to a WAV file. Use it to check URL/token/assistant before touching the iOS app.

    uv run --with "websockets>=13" tools/live_probe.py \
        --url wss://runtime.example.com/live/my-agent/ios-probe --token "$API_TOKEN" --tone-seconds 1.0
    uv run --with "websockets>=13" tools/live_probe.py --url ws://localhost:8080/live/mock/default \
        --token dev --wav hola.wav --stop --out reply.wav

--stop mimics push-to-talk (send {"event":"stop"} after the audio and wait for the close). Without it the
probe behaves like hands-free: it keeps sending silence so the server's VAD can close the turn.
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
import wave
from urllib.parse import urlencode, urlsplit, urlunsplit

from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed, InvalidStatus

CHUNK_MS = 40
CHUNK_BYTES = CHUNK_MS * 32


def tone(seconds: float, frequency: float = 440.0, amplitude: float = 0.3) -> bytes:
    count = int(16_000 * seconds)
    samples = [int(math.sin(2 * math.pi * frequency * i / 16_000) * amplitude * 32767) for i in range(count)]
    return struct.pack(f"<{count}h", *samples)


def load_wav(path: str) -> bytes:
    with wave.open(path, "rb") as wav:
        if wav.getsampwidth() != 2:
            sys.exit("WAV must be 16-bit PCM")
        channels, rate = wav.getnchannels(), wav.getframerate()
        frames = wav.readframes(wav.getnframes())
    samples = list(struct.unpack(f"<{len(frames) // 2}h", frames))
    if channels > 1:
        samples = samples[::channels]
    if rate != 16_000:
        ratio = rate / 16_000
        samples = [samples[min(int(i * ratio), len(samples) - 1)] for i in range(int(len(samples) / ratio))]
        print(f"resampled {rate} Hz → 16 kHz (nearest neighbour)")
    return struct.pack(f"<{len(samples)}h", *samples)


def save_wav(path: str, pcm: bytes) -> None:
    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(16_000)
        wav.writeframes(pcm)


async def run(args: argparse.Namespace) -> int:
    parts = urlsplit(args.url)
    query = dict(q.split("=", 1) for q in parts.query.split("&") if q)
    query.setdefault("agentspace_id", args.agentspace)
    query.setdefault("session_id", args.session or f"probe-{int(time.time())}")
    url = urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(query), ""))
    headers = {"Authorization": f"Bearer {args.token}"} if args.token else {}
    audio = load_wav(args.wav) if args.wav else tone(args.tone_seconds)
    print(f"connecting {url}")
    try:
        async with connect(url, additional_headers=headers, max_size=2**22) as ws:
            print("open; streaming", len(audio) / 32_000, "s of audio")
            reply = bytearray()
            first_frame_at: float | None = None
            last_frame_at: float | None = None
            done = asyncio.Event()

            async def receiver():
                nonlocal first_frame_at, last_frame_at
                try:
                    async for message in ws:
                        if isinstance(message, bytes):
                            continue
                        envelope = json.loads(message)
                        event = envelope.get("event")
                        if event == "audio":
                            now = time.monotonic()
                            if first_frame_at is None:
                                first_frame_at = now
                                print(f"first reply frame after {now - sent_at:.2f} s")
                            last_frame_at = now
                            reply.extend(base64.b64decode(envelope.get("payload", "")))
                        else:
                            print("event:", envelope)
                except ConnectionClosed as exc:
                    print(f"closed by server: code={exc.code} reason={exc.reason!r}")
                finally:
                    done.set()

            receiver_task = asyncio.create_task(receiver())
            start = time.monotonic()
            sent_at = start
            try:
                for index, offset in enumerate(range(0, len(audio), CHUNK_BYTES)):
                    chunk = audio[offset:offset + CHUNK_BYTES]
                    await ws.send(json.dumps({"event": "audio", "payload": base64.b64encode(chunk).decode("ascii")}))
                    await asyncio.sleep(max(0, start + (index + 1) * CHUNK_MS / 1000 - time.monotonic()))
                sent_at = time.monotonic()
                if args.stop:
                    await ws.send(json.dumps({"event": "stop"}))
                    print("sent stop; waiting for reply and close")
                    try:
                        await asyncio.wait_for(done.wait(), timeout=args.timeout)
                    except asyncio.TimeoutError:
                        print("timeout waiting for close")
                else:
                    # Hands-free: keep the socket fed with silence so the server VAD can close the turn.
                    silence = base64.b64encode(bytes(CHUNK_BYTES)).decode("ascii")
                    deadline = time.monotonic() + args.timeout
                    while time.monotonic() < deadline and not done.is_set():
                        await ws.send(json.dumps({"event": "audio", "payload": silence}))
                        await asyncio.sleep(CHUNK_MS / 1000)
                        if first_frame_at and last_frame_at and time.monotonic() - last_frame_at > 1.5:
                            break
            except ConnectionClosed as exc:
                print(f"socket closed while sending: code={exc.code} reason={exc.reason!r}")
            finally:
                await asyncio.sleep(0.2)
                receiver_task.cancel()
            seconds = len(reply) / 32_000
            print(f"reply: {len(reply)} bytes = {seconds:.2f} s")
            if reply:
                save_wav(args.out, bytes(reply))
                print(f"wrote {args.out}")
            return 0 if reply else 2
    except InvalidStatus as exc:
        print(f"handshake rejected: HTTP {exc.response.status_code}")
        return 1


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", required=True, help="ws(s)://host/live/<assistant_id>/<channel_id>")
    parser.add_argument("--token", default="")
    parser.add_argument("--session", default="")
    parser.add_argument("--agentspace", default="default")
    parser.add_argument("--wav", help="16-bit PCM WAV to send instead of a tone")
    parser.add_argument("--tone-seconds", type=float, default=1.0)
    parser.add_argument("--stop", action="store_true", help="push-to-talk: send stop and wait for the close")
    parser.add_argument("--timeout", type=float, default=45.0)
    parser.add_argument("--out", default="reply.wav")
    args = parser.parse_args()
    sys.exit(asyncio.run(run(args)))


if __name__ == "__main__":
    main()
