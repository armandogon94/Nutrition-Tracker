//
//  MainTabView.swift
//  Slice 0.5: 5 tabs — Inicio (Home), Comidas (Meals + Plan), Entrenar
//  (Workouts), Progreso (History), Perfil (Profile + Settings). Each
//  tab hosts a NavigationStack so deep nav doesn't bleed across tabs.
//

import SwiftUI

struct MainTabView: View {
    @Environment(\.appTheme) private var theme
    @State private var selection: Int = MainTabView.initialTab()

    /// DEBUG-only: lets the simulator capture script jump to a specific
    /// tab via `-uiInitialTab N` launch argument.
    private static func initialTab() -> Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-uiInitialTab"),
           i + 1 < args.count, let n = Int(args[i + 1]),
           (0...4).contains(n) {
            return n
        }
        #endif
        return 0
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeView() }
                .tabItem { Label("Inicio", systemImage: "flame.fill") }
                .tag(0)

            NavigationStack { MealsTabView() }
                .tabItem { Label("Comidas", systemImage: "fork.knife") }
                .tag(1)

            NavigationStack { WorkoutsTabView() }
                .tabItem { Label("Entrenar", systemImage: "dumbbell.fill") }
                .tag(2)

            NavigationStack { HistoryView() }
                .tabItem { Label("Progreso", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(3)

            NavigationStack { ProfileTabView() }
                .tabItem { Label("Perfil", systemImage: "person.crop.circle.fill") }
                .tag(4)
        }
        .tint(theme.accent)
    }
}

/// Wrapper that puts MealsListView at the root with toolbar action to view plan.
struct MealsTabView: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        MealsListView()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        MealPlanWeekView()
                    } label: {
                        Image(systemName: "calendar")
                    }
                    NavigationLink {
                        ScanView()
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                }
            }
    }
}

/// Wrapper that puts ProgramsListView at the root with toolbar action to browse exercises.
struct WorkoutsTabView: View {
    var body: some View {
        ProgramsListView()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ExercisesBrowserView()
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
            }
    }
}

/// Wrapper that lets profile tab also reach Settings.
struct ProfileTabView: View {
    var body: some View {
        ProfileView()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
    }
}

#Preview("MainTab — Liquid Glass") {
    MainTabView()
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(MockServiceContainer())
        .preferredColorScheme(.dark)
}
