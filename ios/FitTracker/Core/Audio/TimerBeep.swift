//
//  TimerBeep.swift
//  Slice 7.6: audible "rest is over" beep.
//
//  Design (source-driven-development):
//    Rather than ship a binary WAV blob, we SYNTHESIZE the tone with
//    AVAudioEngine — a short two-note chime built from sine-wave PCM
//    buffers. This keeps the asset out of the bundle, makes the sound
//    fully code-reviewable, and lets us unit-test the buffer math.
//
//    AVAudioSession is configured `.ambient`:
//      - mixes with the user's music (does NOT duck or stop Spotify)
//      - obeys the hardware silent switch (no beep in silent mode, by
//        design — we always pair the beep with a haptic + notification so
//        a silenced phone still alerts; ADR-0006 §3)
//
//  iOS vibration alone is unreliable, so RestTimerController fires this
//  beep together with HapticsService.restComplete().
//
//  Concurrency: the engine lives on @MainActor for simple lifecycle; the
//  pure buffer builder is `nonisolated static` so tests can call it freely.
//

import Foundation
import AVFoundation

@MainActor
final class TimerBeep {

    static let shared = TimerBeep()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isConfigured = false

    /// Standard output sample rate. 44.1 kHz is universally supported.
    /// `nonisolated` so the pure tone builder + tests can read it freely.
    nonisolated static let sampleRate: Double = 44_100

    // MARK: - Public

    /// Play the two-note completion chime. No-op-safe if audio can't start.
    func playRestComplete() {
        do {
            try configureIfNeeded()
            try activateSession()

            let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
            // Two ascending notes: A5 (880 Hz) then E6 (1318.5 Hz).
            let note1 = Self.makeToneBuffer(frequency: 880, seconds: 0.18, format: format)
            let note2 = Self.makeToneBuffer(frequency: 1318.5, seconds: 0.30, format: format)

            player.scheduleBuffer(note1, at: nil)
            player.scheduleBuffer(note2, at: nil)
            if !player.isPlaying { player.play() }
        } catch {
            // Audio is best-effort; the haptic + notification still alert.
        }
    }

    // MARK: - Pure tone synthesis (testable)

    /// Builds a mono PCM buffer holding `seconds` of a sine wave at
    /// `frequency`, with a short linear attack/release envelope to avoid
    /// click artifacts at the edges.
    nonisolated static func makeToneBuffer(
        frequency: Double, seconds: Double, format: AVAudioFormat
    ) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let frameCount = AVAudioFrameCount(sr * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let channels = buffer.floatChannelData!
        let twoPiF = 2.0 * Double.pi * frequency
        // 8ms attack/release ramp.
        let ramp = max(1, Int(sr * 0.008))

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sr
            var sample = Float(sin(twoPiF * t)) * 0.6 // headroom below clipping

            // Linear fade in/out so the note doesn't pop.
            if frame < ramp {
                sample *= Float(frame) / Float(ramp)
            } else if frame > Int(frameCount) - ramp {
                sample *= Float(Int(frameCount) - frame) / Float(ramp)
            }

            for ch in 0..<Int(format.channelCount) {
                channels[ch][frame] = sample
            }
        }
        return buffer
    }

    // MARK: - Engine lifecycle

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        isConfigured = true
    }

    private func activateSession() throws {
        #if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        // .ambient = obey silent switch + mix with other audio.
        try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try session.setActive(true, options: [])
        #endif
    }
}
