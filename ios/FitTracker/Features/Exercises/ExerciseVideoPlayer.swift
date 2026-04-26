//
//  ExerciseVideoPlayer.swift
//  Slice 6.5: thin SwiftUI wrapper around AVKit's VideoPlayer.
//  Drives the playback policy from ADR-0005 — only direct (non-YouTube)
//  URLs render inline; YouTube URLs are opened externally.
//

import AVKit
import SwiftUI

// MARK: - Host classifier

enum ExerciseVideoSource: Equatable {
    /// AVKit can play this directly (MP4 / HLS / etc.).
    case inline(URL)
    /// Must be opened externally (YouTube / unknown host).
    case external(URL)
    /// No URL at all.
    case none

    /// Hosts that AVKit refuses to play. Lowercase, no scheme.
    static let externalHosts: Set<String> = [
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "youtu.be"
    ]

    static func classify(_ url: URL?) -> ExerciseVideoSource {
        guard let url else { return .none }
        let host = (url.host ?? "").lowercased()
        if Self.externalHosts.contains(host) {
            return .external(url)
        }
        return .inline(url)
    }
}

// MARK: - Inline player

struct ExerciseVideoPlayer: View {
    @Environment(\.appTheme) private var theme
    let url: URL

    /// AVPlayer is non-Sendable; build it lazily on the main actor.
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .fill(.black)
            if let player {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous))
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(height: 220)
        .onAppear {
            if player == nil {
                player = AVPlayer(url: url)
            }
        }
        .onDisappear {
            player?.pause()
        }
    }
}
