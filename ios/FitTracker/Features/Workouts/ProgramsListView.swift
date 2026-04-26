//
//  ProgramsListView.swift
//  Slice 6.2: real backend-backed list of preset workout programs.
//  Uses the SwiftData-cached `ProgramsService` so the view renders
//  even in airplane mode after one online sync.
//

import SwiftUI

struct ProgramsListView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var container

    /// Optional override for previews / tests. Production wiring builds
    /// the real service via `live()` on first appear.
    var injectedService: (any ProgramsServiceProtocol)?

    @State private var programs: [WorkoutProgram] = []
    @State private var loadFailed = false
    @State private var isLoading = false

    private var service: any ProgramsServiceProtocol {
        injectedService ?? container.programs
    }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            content
        }
        .navigationTitle(Text(String(localized: "programs.title")))
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && programs.isEmpty {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .tint(theme.accent)
        } else if loadFailed && programs.isEmpty {
            errorState
        } else if programs.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(programs, id: \.id) { program in
                        NavigationLink {
                            ProgramDetailView(program: program, injectedService: injectedService)
                        } label: {
                            ProgramCard(program: program)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 60)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .refreshable { await load() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "dumbbell")
                .font(.system(size: 40))
                .foregroundStyle(theme.textTertiary)
            Text(String(localized: "programs.empty"))
                .font(theme.font.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40))
                .foregroundStyle(theme.textTertiary)
            Text(String(localized: "programs.loadFailed"))
                .font(theme.font.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await load() }
            } label: {
                Text(String(localized: "common.tryAgain"))
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(theme.accent, in: Capsule())
            }
        }
        .padding(40)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            programs = try await service.allPrograms()
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}

// MARK: - ProgramCard

struct ProgramCard: View {
    @Environment(\.appTheme) private var theme
    let program: WorkoutProgram

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(program.name)
                    .font(theme.font.titleCompact)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                difficultyPill
            }
            if !program.summary.isEmpty {
                Text(program.summary)
                    .font(theme.font.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: 14) {
                Label {
                    Text(String(localized: "programs.daysPerWeek")
                        .replacingOccurrences(of: "%lld", with: "\(program.daysPerWeek)"))
                } icon: {
                    Image(systemName: "calendar")
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
            }
            .font(theme.font.caption)
            .foregroundStyle(theme.textTertiary)
        }
        .padding(16)
        .themedCard()
    }

    private var difficultyPill: some View {
        let color: Color = {
            switch program.difficulty {
            case .beginner: theme.positive
            case .intermediate: theme.accent
            case .advanced: theme.negative
            }
        }()
        return Text(program.difficulty.label)
            .font(theme.font.captionMedium)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.18), in: Capsule())
    }
}

#Preview("ProgramsList — Liquid Glass") {
    NavigationStack {
        ProgramsListView()
            .environment(\.appTheme, LiquidGlassTheme())
            .environment(MockServiceContainer())
            .preferredColorScheme(.dark)
    }
}

#Preview("ProgramsList — Health Cards") {
    NavigationStack {
        ProgramsListView()
            .environment(\.appTheme, HealthCardsTheme())
            .environment(MockServiceContainer())
            .preferredColorScheme(.light)
    }
}
