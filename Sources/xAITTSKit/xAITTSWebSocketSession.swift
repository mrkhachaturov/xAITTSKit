//
//  xAITTSWebSocketSession.swift
//  Bidirectional streaming xAI TTS over WebSocket.
//
//  wss://api.x.ai/v1/tts?language=en&voice=eve&codec=mp3&sample_rate=24000&bit_rate=128000
//
//  Client -> Server: { "type": "text.delta", "delta": "..." }
//                    { "type": "text.done" }
//  Server -> Client: { "type": "audio.delta", "delta": "<base64>" }
//                    { "type": "audio.done", "trace_id": "uuid" }
//                    { "type": "error", "message": "..." }
//
//  The connection stays open after `audio.done` — multi-turn sessions are
//  supported. Call `close()` (or let the actor deinit) when you're done.
//

import Foundation

public actor xAITTSWebSocketSession {

    public struct Configuration: Sendable {
        public var baseURL: URL                       // wss://api.x.ai/v1/tts
        public var bearer: String
        public var language: xAITTSLanguage
        public var voice: xAITTSVoice?
        public var codec: xAITTSFormat?
        public var sampleRate: Int?
        public var bitRate: Int?
        /// `0` = best quality (default), `1` = lower time-to-first-audio
        public var optimizeStreamingLatency: Int?
        public var textNormalization: Bool?
        public var timeoutSeconds: TimeInterval

        public init(
            baseURL: URL = URL(string: "wss://api.x.ai/v1/tts")!,
            bearer: String,
            language: xAITTSLanguage,
            voice: xAITTSVoice? = nil,
            codec: xAITTSFormat? = nil,
            sampleRate: Int? = nil,
            bitRate: Int? = nil,
            optimizeStreamingLatency: Int? = nil,
            textNormalization: Bool? = nil,
            timeoutSeconds: TimeInterval = 60
        ) {
            self.baseURL = baseURL
            self.bearer = bearer
            self.language = language
            self.voice = voice
            self.codec = codec
            self.sampleRate = sampleRate
            self.bitRate = bitRate
            self.optimizeStreamingLatency = optimizeStreamingLatency
            self.textNormalization = textNormalization
            self.timeoutSeconds = timeoutSeconds
        }

        /// Build the connection URL with query parameters per the xAI spec.
        /// Exposed for testing.
        public func makeURL() -> URL {
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
            var items: [URLQueryItem] = [URLQueryItem(name: "language", value: language.rawValue)]
            if let voice { items.append(URLQueryItem(name: "voice", value: voice.rawValue)) }
            if let codec { items.append(URLQueryItem(name: "codec", value: codec.rawValue)) }
            if let sampleRate { items.append(URLQueryItem(name: "sample_rate", value: String(sampleRate))) }
            if let bitRate { items.append(URLQueryItem(name: "bit_rate", value: String(bitRate))) }
            if let optimizeStreamingLatency {
                items.append(URLQueryItem(name: "optimize_streaming_latency", value: String(optimizeStreamingLatency)))
            }
            if let textNormalization {
                items.append(URLQueryItem(name: "text_normalization", value: textNormalization ? "true" : "false"))
            }
            components.queryItems = items
            return components.url!
        }
    }

    /// Server -> client events surfaced through ``events``.
    public enum Event: Sendable, Equatable {
        /// Decoded audio chunk (already base64-decoded). Codec matches the
        /// `codec` query parameter set at connection time.
        case audio(Data)
        /// Server finished the current turn's audio. Connection stays open;
        /// call ``send(_:)`` + ``endTurn()`` again for the next turn.
        case audioDone(traceId: String?)
        /// Server reported an error. The connection may still be open.
        case error(message: String)
    }

    // MARK: - Public stream

    public nonisolated let events: AsyncThrowingStream<Event, Error>

    // MARK: - Internals

    private let task: URLSessionWebSocketTask
    private let continuation: AsyncThrowingStream<Event, Error>.Continuation
    private var receiveTask: Task<Void, Never>?
    private var isClosed = false

    private init(task: URLSessionWebSocketTask) {
        self.task = task
        var local: AsyncThrowingStream<Event, Error>.Continuation!
        self.events = AsyncThrowingStream<Event, Error> { local = $0 }
        self.continuation = local
    }

    deinit {
        receiveTask?.cancel()
        task.cancel(with: .goingAway, reason: nil)
    }

    // MARK: - Opening

    /// Open a new WebSocket session. The returned actor exposes ``events``,
    /// ``send(_:)``, ``endTurn()``, and ``close()``.
    ///
    /// Auth is passed via `Sec-WebSocket-Protocol` (`xai-client-secret.<bearer>`)
    /// because `URLSessionWebSocketTask` strips the `Authorization` header during
    /// the HTTP→WebSocket upgrade on Apple platforms.
    public static func open(
        configuration: Configuration,
        session: URLSession? = nil
    ) async throws -> xAITTSWebSocketSession {
        let urlSession: URLSession = session ?? {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = configuration.timeoutSeconds
            cfg.timeoutIntervalForResource = configuration.timeoutSeconds
            return URLSession(configuration: cfg)
        }()

        let task = urlSession.webSocketTask(
            with: configuration.makeURL(),
            protocols: [Self.authProtocol(bearer: configuration.bearer)]
        )
        task.resume()

        let s = xAITTSWebSocketSession(task: task)
        await s.startReceiveLoop()
        return s
    }

    /// Subprotocol string used to authenticate the WebSocket. Exposed for tests.
    public static func authProtocol(bearer: String) -> String {
        "xai-client-secret.\(bearer)"
    }

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func receiveLoop() async {
        while !isClosed {
            do {
                let message = try await task.receive()
                handle(message: message)
            } catch is CancellationError {
                continuation.finish(throwing: xAITTSError.canceled)
                return
            } catch {
                if !isClosed {
                    continuation.finish(throwing: error)
                }
                return
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handleJSON(text: text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                handleJSON(text: text)
            } else {
                continuation.yield(.error(message: "non-utf8 binary frame from server"))
            }
        @unknown default:
            continuation.yield(.error(message: "unknown WebSocket message kind"))
        }
    }

    private func handleJSON(text: String) {
        guard let event = Self.decodeServerEvent(text: text) else {
            continuation.yield(.error(message: "unparseable server frame: \(text)"))
            return
        }
        continuation.yield(event)
    }

    /// Parse a server -> client frame. Exposed for testing.
    public static func decodeServerEvent(text: String) -> Event? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return nil }

        switch type {
        case "audio.delta":
            guard let b64 = json["delta"] as? String,
                  let bytes = Data(base64Encoded: b64)
            else { return nil }
            return .audio(bytes)
        case "audio.done":
            return .audioDone(traceId: json["trace_id"] as? String)
        case "error":
            return .error(message: (json["message"] as? String) ?? "<unknown error>")
        default:
            return nil
        }
    }

    // MARK: - Outgoing

    /// Send a chunk of text to be synthesized. Up to 15,000 characters per
    /// frame per the xAI spec.
    public func send(_ text: String) async throws {
        let frame = Self.encodeTextDelta(text)
        try await task.send(.string(frame))
    }

    /// Signal the end of the current turn. The server will finish synthesizing
    /// the accumulated text and emit `audio.done`. The connection stays open
    /// for the next turn.
    public func endTurn() async throws {
        try await task.send(.string(Self.endTurnFrame))
    }

    /// Close the connection.
    public func close() async {
        guard !isClosed else { return }
        isClosed = true
        receiveTask?.cancel()
        task.cancel(with: .normalClosure, reason: nil)
        continuation.finish()
    }

    // MARK: - Frame encoders (exposed for testing)

    public static func encodeTextDelta(_ text: String) -> String {
        let payload: [String: Any] = ["type": "text.delta", "delta": text]
        return jsonString(payload)
    }

    public static let endTurnFrame: String = jsonString(["type": "text.done"])

    private static func jsonString(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8)
        else { return "{}" }
        return s
    }
}

// MARK: - Single-turn convenience

extension xAITTSWebSocketSession {
    /// Open a session, send a single text payload, signal end-of-turn, decode
    /// audio frames as they stream, and close once `audio.done` arrives.
    /// Returns an `AsyncThrowingStream<Data, Error>` of decoded audio chunks —
    /// drop-in compatible with `xAITTSClient.stream`.
    public static func synthesize(
        text: String,
        configuration: Configuration
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = try await xAITTSWebSocketSession.open(configuration: configuration)
                    try await session.send(text)
                    try await session.endTurn()
                    for try await event in session.events {
                        switch event {
                        case .audio(let bytes):
                            continuation.yield(bytes)
                        case .audioDone:
                            await session.close()
                            continuation.finish()
                            return
                        case .error(let message):
                            await session.close()
                            continuation.finish(throwing: xAITTSError.http(status: 0, body: message))
                            return
                        }
                    }
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
}
