//
//  xAITTSVoice.swift
//  Built-in xAI Grok TTS voices, output formats, and supported languages.
//  Source: https://docs.x.ai/docs/text-to-speech (also mirrored at
//  openclaw-xai-speech/docs/tts.md) and the live voice library at
//  https://console.x.ai/team/default/voice/voice-library.
//

import Foundation

/// Built-in xAI Grok TTS voices. Voice IDs are case-insensitive at the API
/// layer; this enum preserves the canonical lowercase form. Custom voice IDs
/// (cloned via the xAI console) are passed as raw strings — not represented here.
///
/// The published TTS docs as of 2026-05 list five multilingual voices, but the
/// console exposes additional Russian-only voices for finer locale fidelity.
public enum xAITTSVoice: String, CaseIterable, Sendable {
    // MARK: Multilingual voices

    case eve     // Female · Energetic, upbeat (default)
    case ara     // Female · Warm, friendly
    case rex     // Male   · Confident, clear
    case sal     // Male   · Smooth, balanced
    case leo     // Male   · Authoritative, strong

    // MARK: Russian-only voices

    case pavel   // Male   · Russian
    case andrei  // Male   · Russian
    case dmitri  // Male   · Russian
    case irina   // Female · Russian
    case mikhail // Male   · Russian
    case sergei  // Male   · Russian
    case sonia   // Female · Russian

    public static let `default`: xAITTSVoice = .eve

    /// Voices that work across all 20 documented languages.
    public static let multilingual: [xAITTSVoice] = [.eve, .ara, .rex, .sal, .leo]

    /// Voices tuned for Russian only — pair with `.ru` for best results.
    public static let russian: [xAITTSVoice] = [
        .pavel, .andrei, .dmitri, .irina, .mikhail, .sergei, .sonia
    ]
}

/// Output audio codec. Defaults to `mp3` (24 kHz / 128 kbps per xAI docs).
/// Sent as `output_format.codec` in the request body.
public enum xAITTSFormat: String, Sendable {
    case mp3
    case wav
    case pcm
    case mulaw
    case alaw
}

/// BCP-47 language codes accepted by xAI TTS as of 2026-05. 20 languages
/// supported; the model may also generate speech in additional languages with
/// varying accuracy. Use `.auto` for automatic detection.
///
/// Language codes are case-insensitive at the API layer.
public enum xAITTSLanguage: String, CaseIterable, Sendable {
    case auto

    case en
    case ar_EG = "ar-EG"   // Arabic (Egypt)
    case ar_SA = "ar-SA"   // Arabic (Saudi Arabia)
    case ar_AE = "ar-AE"   // Arabic (United Arab Emirates)
    case bn                // Bengali
    case zh                // Chinese (Simplified)
    case fr                // French
    case de                // German
    case hi                // Hindi
    case id                // Indonesian
    case it                // Italian
    case ja                // Japanese
    case ko                // Korean
    case pt_BR = "pt-BR"   // Portuguese (Brazil)
    case pt_PT = "pt-PT"   // Portuguese (Portugal)
    case ru                // Russian
    case es_MX = "es-MX"   // Spanish (Mexico)
    case es_ES = "es-ES"   // Spanish (Spain)
    case tr                // Turkish
    case vi                // Vietnamese
}
