import Foundation
import Testing
@testable import xAITTSKit

@Suite struct xAITTSWebSocketURLTests {
    @Test func includesMandatoryLanguageQuery() {
        let config = xAITTSWebSocketSession.Configuration(bearer: "test", language: .en)
        let url = config.makeURL()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = components.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "language", value: "en")))
        #expect(url.scheme == "wss")
        #expect(url.host == "api.x.ai")
        #expect(url.path == "/v1/tts")
    }

    @Test func emitsOptionalFieldsWhenSet() {
        let config = xAITTSWebSocketSession.Configuration(
            bearer: "test",
            language: .ru,
            voice: .pavel,
            codec: .pcm,
            sampleRate: 24000,
            bitRate: 192000,
            optimizeStreamingLatency: 1,
            textNormalization: true
        )
        let items = URLComponents(url: config.makeURL(), resolvingAgainstBaseURL: false)!.queryItems ?? []
        let dict = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
            guard let v = item.value else { return nil }
            return (item.name, v)
        })
        #expect(dict["language"] == "ru")
        #expect(dict["voice"] == "pavel")
        #expect(dict["codec"] == "pcm")
        #expect(dict["sample_rate"] == "24000")
        #expect(dict["bit_rate"] == "192000")
        #expect(dict["optimize_streaming_latency"] == "1")
        #expect(dict["text_normalization"] == "true")
    }

    @Test func omitsUnsetFields() {
        let config = xAITTSWebSocketSession.Configuration(bearer: "test", language: .en)
        let names = (URLComponents(url: config.makeURL(), resolvingAgainstBaseURL: false)!.queryItems ?? []).map(\.name)
        #expect(names.contains("voice") == false)
        #expect(names.contains("codec") == false)
        #expect(names.contains("sample_rate") == false)
        #expect(names.contains("bit_rate") == false)
        #expect(names.contains("optimize_streaming_latency") == false)
        #expect(names.contains("text_normalization") == false)
    }
}

@Suite struct xAITTSWebSocketAuthTests {
    @Test func usesSecWebSocketProtocolFormat() {
        #expect(xAITTSWebSocketSession.authProtocol(bearer: "sk-xai-abc") == "xai-client-secret.sk-xai-abc")
    }
}

@Suite struct xAITTSWebSocketFrameEncodingTests {
    @Test func textDeltaFrameShape() throws {
        let frame = xAITTSWebSocketSession.encodeTextDelta("hello")
        let json = try JSONSerialization.jsonObject(with: Data(frame.utf8)) as! [String: Any]
        #expect(json["type"] as? String == "text.delta")
        #expect(json["delta"] as? String == "hello")
    }

    @Test func endTurnFrameShape() throws {
        let json = try JSONSerialization.jsonObject(with: Data(xAITTSWebSocketSession.endTurnFrame.utf8)) as! [String: Any]
        #expect(json["type"] as? String == "text.done")
        #expect(json.count == 1)
    }

    @Test func textDeltaEscapesQuotes() throws {
        let frame = xAITTSWebSocketSession.encodeTextDelta("She said \"hello\".")
        let json = try JSONSerialization.jsonObject(with: Data(frame.utf8)) as! [String: Any]
        #expect(json["delta"] as? String == "She said \"hello\".")
    }
}

@Suite struct xAITTSWebSocketEventDecodingTests {
    @Test func decodesAudioDelta() {
        let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let frame = #"{"type":"audio.delta","delta":"\#(bytes.base64EncodedString())"}"#
        let event = xAITTSWebSocketSession.decodeServerEvent(text: frame)
        #expect(event == .audio(bytes))
    }

    @Test func decodesAudioDoneWithTraceId() {
        let frame = #"{"type":"audio.done","trace_id":"abc-123"}"#
        #expect(xAITTSWebSocketSession.decodeServerEvent(text: frame) == .audioDone(traceId: "abc-123"))
    }

    @Test func decodesAudioDoneWithoutTraceId() {
        let frame = #"{"type":"audio.done"}"#
        #expect(xAITTSWebSocketSession.decodeServerEvent(text: frame) == .audioDone(traceId: nil))
    }

    @Test func decodesError() {
        let frame = #"{"type":"error","message":"voice not found"}"#
        #expect(xAITTSWebSocketSession.decodeServerEvent(text: frame) == .error(message: "voice not found"))
    }

    @Test func rejectsUnknownTypes() {
        let frame = #"{"type":"text.delta","delta":"hi"}"#  // outbound type, not a valid inbound event
        #expect(xAITTSWebSocketSession.decodeServerEvent(text: frame) == nil)
    }

    @Test func rejectsMalformed() {
        #expect(xAITTSWebSocketSession.decodeServerEvent(text: "not json") == nil)
        #expect(xAITTSWebSocketSession.decodeServerEvent(text: "{}") == nil)
    }
}
