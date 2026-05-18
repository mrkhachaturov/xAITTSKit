//
//  xAITTSClient.swift
//  Streaming xAI TTS client.
//
//  POST https://api.x.ai/v1/tts
//  Body: { text, voice_id, language, output_format? { codec, sample_rate?, bit_rate? } }
//  Response: streamed audio bytes (MP3 / WAV / PCM / mulaw / alaw per codec).
//

import Foundation

public actor xAITTSClient {

    public struct Configuration: Sendable {
        public var baseURL: URL
        public var bearer: String                  // xAI API key or OAuth bearer
        public var defaultVoice: xAITTSVoice
        public var defaultFormat: xAITTSFormat
        public var defaultLanguage: xAITTSLanguage
        public var timeoutSeconds: TimeInterval

        public init(
            baseURL: URL = URL(string: "https://api.x.ai/v1/tts")!,
            bearer: String,
            defaultVoice: xAITTSVoice = .default,
            defaultFormat: xAITTSFormat = .mp3,
            defaultLanguage: xAITTSLanguage = .auto,
            timeoutSeconds: TimeInterval = 60
        ) {
            self.baseURL = baseURL
            self.bearer = bearer
            self.defaultVoice = defaultVoice
            self.defaultFormat = defaultFormat
            self.defaultLanguage = defaultLanguage
            self.timeoutSeconds = timeoutSeconds
        }
    }

    private let config: Configuration
    private let session: URLSession

    public init(config: Configuration) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = config.timeoutSeconds
        cfg.timeoutIntervalForResource = config.timeoutSeconds
        self.session = URLSession(configuration: cfg)
    }

    /// Stream synthesized audio chunks as they arrive from xAI.
    /// Same shape as OpenAITTSClient.stream so TalkModeManager can swap in.
    ///
    /// - Parameters:
    ///   - text: Up to 15,000 characters. Speech tags (`[pause]`, `<whisper>…</whisper>`) supported.
    ///   - voice: Built-in voice ID. Use ``streamRaw`` for custom (cloned) voice IDs.
    ///   - format: Output codec. Omit to use the configured default.
    ///   - language: BCP-47 code or `.auto`. Omit to use the configured default.
    ///   - sampleRate: Override the codec's default sample rate (8000, 16000, 22050, 24000, 44100, 48000).
    ///   - bitRate: MP3-only bit rate (32000, 64000, 96000, 128000, 192000).
    public func stream(
        text: String,
        voice: xAITTSVoice? = nil,
        format: xAITTSFormat? = nil,
        language: xAITTSLanguage? = nil,
        sampleRate: Int? = nil,
        bitRate: Int? = nil
    ) -> AsyncThrowingStream<Data, Error> {
        streamRaw(
            text: text,
            voiceId: (voice ?? config.defaultVoice).rawValue,
            format: format ?? config.defaultFormat,
            language: language ?? config.defaultLanguage,
            sampleRate: sampleRate,
            bitRate: bitRate
        )
    }

    /// Stream synthesized audio using a raw `voice_id` — useful for custom voices
    /// cloned via the xAI console.
    public func streamRaw(
        text: String,
        voiceId: String,
        format: xAITTSFormat? = nil,
        language: xAITTSLanguage? = nil,
        sampleRate: Int? = nil,
        bitRate: Int? = nil
    ) -> AsyncThrowingStream<Data, Error> {
        let body = Self.encodeRequestBody(
            text: text,
            voiceId: voiceId,
            language: (language ?? config.defaultLanguage).rawValue,
            format: format ?? config.defaultFormat,
            sampleRate: sampleRate,
            bitRate: bitRate
        )
        let bearer = config.bearer
        let url = config.baseURL
        let session = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try Task.checkCancellation()
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = body

                    let (bytes, response) = try await session.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: xAITTSError.decoding("non-HTTP response"))
                        return
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var errBody = Data()
                        for try await b in bytes { errBody.append(b); if errBody.count > 4096 { break } }
                        let snippet = String(data: errBody, encoding: .utf8)
                        continuation.finish(throwing: xAITTSError.http(status: http.statusCode, body: snippet))
                        return
                    }

                    var chunk = Data()
                    chunk.reserveCapacity(8 * 1024)
                    for try await b in bytes {
                        try Task.checkCancellation()
                        chunk.append(b)
                        if chunk.count >= 4 * 1024 {
                            continuation.yield(chunk)
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }
                    if !chunk.isEmpty { continuation.yield(chunk) }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: xAITTSError.canceled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Build the JSON request body. Exposed for testing.
    public static func encodeRequestBody(
        text: String,
        voiceId: String,
        language: String,
        format: xAITTSFormat,
        sampleRate: Int? = nil,
        bitRate: Int? = nil
    ) -> Data {
        var body: [String: Any] = [
            "text": text,
            "voice_id": voiceId,
            "language": language
        ]
        var outputFormat: [String: Any] = ["codec": format.rawValue]
        if let sampleRate { outputFormat["sample_rate"] = sampleRate }
        if let bitRate { outputFormat["bit_rate"] = bitRate }
        body["output_format"] = outputFormat
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }
}
