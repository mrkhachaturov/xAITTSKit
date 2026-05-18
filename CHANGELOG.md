# Changelog

## 0.1.0 — initial release

- Streaming HTTP TTS client (`xAITTSClient.stream`, `streamRaw`) for xAI Grok `/v1/tts`
- Nested `output_format` request shape matching the xAI REST spec exactly
- Type-safe enums: `xAITTSVoice` (12 voices: 5 multilingual + 7 Russian), `xAITTSFormat` (5 codecs), `xAITTSLanguage` (20 BCP-47 + `auto`)
- Structured error type: `xAITTSError`
- Configurable bearer auth (OAuth or API key), base URL, default voice/format/language, timeout
- Actor-based concurrency (`Sendable`, strict concurrency mode)
- Zero external dependencies
- Tests via Swift Testing (`@Suite`, `@Test`) covering voice/language/format raw values, configuration defaults, and request-body encoding
