//
//  PingView.swift
//  Debug-only view. Hits GET /health on the configured backend and
//  displays the result — proves the APIClient actor, APIConfig lookup,
//  and themed card styling all compose correctly end-to-end.
//

import SwiftUI

#if DEBUG
@MainActor
@Observable
final class PingViewModel {
    enum State: Equatable {
        case idle
        case loading
        case success(String)
        case failure(String)
    }

    var state: State = .idle
    private let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func ping() async {
        state = .loading
        do {
            let resp: HealthResponse = try await api.get("/health")
            state = .success("status: \(resp.status)")
        } catch let err as APIError {
            state = .failure(humanize(err))
        } catch {
            state = .failure(error.localizedDescription)
        }
    }

    private func humanize(_ err: APIError) -> String {
        switch err {
        case .offline: return "Offline — backend not reachable"
        case .unauthorized: return "Unauthorized (401)"
        case .notFound: return "Not found (404)"
        case .rateLimited(let s): return "Rate limited" + (s.map { " (retry in \($0)s)" } ?? "")
        case .server(let status, let detail): return "Server \(status): \(detail ?? "no detail")"
        case .decoding(let m): return "Decoding error: \(m)"
        case .network(let m): return "Network error: \(m)"
        case .cancelled: return "Cancelled"
        case .unknown(let m): return "Unknown: \(m)"
        }
    }
}

struct PingView: View {
    @Environment(\.appTheme) private var theme
    @State private var vm = PingViewModel()

    var body: some View {
        VStack(spacing: 14) {
            Text("DEBUG PING")
                .font(theme.font.captionMedium)
                .tracking(1.5)
                .foregroundStyle(theme.textTertiary)

            Group {
                switch vm.state {
                case .idle:
                    Text("Tap to call \(APIConfig.baseURL.absoluteString)/health")
                        .font(theme.font.body)
                        .foregroundStyle(theme.textSecondary)
                case .loading:
                    ProgressView().tint(theme.accent)
                case .success(let msg):
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .font(theme.font.bodyMedium)
                        .foregroundStyle(theme.positive)
                case .failure(let msg):
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(theme.font.bodyMedium)
                        .foregroundStyle(theme.negative)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

            Button {
                Task { await vm.ping() }
            } label: {
                Text("Ping backend")
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(theme.accent, in: Capsule())
            }
            .disabled(vm.state == .loading)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .themedCard()
    }
}

#Preview("PingView — Liquid Glass") {
    ZStack {
        ThemedBackdrop()
        PingView().padding()
    }
    .environment(\.appTheme, LiquidGlassTheme())
    .preferredColorScheme(.dark)
}

#Preview("PingView — Health Cards") {
    ZStack {
        ThemedBackdrop()
        PingView().padding()
    }
    .environment(\.appTheme, HealthCardsTheme())
    .preferredColorScheme(.light)
}
#endif
