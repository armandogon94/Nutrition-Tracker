//
//  WorkoutCSVExporterTests.swift
//  Slice 8.6: CSV export of workout history. Verifies the RFC 4180 quoting
//  edge cases, the column contract, and the privacy guarantee (no identity
//  fields ever leave in the file).
//

import Foundation
import Testing
@testable import FitTracker

@Suite("WorkoutCSVExporter")
struct WorkoutCSVExporterTests {

    private let benchId = UUID(uuidString: "00000000-0000-0000-0000-0000000B0001")!

    private func session(
        program: String = "PPL",
        day: String = "Push",
        start: Date = Date(timeIntervalSince1970: 1_700_000_000),
        durationMin: Int = 65,
        sets: [WorkoutSet]
    ) -> WorkoutSession {
        WorkoutSession(
            id: UUID(), startedAt: start,
            completedAt: start.addingTimeInterval(TimeInterval(durationMin * 60)),
            programName: program, dayName: day, sets: sets
        )
    }

    @Test("header row matches the documented column contract")
    func headerColumns() {
        let csv = WorkoutCSVExporter.makeCSV(sessions: [], exerciseNames: [:])
        let firstLine = csv.split(separator: "\r\n", omittingEmptySubsequences: false).first.map(String.init)
        #expect(firstLine == "date,program,exercise,set_number,weight_kg,reps,is_pr,duration_minutes")
    }

    @Test("one row per set, with resolved exercise name and PR flag")
    func rowPerSet() {
        let s = session(sets: [
            WorkoutSet(id: UUID(), exerciseId: benchId, setNumber: 1, weightKg: 80, reps: 8, isPR: true),
            WorkoutSet(id: UUID(), exerciseId: benchId, setNumber: 2, weightKg: 80, reps: 6, isPR: false)
        ])
        let csv = WorkoutCSVExporter.makeCSV(sessions: [s], exerciseNames: [benchId: "Bench Press"])
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.count == 3) // header + 2 sets
        #expect(lines[1].contains("Bench Press"))
        #expect(lines[1].contains("80"))
        #expect(lines[1].contains("true"))
        #expect(lines[2].contains("false"))
    }

    @Test("fields containing commas/quotes are RFC 4180 quoted; newlines too")
    func rfc4180Quoting() {
        // program carries a comma + embedded quote; exercise name carries a comma.
        let s = session(
            program: "Push, Pull \"Heavy\"",
            sets: [WorkoutSet(id: UUID(), exerciseId: benchId, setNumber: 1, weightKg: 100, reps: 5, isPR: false)]
        )
        let csv = WorkoutCSVExporter.makeCSV(sessions: [s], exerciseNames: [benchId: "Curl, bíceps"])
        // Comma + embedded quote in program → wrapped in quotes, inner quotes doubled.
        #expect(csv.contains("\"Push, Pull \"\"Heavy\"\"\""))
        // Comma in exercise name → quoted.
        #expect(csv.contains("\"Curl, bíceps\""))
        // Unit-level: a field with a newline is quoted by escapeField.
        #expect(WorkoutCSVExporter.escapeField("Día\n1") == "\"Día\n1\"")
    }

    @Test("plain fields are NOT quoted")
    func plainFieldsUnquoted() {
        let s = session(program: "PPL", day: "Push", sets: [
            WorkoutSet(id: UUID(), exerciseId: benchId, setNumber: 1, weightKg: 80, reps: 8, isPR: false)
        ])
        let csv = WorkoutCSVExporter.makeCSV(sessions: [s], exerciseNames: [benchId: "Bench"])
        // program "PPL" is plain → appears unquoted between commas.
        #expect(csv.contains(",PPL,"))
        #expect(!csv.contains("\"PPL\""))
        #expect(WorkoutCSVExporter.escapeField("PPL") == "PPL")
    }

    @Test("weight uses up to one decimal; bodyweight (0) renders as 0")
    func weightFormatting() {
        let s = session(sets: [
            WorkoutSet(id: UUID(), exerciseId: benchId, setNumber: 1, weightKg: 82.5, reps: 5, isPR: false),
            WorkoutSet(id: UUID(), exerciseId: benchId, setNumber: 2, weightKg: 0, reps: 15, isPR: false)
        ])
        let csv = WorkoutCSVExporter.makeCSV(sessions: [s], exerciseNames: [benchId: "Bench"])
        #expect(csv.contains(",82.5,5,"))
        #expect(csv.contains(",0,15,"))
    }

    @Test("rows are ordered newest session first, then by set number")
    func ordering() {
        let older = session(start: Date(timeIntervalSince1970: 1_600_000_000), sets: [
            WorkoutSet(id: UUID(), exerciseId: benchId, setNumber: 1, weightKg: 70, reps: 8, isPR: false)
        ])
        let newer = session(start: Date(timeIntervalSince1970: 1_700_000_000), sets: [
            WorkoutSet(id: UUID(), exerciseId: benchId, setNumber: 2, weightKg: 90, reps: 5, isPR: false),
            WorkoutSet(id: UUID(), exerciseId: benchId, setNumber: 1, weightKg: 90, reps: 6, isPR: false)
        ])
        let csv = WorkoutCSVExporter.makeCSV(sessions: [older, newer], exerciseNames: [benchId: "Bench"])
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        // Newer session first; within it set 1 before set 2.
        #expect(lines[1].contains(",1,90,6,"))
        #expect(lines[2].contains(",2,90,5,"))
        #expect(lines[3].contains(",1,70,8,"))
    }

    @Test("no identity fields (user id / email) appear anywhere in the output")
    func noIdentityLeak() {
        let s = session(sets: [
            WorkoutSet(id: UUID(), exerciseId: benchId, setNumber: 1, weightKg: 80, reps: 8, isPR: false)
        ])
        let csv = WorkoutCSVExporter.makeCSV(sessions: [s], exerciseNames: [benchId: "Bench"])
        let lower = csv.lowercased()
        #expect(!lower.contains("user_id"))
        #expect(!lower.contains("email"))
        #expect(!lower.contains("@"))
        // Session UUID must not appear either — only domain data.
        #expect(!csv.contains(s.id.uuidString))
    }

    @Test("writeCSV produces a .csv file URL whose contents round-trip")
    func writeToFile() throws {
        let s = session(sets: [
            WorkoutSet(id: UUID(), exerciseId: benchId, setNumber: 1, weightKg: 80, reps: 8, isPR: false)
        ])
        let url = try WorkoutCSVExporter.writeCSV(sessions: [s], exerciseNames: [benchId: "Bench"])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.pathExtension == "csv")
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.contains("Bench"))
        #expect(contents.hasPrefix("date,program,exercise"))
    }
}
