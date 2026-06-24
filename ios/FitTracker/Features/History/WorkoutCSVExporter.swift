//
//  WorkoutCSVExporter.swift
//  Slice 8.6: export workout history as an RFC 4180 CSV for hand-off to a
//  spreadsheet (Numbers / Google Sheets) via the system Share Sheet.
//
//  Lives in Features/History (not Core/Export) to stay inside the Slice 8
//  file-ownership boundary; it has no dependencies beyond the domain
//  structs so it can move later if a shared Core/Export home is created.
//
//  Privacy (per the Slice 8 plan): the file contains the user's own
//  training data ONLY. No user id, email, session id, or any identity
//  field is ever written. A unit test asserts this guarantee.
//
//  Column contract (header row, in order):
//    date, program, exercise, set_number, weight_kg, reps, is_pr,
//    duration_minutes
//
//  Skills invoked: everything-claude-code:swiftui-patterns,
//  security-and-hardening (output sanitisation + RFC 4180 quoting).
//

import Foundation

enum WorkoutCSVExporter {

    /// Documented column header, comma-joined. Stable contract — tests pin it.
    static let header = "date,program,exercise,set_number,weight_kg,reps,is_pr,duration_minutes"

    /// ISO-8601 (e.g. `2026-06-04`) keeps the date locale-independent and
    /// unambiguous for spreadsheets. Date only — time of day is noise here.
    /// `nonisolated(unsafe)`: ISO8601DateFormatter is documented thread-safe
    /// for reads once configured — same pattern as `APIClient`'s formatters.
    nonisolated(unsafe) private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Build the full CSV document. Rows are ordered newest session first,
    /// then by ascending set number within a session.
    static func makeCSV(sessions: [WorkoutSession], exerciseNames: [UUID: String]) -> String {
        var rows: [String] = [header]

        let ordered = sessions.sorted { $0.startedAt > $1.startedAt }
        for session in ordered {
            let date = dateFormatter.string(from: session.startedAt)
            let duration = session.durationMinutes.map(String.init) ?? ""
            let setsInOrder = session.sets.sorted { $0.setNumber < $1.setNumber }
            for set in setsInOrder {
                let name = exerciseNames[set.exerciseId] ?? "—"
                let fields = [
                    date,
                    session.programName,
                    name,
                    String(set.setNumber),
                    formatWeight(set.weightKg),
                    String(set.reps),
                    set.isPR ? "true" : "false",
                    duration
                ]
                rows.append(fields.map(escapeField).joined(separator: ","))
            }
        }
        // RFC 4180 uses CRLF line breaks; trailing CRLF terminates the file.
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    /// Write the CSV to a uniquely-named temp file and return its URL for
    /// `ShareLink(item:)`. UTF-8, no BOM (Numbers/Sheets read it fine).
    static func writeCSV(sessions: [WorkoutSession],
                         exerciseNames: [UUID: String],
                         fileName: String = "fittracker-historial") throws -> URL {
        let csv = makeCSV(sessions: sessions, exerciseNames: exerciseNames)
        let stamp = dateFormatter.string(from: Date())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileName)-\(stamp)", conformingTo: .commaSeparatedText)
        try csv.data(using: .utf8)!.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Helpers

    /// RFC 4180: a field is quoted iff it contains a comma, double-quote, CR,
    /// or LF. Inner double-quotes are escaped by doubling them.
    static func escapeField(_ field: String) -> String {
        let needsQuoting = field.contains(",") || field.contains("\"")
            || field.contains("\n") || field.contains("\r")
        guard needsQuoting else { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    /// Whole numbers render without a decimal (`80`, `0`); fractional weights
    /// keep up to one decimal (`82.5`). Matches the gym-log convention of
    /// 0.5 kg plate increments.
    static func formatWeight(_ weight: Double) -> String {
        if weight == weight.rounded() {
            return String(Int(weight))
        }
        return String(format: "%.1f", weight)
    }
}
