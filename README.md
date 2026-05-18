# xAITTSKit — xAI Grok TTS on tap, SwiftPM-friendly, streaming-native.

Swift client for [xAI Grok Text-to-Speech](https://docs.x.ai/docs/text-to-speech) on Apple platforms (iOS/macOS).

![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2018%2B%20%7C%20macOS%2015%2B-blue)
![License](https://img.shields.io/badge/License-MIT-green)

> Brand convention: the brand is **xAI** (lowercase `x`, uppercase `AI`).
> All public types follow suit — `xAITTSClient`, `xAITTSVoice`, `xAITTSFormat`,
> `xAITTSLanguage`, `xAITTSError`. This is an intentional violation of the Swift
> API Design Guidelines in favor of brand fidelity. Don't "fix" it.

## What's Included

- Streaming HTTP TTS client (incremental audio playback via `AsyncThrowingStream<Data, Error>`)
- Type-safe enums for the 12 built-in voices, 5 codecs, and 20 BCP-47 languages
- Nested `output_format` request shape — matches the xAI REST spec exactly
- Structured error type (`xAITTSError`)
- Actor-based concurrency, `Sendable` everywhere, zero external dependencies

## Requirements

- Swift 6.2 (SwiftPM `swift-tools-version: 6.2`)
- iOS 18+
- macOS 15+

## Install (Swift Package Manager)

### Xcode

**File > Add Package Dependencies...** and enter:
```
https://github.com/mrkhachaturov/xAITTSKit.git
```

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/mrkhachaturov/xAITTSKit.git", from: "0.1.0"),
]
```

## Quick Start

```swift
import xAITTSKit

let client = xAITTSClient(config: .init(bearer: "<xai-api-key-or-oauth-bearer>"))

let stream = await client.stream(
    text: "Hello! Welcome to the xAI Text to Speech API.",
    voice: .eve,
    language: .en
)

for try await chunk in stream {
    audioPlayer.enqueue(chunk) // feed to AVAudioEngine or your player of choice
}
```

## Streaming

`stream(...)` returns an `AsyncThrowingStream<Data, Error>` that yields ~4 KB
audio chunks as they arrive from xAI. Audio can start playing on the first
chunk — no need to wait for the full response.

## Voices

Twelve built-in voices: five multilingual (work for all supported languages) and
seven tuned for Russian only. Voice IDs are case-insensitive at the API layer;
this enum keeps the canonical lowercase form.

### Multilingual

| Voice | Gender | Character |
|-------|--------|-----------|
| `.eve` *(default)* | Female | Energetic, upbeat |
| `.ara` | Female | Warm, friendly |
| `.rex` | Male   | Confident, clear |
| `.sal` | Male   | Smooth, balanced |
| `.leo` | Male   | Authoritative, strong |

### Russian-only

| Voice | Gender |
|-------|--------|
| `.pavel`   | Male   |
| `.andrei`  | Male   |
| `.dmitri`  | Male   |
| `.mikhail` | Male   |
| `.sergei`  | Male   |
| `.irina`   | Female |
| `.sonia`   | Female |

Filtered lists are exposed as `xAITTSVoice.multilingual` and `xAITTSVoice.russian`.

Preview voices in the [xAI console](https://console.x.ai/team/default/voice/voice-library).

### Custom (cloned) voices

Clone a voice via the xAI console, then pass the ID through the raw-string API:

```swift
let stream = await client.streamRaw(
    text: "Hello from my cloned voice.",
    voiceId: "nlbqfwie",
    language: .en
)
```

## Output Format

The client always sends a nested `output_format` object — matching the xAI spec.
Sample rate and bit rate are optional and default to MP3 at 24 kHz / 128 kbps
server-side.

```swift
let stream = await client.stream(
    text: "Crystal clear audio.",
    voice: .rex,
    format: .mp3,
    language: .en,
    sampleRate: 44100,
    bitRate: 192000
)
```

| Codec | Notes |
|-------|-------|
| `.mp3` | Default — wide compatibility |
| `.wav` | Lossless |
| `.pcm` | Raw 16-bit LE |
| `.mulaw` | G.711 μ-law (telephony) |
| `.alaw` | G.711 A-law (telephony) |

Valid sample rates: `8000`, `16000`, `22050`, `24000` (default), `44100`, `48000`.
Valid MP3 bit rates: `32000`, `64000`, `96000`, `128000` (default), `192000`.

## Languages

20 BCP-47 codes plus `.auto`:

```
.auto, .en, .ar_EG, .ar_SA, .ar_AE, .bn, .zh, .fr, .de, .hi, .id,
.it, .ja, .ko, .pt_BR, .pt_PT, .ru, .es_MX, .es_ES, .tr, .vi
```

Hyphenated raw values (`pt-BR`, `es-MX`, `ar-EG`, etc.) match the xAI spec.

## Speech Tags

The xAI API understands inline (`[pause]`, `[laugh]`) and wrapping
(`<whisper>...</whisper>`) speech tags directly in the `text` parameter — no
special handling required from the client.

```swift
let stream = await client.stream(
    text: "So I walked in and [pause] there it was. [laugh] <whisper>It was a secret the whole time.</whisper>",
    voice: .eve,
    language: .en
)
```

## Auth

Pass either:

- The xAI OAuth bearer minted by the OpenClaw gateway (preferred — shipped to
  iOS clients via `talk.config`), or
- A static `XAI_API_KEY` obtained from the [xAI console](https://console.x.ai/team/default/api-keys).

Both go in the `Authorization: Bearer …` header — the client doesn't care which.

## Error Handling

Network and API failures surface through the stream as `xAITTSError`:

```swift
do {
    for try await chunk in stream {
        audioPlayer.enqueue(chunk)
    }
} catch let error as xAITTSError {
    switch error {
    case .http(let status, let body):
        print("xAI returned HTTP \(status): \(body ?? "<no body>")")
    case .canceled:
        print("Playback canceled")
    default:
        print("xAI TTS error: \(error.errorDescription ?? "<unknown>")")
    }
}
```

## Limits

- 15,000 characters per request (POST endpoint)
- For longer content, split by paragraph or switch to the xAI WebSocket TTS
  endpoint (not yet covered by this kit — see roadmap)

## Roadmap

- `v0.2.0` — WebSocket streaming TTS (`wss://api.x.ai/v1/tts`), `optimize_streaming_latency`, `text_normalization`
- `v0.3.0` — Voice listing (`GET /v1/tts/voices`) so custom voices can be enumerated

## Contributing

Contributions welcome:

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Add tests
4. Ensure `swift test` passes
5. Submit a PR

### Development

```bash
swift build
swift test
```

### Guidelines

- Follow the existing brand-cased naming (`xAI…`)
- Keep zero external dependencies
- Maintain `Sendable` conformance under strict concurrency
- Add tests for new features and bug fixes
- Update `CHANGELOG.md`

## License

MIT — see [LICENSE](LICENSE) for details.
