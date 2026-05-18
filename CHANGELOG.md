# Changelog

## 0.2.0 — WebSocket streaming TTS

- Add `xAITTSWebSocketSession` actor — bidirectional streaming over `wss://api.x.ai/v1/tts`
- Support multi-turn sessions: connection stays open after `audio.done`; call `send(_:)` + `endTurn()` for the next turn
- Single-utterance convenience: `xAITTSWebSocketSession.synthesize(text:configuration:)` returns an `AsyncThrowingStream<Data, Error>` of decoded audio chunks — drop-in compatible with `xAITTSClient.stream`
- Exposed `optimize_streaming_latency` and `text_normalization` query parameters (WebSocket only — REST POST does not accept these)
- Auth via `Sec-WebSocket-Protocol: xai-client-secret.<bearer>` to work around `URLSessionWebSocketTask`'s Authorization-header stripping on Apple platforms (matches the xAI iOS cookbook reference at `build/xai-cookbook/iOS/VoiceTesterApp/.../StreamingTTSView.swift`)
- Public `Event` enum (`audio`, `audioDone`, `error`) — `Sendable` and `Equatable`
- 13 new Swift Testing tests covering URL building, query parameter coverage, auth subprotocol formatting, outbound frame shape, and inbound event decoding (audio.delta with base64, audio.done with/without trace_id, error, malformed)

## 0.1.0 — initial release

- Streaming HTTP TTS client (`xAITTSClient.stream`, `streamRaw`) for xAI Grok `/v1/tts`
- Nested `output_format` request shape matching the xAI REST spec exactly
- Type-safe enums: `xAITTSVoice` (12 voices: 5 multilingual + 7 Russian), `xAITTSFormat` (5 codecs), `xAITTSLanguage` (20 BCP-47 + `auto`)
- Structured error type: `xAITTSError`
- Configurable bearer auth (OAuth or API key), base URL, default voice/format/language, timeout
- Actor-based concurrency (`Sendable`, strict concurrency mode)
- Zero external dependencies
- Tests via Swift Testing (`@Suite`, `@Test`) covering voice/language/format raw values, configuration defaults, and request-body encoding
