import Foundation
import Testing
@testable import xAITTSKit

@Suite struct xAITTSVoiceTests {
    @Test func multilingualVoicesAreLowercaseRawValues() {
        #expect(xAITTSVoice.eve.rawValue == "eve")
        #expect(xAITTSVoice.ara.rawValue == "ara")
        #expect(xAITTSVoice.rex.rawValue == "rex")
        #expect(xAITTSVoice.sal.rawValue == "sal")
        #expect(xAITTSVoice.leo.rawValue == "leo")
    }

    @Test func russianVoicesArePresent() {
        let russian = Set(xAITTSVoice.russian.map(\.rawValue))
        #expect(russian == ["pavel", "andrei", "dmitri", "irina", "mikhail", "sergei", "sonia"])
    }

    @Test func defaultIsEve() {
        #expect(xAITTSVoice.default == .eve)
    }

    @Test func allVoicesAreUnique() {
        let raws = xAITTSVoice.allCases.map(\.rawValue)
        #expect(raws.count == 12)
        #expect(Set(raws).count == raws.count)
    }
}

@Suite struct xAITTSLanguageTests {
    @Test func bcp47CasingMatchesSpec() {
        #expect(xAITTSLanguage.pt_BR.rawValue == "pt-BR")
        #expect(xAITTSLanguage.pt_PT.rawValue == "pt-PT")
        #expect(xAITTSLanguage.es_MX.rawValue == "es-MX")
        #expect(xAITTSLanguage.es_ES.rawValue == "es-ES")
        #expect(xAITTSLanguage.ar_EG.rawValue == "ar-EG")
        #expect(xAITTSLanguage.ar_SA.rawValue == "ar-SA")
        #expect(xAITTSLanguage.ar_AE.rawValue == "ar-AE")
    }

    @Test func shortCodesAreLowercase() {
        #expect(xAITTSLanguage.en.rawValue == "en")
        #expect(xAITTSLanguage.ru.rawValue == "ru")
        #expect(xAITTSLanguage.zh.rawValue == "zh")
        #expect(xAITTSLanguage.ja.rawValue == "ja")
    }

    @Test func twentyLanguagesPlusAuto() {
        // Spec: 20 BCP-47 codes + `auto`.
        #expect(xAITTSLanguage.allCases.count == 21)
        #expect(xAITTSLanguage.allCases.contains(.auto))
    }
}

@Suite struct xAITTSFormatTests {
    @Test func codecRawValuesMatchSpec() {
        #expect(xAITTSFormat.mp3.rawValue == "mp3")
        #expect(xAITTSFormat.wav.rawValue == "wav")
        #expect(xAITTSFormat.pcm.rawValue == "pcm")
        #expect(xAITTSFormat.mulaw.rawValue == "mulaw")
        #expect(xAITTSFormat.alaw.rawValue == "alaw")
    }
}

@Suite struct xAITTSConfigurationTests {
    @Test func defaultsMatchSpec() {
        let cfg = xAITTSClient.Configuration(bearer: "test")
        #expect(cfg.baseURL.absoluteString == "https://api.x.ai/v1/tts")
        #expect(cfg.defaultVoice == .eve)
        #expect(cfg.defaultFormat == .mp3)
        #expect(cfg.defaultLanguage == .auto)
        #expect(cfg.timeoutSeconds == 60)
        #expect(cfg.bearer == "test")
    }

    @Test func bearerIsRequired() {
        let cfg = xAITTSClient.Configuration(bearer: "sk-xai-abc")
        #expect(cfg.bearer == "sk-xai-abc")
    }
}

@Suite struct xAITTSRequestBodyTests {
    @Test func minimalBodyHasRequiredKeys() throws {
        let data = xAITTSClient.encodeRequestBody(
            text: "Hello",
            voiceId: "eve",
            language: "en",
            format: .mp3
        )
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["text"] as? String == "Hello")
        #expect(json["voice_id"] as? String == "eve")
        #expect(json["language"] as? String == "en")
        let output = json["output_format"] as? [String: Any]
        #expect(output?["codec"] as? String == "mp3")
        #expect(output?["sample_rate"] == nil)
        #expect(output?["bit_rate"] == nil)
    }

    @Test func includesSampleAndBitRateWhenProvided() throws {
        let data = xAITTSClient.encodeRequestBody(
            text: "Hi",
            voiceId: "rex",
            language: "en",
            format: .mp3,
            sampleRate: 44100,
            bitRate: 192000
        )
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let output = json["output_format"] as? [String: Any]
        #expect(output?["sample_rate"] as? Int == 44100)
        #expect(output?["bit_rate"] as? Int == 192000)
    }

    @Test func russianVoiceBodyShape() throws {
        let data = xAITTSClient.encodeRequestBody(
            text: "Привет",
            voiceId: xAITTSVoice.pavel.rawValue,
            language: xAITTSLanguage.ru.rawValue,
            format: .wav,
            sampleRate: 24000
        )
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["voice_id"] as? String == "pavel")
        #expect(json["language"] as? String == "ru")
        let output = json["output_format"] as? [String: Any]
        #expect(output?["codec"] as? String == "wav")
        #expect(output?["sample_rate"] as? Int == 24000)
    }
}

@Suite struct xAITTSErrorTests {
    @Test func errorDescriptionsAreNonEmpty() {
        let cases: [xAITTSError] = [
            .invalidURL,
            .missingAuth,
            .http(status: 401, body: "{\"error\":\"bad key\"}"),
            .textTooLong(maxChars: 15000, gotChars: 20000),
            .decoding("bad json"),
            .canceled
        ]
        for err in cases {
            #expect((err.errorDescription ?? "").isEmpty == false)
        }
    }
}
