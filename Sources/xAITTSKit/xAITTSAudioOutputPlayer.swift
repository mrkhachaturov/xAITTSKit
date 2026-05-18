//
//  xAITTSAudioOutputPlayer.swift
//  AVAudio wrapper for playing xAI Grok TTS audio chunks as they stream in.
//
//  - For `.mp3` / `.wav` / `.aac` (container formats), call ``play(container:)``
//    once you have a complete or near-complete buffer — `AVAudioPlayer` plays
//    self-contained audio data and can't decode mid-stream MP3 fragments.
//  - For `.pcm` (raw 16-bit LE), call ``attach(to:)`` once and then
//    ``play(pcm16Bytes:)`` per chunk — `AVAudioPlayerNode` queues PCM frames.
//
//  PCM streaming mirrors what an `AVAudioEngine` + `AVAudioPlayerNode` setup
//  needs; the container-format helper wraps `AVAudioPlayer` for one-shot
//  playback of fully-downloaded MP3 / WAV / AAC buffers.
//

#if canImport(AVFoundation)
@preconcurrency import AVFoundation
#endif
import Foundation
import os

public final class xAITTSAudioOutputPlayer: @unchecked Sendable {

    public static let defaultPCMSampleRate: Double = 24_000

    private let pcmSampleRate: Double
    private let pcmFormat: AVAudioFormat
    private weak var attachedEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var containerPlayer: AVAudioPlayer?

    private struct PlaybackState {
        var pending: Int = 0
        var waiters: [CheckedContinuation<Void, Never>] = []
    }
    private let state = OSAllocatedUnfairLock<PlaybackState>(initialState: .init())

    public init(pcmSampleRate: Double = defaultPCMSampleRate) {
        self.pcmSampleRate = pcmSampleRate
        self.pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: pcmSampleRate,
            channels: 1,
            interleaved: false
        )!
    }

    // MARK: - PCM streaming (use for `xAITTSFormat.pcm`)

    /// Attach an `AVAudioPlayerNode` to the engine's main mixer. Call before
    /// `engine.start()`. Required for ``play(pcm16Bytes:)``.
    ///
    /// Callable from any isolation domain — matches `AVAudioEngine`'s own
    /// contract. Don't call `attach` / `stop` concurrently.
    public func attach(to engine: AVAudioEngine) {
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: pcmFormat)
        self.playerNode = player
        self.attachedEngine = engine
    }

    public func start() {
        guard let player = playerNode, !player.isPlaying else { return }
        player.play()
    }

    /// Schedule a raw PCM16 buffer (Int16 little-endian, mono, at the
    /// configured sample rate) for playback. Use with `xAITTSClient.stream(...,
    /// format: .pcm, sampleRate: 24_000)`.
    public func play(pcm16Bytes: Data) {
        guard let player = playerNode,
              let engine = attachedEngine,
              engine.isRunning
        else { return }
        let frameCount = pcm16Bytes.count / MemoryLayout<Int16>.size
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: UInt32(frameCount)),
              let floats = buffer.floatChannelData?[0]
        else { return }
        buffer.frameLength = UInt32(frameCount)
        pcm16Bytes.withUnsafeBytes { raw in
            guard let src = raw.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            for i in 0..<frameCount {
                floats[i] = Float(src[i]) / Float(Int16.max)
            }
        }
        state.withLock { $0.pending += 1 }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [state] _ in
            let waiters = state.withLock { s -> [CheckedContinuation<Void, Never>] in
                s.pending = max(0, s.pending - 1)
                guard s.pending == 0 else { return [] }
                let w = s.waiters
                s.waiters.removeAll()
                return w
            }
            for w in waiters { w.resume() }
        }
        if !player.isPlaying { player.play() }
    }

    /// Cancel pending PCM playback and re-prime the player.
    public func interrupt() {
        playerNode?.stop()
        let waiters = state.withLock { s -> [CheckedContinuation<Void, Never>] in
            s.pending = 0
            let w = s.waiters
            s.waiters.removeAll()
            return w
        }
        for w in waiters { w.resume() }
        playerNode?.play()
    }

    /// Returns once every scheduled PCM buffer has been consumed by the
    /// output hardware. Backed by the `.dataPlayedBack` completion callback
    /// — no polling. Useful before tearing down the engine.
    public func waitForPlaybackToDrain() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeImmediately = state.withLock { s -> Bool in
                guard s.pending > 0 else { return true }
                s.waiters.append(continuation)
                return false
            }
            if resumeImmediately { continuation.resume() }
        }
    }

    // MARK: - Container-format playback (mp3 / wav / aac)

    /// Play a complete container-format audio buffer (MP3, WAV, AAC, etc.).
    /// `AVAudioPlayer` decodes the whole `data` blob at once — collect the
    /// full stream from `xAITTSClient.stream` first if you're using `.mp3`
    /// or `.wav`, then call this.
    public func play(container data: Data) throws {
        let player = try AVAudioPlayer(data: data)
        player.prepareToPlay()
        player.play()
        self.containerPlayer = player
    }

    /// Stop any container-format playback in progress.
    public func stopContainer() {
        containerPlayer?.stop()
        containerPlayer = nil
    }

    // MARK: - Lifecycle

    public func stop() {
        playerNode?.stop()
        playerNode = nil
        attachedEngine = nil
        let waiters = state.withLock { s -> [CheckedContinuation<Void, Never>] in
            s.pending = 0
            let w = s.waiters
            s.waiters.removeAll()
            return w
        }
        for w in waiters { w.resume() }
        stopContainer()
    }
}
