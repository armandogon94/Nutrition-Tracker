//
//  TimerBeepTests.swift
//  Slice 7.6: the rest-complete beep is synthesized, not a bundled asset,
//  so the tone-buffer math is unit-testable. We can't assert audible
//  playback headlessly (verified on device), but we CAN assert the PCM
//  buffer has the right length, stays within range, and is silent at the
//  fade edges.
//

import Foundation
import AVFoundation
import Testing
@testable import FitTracker

@Suite("TimerBeep")
struct TimerBeepTests {

    private func makeFormat() -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: TimerBeep.sampleRate, channels: 1)!
    }

    @Test("tone buffer length matches sampleRate * seconds")
    func toneBuffer_hasExpectedFrameCount() {
        let format = makeFormat()
        let buffer = TimerBeep.makeToneBuffer(frequency: 880, seconds: 0.2, format: format)
        let expected = AVAudioFrameCount(TimerBeep.sampleRate * 0.2)
        #expect(buffer.frameLength == expected)
    }

    @Test("tone samples stay within [-1, 1] (no clipping)")
    func toneBuffer_withinRange() {
        let format = makeFormat()
        let buffer = TimerBeep.makeToneBuffer(frequency: 1318.5, seconds: 0.1, format: format)
        let ch = buffer.floatChannelData![0]
        var maxAbs: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            maxAbs = max(maxAbs, abs(ch[i]))
        }
        #expect(maxAbs <= 1.0)
        #expect(maxAbs > 0.1, "a real tone must have non-trivial amplitude")
    }

    @Test("envelope fades in from silence")
    func toneBuffer_startsNearSilence() {
        let format = makeFormat()
        let buffer = TimerBeep.makeToneBuffer(frequency: 880, seconds: 0.2, format: format)
        let ch = buffer.floatChannelData![0]
        // First sample is at the very start of the attack ramp -> ~0.
        #expect(abs(ch[0]) < 0.05)
    }
}
