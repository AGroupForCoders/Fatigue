import Foundation

/// Writes CSV the way RFC 4180 says: a field with a comma, a quote or a line break is wrapped in quotes,
/// and a quote inside it is doubled. Lines end in LF, which spreadsheets on every platform open fine.
nonisolated enum CSV {
    static func field(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func line(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",")
    }

    /// A header line followed by one line per row, each ending in LF.
    static func document(header: [String], rows: [[String]]) -> String {
        ([header] + rows).map { line($0) + "\n" }.joined()
    }
}

/// One set in the export, with every column already formatted.
/// Plain data so it can cross to a background task, where the file is written.
nonisolated struct ExportRow: Sendable, Equatable {
    var title: String
    var startTime: String
    var endTime: String
    var description: String
    var exerciseTitle: String
    var exerciseNotes: String
    var setIndex: Int
    var weightKg: String
    var reps: String
    var durationSeconds: String
    var rpe: String
    var brand: String
    var brandLabel: String
    var settings: String
    var weightedScore: String

    /// The column order. The first fourteen are Hevy's, with the same names, so the Hevy import can read
    /// this file too. Fatigue adds what Hevy doesn't have at the end.
    static let header = [
        "title", "start_time", "end_time", "description", "exercise_title", "superset_id", "exercise_notes",
        "set_index", "set_type", "weight_kg", "reps", "distance_km", "duration_seconds", "rpe",
        "brand", "brand_label", "settings", "weighted_score",
    ]

    /// Fatigue has no supersets, set types or distances, so those columns stay empty or read "normal".
    var fields: [String] {
        [
            title, startTime, endTime, description, exerciseTitle, "", exerciseNotes,
            String(setIndex), "normal", weightKg, reps, "", durationSeconds, rpe,
            brand, brandLabel, settings, weightedScore,
        ]
    }
}

/// Everything you've logged as one CSV with a row per set, for the share sheet on the profile.
nonisolated enum DataExport {
    /// Dates read like Hevy's, "13 Nov 2025, 07:30", in the time zone the phone is in.
    static func dateFormatter(timeZone: TimeZone = .current) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter
    }

    /// The file name, `fatigue-export-2025-11-13.csv`, dated in the phone's time zone.
    static func fileName(on date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "fatigue-export-\(formatter.string(from: date)).csv"
    }

    static func csv(_ rows: [ExportRow]) -> String {
        CSV.document(header: ExportRow.header, rows: rows.map(\.fields))
    }

    /// Writes the CSV to a file in the temporary folder and returns where it is. Any file from an earlier
    /// export with the same name is replaced.
    static func write(_ rows: [ExportRow], on date: Date, timeZone: TimeZone = .current) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: fileName(on: date, timeZone: timeZone))
        try csv(rows).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A number for a CSV cell: whole numbers without ".0", others rounded to two decimals.
    static func number(_ value: Double) -> String {
        PlainNumber.string((value * 100).rounded() / 100)
    }
}

extension FinishedWorkout {
    /// This workout as export rows, one per set, in the order you did them.
    /// `brandLabels` gives each exercise-and-brand's label, keyed like `ExerciseCatalog` keys setups: "Name|Brand".
    func exportRows(brandLabels: [String: String] = [:], timeZone: TimeZone = .current) -> [ExportRow] {
        let formatter = DataExport.dateFormatter(timeZone: timeZone)
        let start = formatter.string(from: startedAt)
        let end = formatter.string(from: startedAt.addingTimeInterval(duration))
        return exercises.flatMap { exercise in
            exercise.sets.enumerated().map { index, set in
                ExportRow(
                    title: title,
                    startTime: start,
                    endTime: end,
                    description: description,
                    exerciseTitle: exercise.name,
                    exerciseNotes: exercise.notes.map(\.text).joined(separator: "\n"),
                    setIndex: index,
                    weightKg: set.weight.trimmingCharacters(in: .whitespaces),
                    reps: set.kind == .reps ? set.amount.trimmingCharacters(in: .whitespaces) : "",
                    durationSeconds: set.kind == .hold ? set.amount.trimmingCharacters(in: .whitespaces) : "",
                    rpe: set.rpe.map(PlainNumber.string) ?? "",
                    brand: exercise.brand ?? "",
                    brandLabel: brandLabels["\(exercise.name)|\(exercise.brand ?? "")"] ?? "",
                    settings: exercise.settingsExport(for: set),
                    weightedScore: SetScore.score(of: set, in: exercise).map(DataExport.number) ?? ""
                )
            }
        }
    }
}

extension WorkoutExercise {
    /// The settings a set was done with, as "Seat=4; Notch=8; Dead stop=yes": the exercise's values with the
    /// set's overrides applied, in the order the settings show under the exercise name. A yes/no setting
    /// reads yes or no. Settings with no name or no value are left out.
    func settingsExport(for set: WorkoutSet) -> String {
        settings.compactMap { setting -> String? in
            let name = setting.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            let text: String
            switch setting.kind {
            case .number:
                guard let number = value(of: setting, in: set.setup) else { return nil }
                text = PlainNumber.string(number)
            case .yesNo:
                text = value(of: setting, in: set.setup) == 1 ? "yes" : "no"
            case .text:
                text = setting.value.trimmingCharacters(in: .whitespaces)
            }
            guard !text.isEmpty else { return nil }
            return "\(name)=\(text)"
        }
        .joined(separator: "; ")
    }
}
