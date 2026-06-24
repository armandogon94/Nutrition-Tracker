//
//  ProfileView.swift
//  Slice 0.5 mock — profile form with live TDEE preview.
//

import SwiftUI

struct ProfileView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services

    @State private var profile: UserProfile = MockData.profile
    @State private var isSaving = false
    @State private var savedConfirmation = false
    @State private var saveError = false

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    formCard
                    TDEECalculatorView(profile: profile)
                    saveButton
                    if savedConfirmation {
                        Text("profile.saved")
                            .font(theme.font.caption)
                            .foregroundStyle(theme.positive)
                    } else if saveError {
                        Text("profile.error.generic")
                            .font(theme.font.caption)
                            .foregroundStyle(theme.negative)
                    }
                    NavigationLink {
                        GoalsView()
                    } label: {
                        HStack {
                            Image(systemName: "target")
                            Text("settings.row.goals")
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12))
                        }
                        .padding(16)
                        .themedCard()
                        .foregroundStyle(theme.accent)
                    }
                    Spacer(minLength: 60)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Perfil")
        .task {
            profile = (try? await services.profile.profile()) ?? MockData.profile
        }
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack {
                if isSaving { ProgressView().tint(.white) }
                Text("profile.save").font(theme.font.bodyMedium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(theme.accent, in: RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous))
            .foregroundStyle(.white)
        }
        .disabled(isSaving)
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        savedConfirmation = false
        saveError = false
        do {
            try await services.profile.updateProfile(profile)
            savedConfirmation = true
        } catch {
            saveError = true
        }
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(theme.accent.opacity(0.2))
                Text(String((services.auth.currentUser?.displayName ?? "U").prefix(1)))
                    .font(theme.font.title)
                    .foregroundStyle(theme.accent)
            }
            .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(services.auth.currentUser?.displayName ?? "Usuario")
                    .font(theme.font.titleCompact)
                    .foregroundStyle(theme.textPrimary)
                Text(services.auth.currentUser?.email ?? "")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .themedCard()
    }

    private var formCard: some View {
        VStack(spacing: 12) {
            stepperRow(label: "Peso", suffix: "kg", value: $profile.weightKg, step: 0.5, range: 30...250)
            stepperRow(label: "Estatura", suffix: "cm", value: Binding(
                get: { profile.heightCm },
                set: { profile.heightCm = $0 }
            ), step: 1, range: 100...230)
            stepperRow(label: "Edad", suffix: "años", intValue: Binding(
                get: { profile.age },
                set: { profile.age = $0 }
            ), range: 13...120)

            HStack {
                Text("Sexo").font(theme.font.body).foregroundStyle(theme.textSecondary)
                Spacer()
                Picker("", selection: $profile.sex) {
                    ForEach(Sex.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            HStack {
                Text("Actividad").font(theme.font.body).foregroundStyle(theme.textSecondary)
                Spacer()
                Picker("", selection: $profile.activity) {
                    ForEach(ActivityLevel.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .tint(theme.accent)
            }
        }
        .padding(16)
        .themedCard()
    }

    private func stepperRow(label: String, suffix: String, value: Binding<Double>, step: Double, range: ClosedRange<Double>) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(label).foregroundStyle(theme.textSecondary)
                Spacer()
                Text("\(value.wrappedValue, specifier: "%.1f") \(suffix)")
                    .foregroundStyle(theme.textPrimary)
            }
        }
        .tint(theme.accent)
    }

    private func stepperRow(label: String, suffix: String, intValue: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: intValue, in: range) {
            HStack {
                Text(label).foregroundStyle(theme.textSecondary)
                Spacer()
                Text("\(intValue.wrappedValue) \(suffix)")
                    .foregroundStyle(theme.textPrimary)
            }
        }
        .tint(theme.accent)
    }
}

struct TDEECalculatorView: View {
    @Environment(\.appTheme) private var theme
    let profile: UserProfile

    /// Slice 5.3: the preview now comes from the shared `TDEECalculator`
    /// (via `TDEEPreview`) instead of a second inline copy of the formula,
    /// so it can never drift from the backend / GoalsView numbers.
    private var preview: TDEEPreview { TDEEPreview(profile: profile) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CÁLCULO TDEE")
                .font(theme.font.captionMedium).tracking(1.4)
                .foregroundStyle(theme.textTertiary)
            HStack(spacing: 10) {
                tile("BMR", value: "\(Int(preview.bmr))", color: theme.accentSecondary)
                tile("TDEE", value: "\(Int(preview.tdee))", color: theme.accent)
            }
            HStack(spacing: 10) {
                tile("Proteína", value: "\(preview.proteinG)g", color: theme.categoryColors[0])
                tile("Carbos", value: "\(preview.carbsG)g", color: theme.categoryColors[1])
                tile("Grasa", value: "\(preview.fatG)g", color: theme.categoryColors[2])
            }
        }
        .padding(16)
        .themedCard()
    }

    private func tile(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct GoalsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services

    /// The profile drives the TDEE that preset cards are computed against.
    @State private var profile: UserProfile = MockData.profile
    @State private var goal: NutritionGoal = MockData.goal
    @State private var selectedPreset: GoalPreset?
    @State private var mode: Int = 0   // 0: presets, 1: custom
    @State private var isSaving = false
    @State private var savedConfirmation = false

    /// TDEE for the loaded profile — preset cards apply their delta on top.
    private var tdee: Double {
        let bmr = TDEECalculator.bmr(
            weightKg: profile.weightKg, heightCm: profile.heightCm,
            age: profile.age, sex: profile.sex
        )
        return TDEECalculator.tdee(bmr: bmr, activity: profile.activity)
    }

    /// Slice 5.4: advisories from the shared GoalsViewModel.
    private var warnings: Set<GoalWarning> {
        GoalsViewModel.warnings(for: goal, sex: profile.sex, weightKg: profile.weightKg)
    }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 14) {
                    Picker("", selection: $mode) {
                        Text("goals.mode.presets").tag(0)
                        Text("goals.mode.custom").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if mode == 0 {
                        ForEach(GoalPreset.allCases, id: \.self) { preset in
                            presetCard(preset)
                                .onTapGesture { select(preset) }
                        }
                    } else {
                        customCard
                    }

                    saveButton
                    if savedConfirmation {
                        Text("goals.saved")
                            .font(theme.font.caption)
                            .foregroundStyle(theme.positive)
                    }
                    Spacer(minLength: 60)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Mis metas")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            profile = (try? await services.profile.profile()) ?? MockData.profile
            goal = (try? await services.profile.goal()) ?? MockData.goal
        }
    }

    private func select(_ preset: GoalPreset) {
        selectedPreset = preset
        savedConfirmation = false
        // Reflect the preset in the live goal so the user sees its macros.
        goal = GoalsViewModel.presetGoal(for: preset, tdee: tdee, weightKg: profile.weightKg)
    }

    private func presetCard(_ preset: GoalPreset) -> some View {
        let computed = GoalsViewModel.presetGoal(for: preset, tdee: tdee, weightKg: profile.weightKg)
        let isSelected = selectedPreset == preset
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: preset.labelKey))
                    .font(theme.font.titleCompact).foregroundStyle(theme.textPrimary)
                Text("\(computed.dailyCalories) kcal · \(String(localized: preset.hintKey))")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.accent)
                    .font(.system(size: 22))
            }
        }
        .padding(16)
        .themedCard()
        .overlay(
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .strokeBorder(isSelected ? theme.accent : .clear, lineWidth: 2)
        )
    }

    private var customCard: some View {
        VStack(spacing: 12) {
            customRow("goals.row.calories", value: $goal.dailyCalories, suffix: "kcal", step: 50, range: 1200...4500)
            customRow("goals.row.protein", value: $goal.proteinG, suffix: "g", step: 5, range: 60...300)
            customRow("goals.row.carbs",   value: $goal.carbsG,   suffix: "g", step: 5, range: 50...500)
            customRow("goals.row.fat",     value: $goal.fatG,     suffix: "g", step: 5, range: 30...200)
            if warnings.contains(.lowCalories) {
                Text("goals.warning.lowCalories")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.negative)
            }
            if warnings.contains(.lowProtein) {
                Text("goals.warning.lowProtein")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.negative)
            }
        }
        .padding(16)
        .themedCard()
        .onChange(of: goal) { savedConfirmation = false }
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack {
                if isSaving { ProgressView().tint(.white) }
                Text("goals.save").font(theme.font.bodyMedium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(theme.accent, in: RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous))
            .foregroundStyle(.white)
        }
        .disabled(isSaving)
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            // Preset mode with a selection → persist the preset (server
            // recomputes). Otherwise persist the custom macro override.
            if mode == 0, let preset = selectedPreset {
                try await services.profile.updatePreset(preset)
            } else {
                try await services.profile.updateGoal(goal)
            }
            savedConfirmation = true
        } catch {
            savedConfirmation = false
        }
    }

    private func customRow(_ labelKey: LocalizedStringKey, value: Binding<Int>, suffix: String, step: Int, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(labelKey).foregroundStyle(theme.textSecondary)
                Spacer()
                Text("\(value.wrappedValue) \(suffix)")
                    .foregroundStyle(theme.textPrimary)
            }
        }
        .tint(theme.accent)
    }
}
