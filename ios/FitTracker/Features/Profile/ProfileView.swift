//
//  ProfileView.swift
//  Slice 0.5 mock — profile form with live TDEE preview.
//

import SwiftUI

struct ProfileView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services

    @State private var profile: UserProfile = MockData.profile

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    formCard
                    TDEECalculatorView(profile: profile)
                    NavigationLink {
                        GoalsView()
                    } label: {
                        HStack {
                            Image(systemName: "target")
                            Text("Mis metas")
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

    private var bmr: Double {
        // Mifflin-St Jeor
        let base = 10 * profile.weightKg + 6.25 * profile.heightCm - 5 * Double(profile.age)
        return profile.sex == .male ? base + 5 : base - 161
    }
    private var tdee: Double { bmr * profile.activity.multiplier }
    private var protein: Int { Int(profile.weightKg * 2) }
    private var fat: Int { Int(tdee * 0.25 / 9) }
    private var carbs: Int { Int((tdee - Double(protein * 4) - Double(fat * 9)) / 4) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CÁLCULO TDEE")
                .font(theme.font.captionMedium).tracking(1.4)
                .foregroundStyle(theme.textTertiary)
            HStack(spacing: 10) {
                tile("BMR", value: "\(Int(bmr))", color: theme.accentSecondary)
                tile("TDEE", value: "\(Int(tdee))", color: theme.accent)
            }
            HStack(spacing: 10) {
                tile("Proteína", value: "\(protein)g", color: theme.categoryColors[0])
                tile("Carbos", value: "\(carbs)g", color: theme.categoryColors[1])
                tile("Grasa", value: "\(fat)g", color: theme.categoryColors[2])
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
    @State private var goal: NutritionGoal = MockData.goal
    @State private var mode: Int = 0   // 0: presets, 1: custom

    private let presets: [(label: String, calories: Int, hint: String)] = [
        ("Pérdida de grasa", 1900, "−500 kcal"),
        ("Mantenimiento",    2400, "0 kcal"),
        ("Volumen ligero",   2650, "+250 kcal"),
        ("Ganancia muscular",2900, "+500 kcal")
    ]

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 14) {
                    Picker("", selection: $mode) {
                        Text("Preestablecidos").tag(0)
                        Text("Personalizar").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if mode == 0 {
                        ForEach(0..<presets.count, id: \.self) { i in
                            presetCard(label: presets[i].label,
                                       calories: presets[i].calories,
                                       hint: presets[i].hint,
                                       isSelected: goal.dailyCalories == presets[i].calories)
                                .onTapGesture {
                                    goal.dailyCalories = presets[i].calories
                                }
                        }
                    } else {
                        customCard
                    }
                    Spacer(minLength: 60)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Mis metas")
        .navigationBarTitleDisplayMode(.inline)
        .task { goal = (try? await services.profile.goal()) ?? MockData.goal }
    }

    private func presetCard(label: String, calories: Int, hint: String, isSelected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(theme.font.titleCompact).foregroundStyle(theme.textPrimary)
                Text("\(calories) kcal · \(hint)")
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
            customRow("Calorías", value: $goal.dailyCalories, suffix: "kcal", step: 50, range: 1200...4500)
            customRow("Proteína", value: $goal.proteinG, suffix: "g", step: 5, range: 60...300)
            customRow("Carbos",   value: $goal.carbsG,   suffix: "g", step: 5, range: 50...500)
            customRow("Grasa",    value: $goal.fatG,     suffix: "g", step: 5, range: 30...200)
            if Double(goal.dailyCalories) < 1200 {
                Text("Meta menor a 1200 kcal — consulta a un profesional")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.negative)
            }
        }
        .padding(16)
        .themedCard()
    }

    private func customRow(_ label: String, value: Binding<Int>, suffix: String, step: Int, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(label).foregroundStyle(theme.textSecondary)
                Spacer()
                Text("\(value.wrappedValue) \(suffix)")
                    .foregroundStyle(theme.textPrimary)
            }
        }
        .tint(theme.accent)
    }
}
