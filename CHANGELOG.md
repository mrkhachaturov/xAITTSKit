# Changelog

## 0.3.1 — nonisolated audio helpers, drain-without-polling

- Drop `@MainActor` from `xAITTSAudioOutputPlayer.attach` / `start` / `play` / `interrupt` / `stop`. Callable from any isolation domain, matching `AVAudioEngine`'s own contract — no forced main-thread hop when bootstrapping audio off-main.
- `waitForPlaybackToDrain()` is now backed by `CheckedContinuation` waiters resumed from the `.dataPlayedBack` callback. No polling, no `pollIntervalMillis` knob. `interrupt()` and `stop()` also wake pending waiters so they don't hang.

## 0.3.0 — AVAudio output player

- Add `xAITTSAudioOutputPlayer` for playing back streamed TTS audio:
  - **PCM streaming** — `attach(to:)` an `AVAudioEngine` and call `play(pcm16Bytes:)` per chunk for `xAITTSFormat.pcm` streams. Schedules buffers on an `AVAudioPlayerNode`; tracks pending buffers with `OSAllocatedUnfairLock` so `waitForPlaybackToDrain()` reflects hardware playout (not just queue length)
  - **Container-format playback** — `play(container:)` wraps `AVAudioPlayer` for one-shot playback of fully-downloaded MP3 / WAV / AAC buffers
  - `interrupt()` cancels pending PCM playback and re-primes the player for barge-in scenarios
- Default sample rate matches xAI's default output (`24_000` Hz, mono Float32 on the engine, decoded from Int16 LE)

## 0.2.0 — WebSocket streaming TTS

- Add `xAITTSWebSocketSession` actor — bidirectional streaming over `wss://api.x.ai/v1/tts`
- Support multi-turn sessions: connection stays open after `audio.done`; call `send(_:)` + `endTurn()` for the next turn
- Single-utterance convenience: `xAITTSWebSocketSession.synthesize(text:configuration:)` returns an `AsyncThrowingStream<Data, Error>` of decoded audio chunks — drop-in compatible with `xAITTSClient.stream`
- Exposed `optimize_streaming_latency` and `text_normalization` query parameters (WebSocket only — REST POST does not accept these)
- Auth via `Sec-WebSocket-Protocol: xai-client-secret.<bearer>` to work around `URLSessionWebSocketTask`'s Authorization-header stripping on Apple platforms
- Public `Event` enum (`audio`, `audioDone`, `error`) — `Sendable` and `Equatable`

## 0.1.0 — initial release

- Streaming HTTP TTS client (`xAITTSClient.stream`, `streamRaw`) for xAI Grok `/v1/tts`
- Nested `output_format` request shape matching the xAI REST spec exactly
- Type-safe enums: `xAITTSVoice` (12 voices: 5 multilingual + 7 Russian), `xAITTSFormat` (5 codecs), `xAITTSLanguage` (20 BCP-47 + `auto`)
- Structured error type: `xAITTSError`
- Configurable bearer auth, base URL, default voice/format/language, timeout
- Actor-based concurrency (`Sendable`, strict concurrency mode)
- Zero external dependencies
