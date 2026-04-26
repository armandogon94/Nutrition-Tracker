//
//  ExerciseVideoSourceTests.swift
//  Slice 6.5: enforces ADR-0005 — YouTube hosts open externally,
//  everything else plays inline. Pure-function test — no UI involved.
//

import Foundation
import Testing
@testable import FitTracker

@Suite("ExerciseVideoSource")
struct ExerciseVideoSourceTests {

    @Test("YouTube watch URL classifies as external")
    func classify_youtubeWatchURL() {
        let url = URL(string: "https://www.youtube.com/watch?v=abc")!
        #expect(ExerciseVideoSource.classify(url) == .external(url))
    }

    @Test("youtu.be short URL classifies as external")
    func classify_youtuBeShortURL() {
        let url = URL(string: "https://youtu.be/xyz")!
        #expect(ExerciseVideoSource.classify(url) == .external(url))
    }

    @Test("m.youtube.com mobile URL classifies as external")
    func classify_mobileYoutubeURL() {
        let url = URL(string: "https://m.youtube.com/watch?v=abc")!
        #expect(ExerciseVideoSource.classify(url) == .external(url))
    }

    @Test("Direct MP4 URL classifies as inline")
    func classify_directMP4() {
        let url = URL(string: "https://cdn.fittracker.app/videos/bench.mp4")!
        #expect(ExerciseVideoSource.classify(url) == .inline(url))
    }

    @Test("nil URL classifies as none")
    func classify_nil() {
        #expect(ExerciseVideoSource.classify(nil) == .none)
    }
}
