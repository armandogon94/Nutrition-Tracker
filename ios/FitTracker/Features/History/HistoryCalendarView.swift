//
//  HistoryCalendarView.swift
//  Slice 8.2: month calendar with a dot on every day that has a logged
//  workout. Tapping a day reveals that day's sessions below the grid; each
//  row pushes a SessionDetailView. Month navigation is local state driven
//  by the immutable `CalendarMonth` value type (unit-tested separately).
//

import SwiftUI

struct HistoryCalendarView: View {
    @Environment(\.appTheme) private var theme
    let sessions: [WorkoutSession]
    let exerciseNames: [UUID: String]

    @State private var month: CalendarMonth
    @State private var selectedDay: Int?

    private static var esCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday-first (Latin America convention)
        return cal
    }
    private let locale = Locale(identifier: "es_419")

    init(sessions: [WorkoutSession], exerciseNames: [UUID: String]) {
        self.sessions = sessions
        self.exerciseNames = exerciseNames
        _month = State(initialValue: CalendarMonth(
            monthContaining: Date(),
            calendar: Self.esCalendar,
            daysWithSessions: sessions.map(\.startedAt)
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            weekdayHeader
            grid
            if let selectedDay { daySessions(for: selectedDay) }
        }
        .padding(16)
        .themedCard()
        .onChange(of: sessions) { _, newValue in
            // Rebuild the month when data arrives, preserving the visible month.
            month = CalendarMonth(monthContaining: month.firstOfMonth,
                                  calendar: Self.esCalendar,
                                  daysWithSessions: newValue.map(\.startedAt))
        }
    }

    // MARK: - Header + weekday labels

    private var header: some View {
        HStack {
            Text(month.title(locale: locale))
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Button {
                selectedDay = nil
                month = month.previousMonth()
            } label: {
                Image(systemName: "chevron.left").padding(8)
            }
            .accessibilityLabel(Text("history.calendar.previousMonth"))
            Button {
                selectedDay = nil
                month = month.nextMonth()
            } label: {
                Image(systemName: "chevron.right").padding(8)
            }
            .accessibilityLabel(Text("history.calendar.nextMonth"))
        }
        .foregroundStyle(theme.accent)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { sym in
                Text(sym)
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    /// Monday-first short weekday symbols in Spanish (L M M J V S D).
    private var weekdaySymbols: [String] {
        ["L", "M", "M", "J", "V", "S", "D"]
    }

    // MARK: - Grid

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(0..<month.leadingBlankCount, id: \.self) { _ in
                Color.clear.frame(height: 40)
            }
            ForEach(1...month.dayCount, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Int) -> some View {
        let hasSession = month.hasSession(day: day)
        let isSelected = selectedDay == day
        return Button {
            selectedDay = (selectedDay == day) ? nil : day
        } label: {
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(theme.font.body)
                    .foregroundStyle(hasSession ? theme.textPrimary : theme.textSecondary)
                Circle()
                    .fill(hasSession ? theme.accent : .clear)
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? theme.accent.opacity(0.18) : .clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasSession)
        .accessibilityLabel(accessibilityLabel(day: day, hasSession: hasSession))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func accessibilityLabel(day: Int, hasSession: Bool) -> Text {
        guard let date = month.date(forDay: day) else { return Text("\(day)") }
        let df = Date.FormatStyle.dateTime.day().month(.wide).locale(locale)
        let dateStr = date.formatted(df)
        return hasSession
            ? Text("\(dateStr) — ") + Text("history.calendar.hasWorkout")
            : Text(dateStr)
    }

    // MARK: - Selected day's sessions

    @ViewBuilder
    private func daySessions(for day: Int) -> some View {
        let daysSessions = sessions(on: day)
        Divider().opacity(0.18).padding(.vertical, 4)
        if daysSessions.isEmpty {
            Text("history.calendar.noSessions")
                .font(theme.font.body)
                .foregroundStyle(theme.textTertiary)
        } else {
            VStack(spacing: 8) {
                ForEach(daysSessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session, exerciseNames: exerciseNames)
                    } label: {
                        sessionRow(session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sessionRow(_ session: WorkoutSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .foregroundStyle(theme.accent)
                .frame(width: 32, height: 32)
                .background(theme.accent.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.programName) · \(session.dayName)")
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(theme.textPrimary)
                Text("\(session.sets.count) ") + Text("history.session.setsSuffix")
            }
            .font(theme.font.caption)
            .foregroundStyle(theme.textTertiary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func sessions(on day: Int) -> [WorkoutSession] {
        guard let date = month.date(forDay: day) else { return [] }
        return sessions
            .filter { Self.esCalendar.isDate($0.startedAt, inSameDayAs: date) }
            .sorted { $0.startedAt > $1.startedAt }
    }
}
