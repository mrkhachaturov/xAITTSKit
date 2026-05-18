//
//  xAITTSError.swift
//

import Foundation

public enum xAITTSError: Error, LocalizedError, Sendable {
    case invalidURL
    case missingAuth
    case http(status: Int, body: String?)
    case textTooLong(maxChars: Int, gotChars: Int)
    case decoding(String)
    case canceled

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid xAI TTS URL"
        case .missingAuth: return "Missing xAI Bearer token"
        case .http(let s, let body): return "xAI TTS HTTP \(s): \(body ?? "<no body>")"
        case .textTooLong(let max, let got): return "Text too long: \(got)/\(max) chars"
        case .decoding(let m): return "xAI TTS decoding: \(m)"
        case .canceled: return "xAI TTS canceled"
        }
    }
}
