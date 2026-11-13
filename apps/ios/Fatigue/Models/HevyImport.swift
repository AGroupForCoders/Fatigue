import CryptoKit
import Foundation

// Reads the CSV that Hevy exports and turns each workout in it into a finished workout for history.
// Everything here is plain logic with no database or UI, so it can be tested on its own.

// MARK: - CSV

/// Reads and writes RFC 4180 CSV. Quoted fields may hold commas, newlines and doubled quotes.
nonisolated enum CSV {
    /// The rows of a CSV text, each as its fields. Empty lines are left out.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var fieldStarted = false
        let scalars = Array(text.unicodeScalars.drop(while: { $0 == "\u{FEFF}" }))
        var index = 0

        func endRow() {
            row.append(field)
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
            field = ""
            fieldStarted = false
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if inQuotes {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        field.unicodeScalars.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                }
            } else {
                switch scalar {
                case "\"" where !fieldStarted:
                    inQuotes = true
                    fieldStarted = true
                case ",":
                    row.append(field)
                    field = ""
                    fieldStarted = false
                case "\r":
                    if index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
                    endRow()
                case "\n":
                    endRow()
                default:
                    field.unicodeScalars.append(scalar)
                    fieldStarted = true
                }
            }
            index += 1
        }
        if fieldStarted || !row.isEmpty { endRow() }
        return rows
    }

    /// A field as it goes in a file: quoted when it holds a comma, a quote or a line break.
    static func field(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// One line of a file, without the line break.
    static func line(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",")
    }
}

// MARK: - Hevy's file

/// The columns in a Hevy workout export, one row per set. Export uses the same names, so the two files line up.
nonisolated enum HevyColumns {
    static let title = "title"
    static let startTime = "start_time"
    static let endTime = "end_time"
    static let description = "description"
    static let exerciseTitle = "exercise_title"
    static let supersetId = "superset_id"
    static let exerciseNotes = "exercise_notes"
    static let setIndex = "set_index"
    static let setType = "set_type"
    /// Which of the two appears follows the account's weight unit.
    static let weightKg = "weight_kg"
    static let weightLbs = "weight_lbs"
    static let reps = "reps"
    static let distanceKm = "distance_km"
    static let distanceMiles = "distance_miles"
    static let durationSeconds = "duration_seconds"
    static let rpe = "rpe"

    /// How Hevy writes a time, such as "13 Nov 2025, 07:30".
    static let dateFormat = "d MMM yyyy, HH:mm"
    static let kilogramsPerPound = 0.45359237

    /// Hevy's set types and what the data model calls them.
    static let setTypes: [String: String] = ["normal": "normal", "warmup": "warmup", "dropset": "drop", "failure": "failure"]
}

/// One set from the file, already in the app's units.
nonisolated struct HevySet: Equatable {
    var index: Int
    /// `normal`, `warmup`, `drop` or `failure`, as the data model names them.
    var type: String
    var weightKg: Double?
    var reps: Int?
    var durationSeconds: Int?
    var rpe: Double?

    /// A rep set when it has reps, a hold when it only has a time.
    var kind: String { reps != nil ? "reps" : "hold" }
}

nonisolated struct HevyExercise: Equatable {
    /// The name as Hevy writes it, such as "Bench Press (Barbell)".
    var title: String
    var notes: String
    var sets: [HevySet]
}

nonisolated struct HevyWorkout: Equatable {
    var title: String
    /// The start time as written in the file, which with the title tells one workout from another.
    var startTime: String
    var startedAt: Date
    var finishedAt: Date
    var description: String
    var exercises: [HevyExercise]

    /// What's stored on the workout row, so importing the file again finds it.
    var importKey: String { "hevy|\(startTime)|\(title)" }

    /// The same workout always gets the same id, so importing it twice can't make two.
    var id: UUID { DerivedID.uuid(importKey) }
}

nonisolated enum HevyImportError: LocalizedError, Equatable {
    case empty
    case missingColumns([String])
    case badDate(String)

    var errorDescription: String? {
        switch self {
        case .empty: "The file has no workouts in it."
        case .missingColumns(let names): "This doesn't look like a Hevy export. It's missing \(names.joined(separator: ", "))."
        case .badDate(let text): "Couldn't read the date \"\(text)\"."
        }
    }
}

nonisolated enum HevyImport {
    /// The workouts in a Hevy export, in the order they appear. Sets with neither reps nor a time,
    /// such as distance-only cardio, are left out, and so are exercises and workouts left empty by that.
    static func parse(_ csv: String) throws -> [HevyWorkout] {
        let rows = CSV.parse(csv)
        guard let header = rows.first else { throw HevyImportError.empty }
        let columns = Dictionary(header.enumerated().map { ($1.trimmingCharacters(in: .whitespaces).lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        let required = [HevyColumns.title, HevyColumns.startTime, HevyColumns.exerciseTitle, HevyColumns.setIndex]
        let missing = required.filter { columns[$0] == nil }
        guard missing.isEmpty else { throw HevyImportError.missingColumns(missing) }
        let weightColumn = columns[HevyColumns.weightKg] != nil ? HevyColumns.weightKg : HevyColumns.weightLbs
        let poundsToKg = weightColumn == HevyColumns.weightLbs

        var workouts: [HevyWorkout] = []
        var positions: [String: Int] = [:]
        for row in rows.dropFirst() {
            func value(_ column: String) -> String {
                guard let index = columns[column], index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespaces)
            }
            let title = value(HevyColumns.title)
            let startTime = value(HevyColumns.startTime)
            let key = "\(startTime)|\(title)"
            if positions[key] == nil {
                let startedAt = try date(startTime)
                let finishedAt = (try? date(value(HevyColumns.endTime))) ?? startedAt
                positions[key] = workouts.count
                workouts.append(HevyWorkout(
                    title: title.isEmpty ? "Workout" : title, startTime: startTime, startedAt: startedAt,
                    finishedAt: max(finishedAt, startedAt), description: value(HevyColumns.description), exercises: []
                ))
            }
            let position = positions[key]!

            let reps = Int(value(HevyColumns.reps)).flatMap { $0 > 0 ? $0 : nil }
            let duration = Double(value(HevyColumns.durationSeconds)).flatMap { $0 > 0 ? Int($0.rounded()) : nil }
            guard reps != nil || duration != nil else { continue }
            var weight = Double(value(weightColumn))
            if poundsToKg, let pounds = weight { weight = (pounds * HevyColumns.kilogramsPerPound * 100).rounded() / 100 }
            let set = HevySet(
                index: Int(value(HevyColumns.setIndex)) ?? 0,
                type: HevyColumns.setTypes[value(HevyColumns.setType).lowercased()] ?? "normal",
                weightKg: weight, reps: reps, durationSeconds: reps == nil ? duration : nil,
                rpe: Double(value(HevyColumns.rpe))
            )

            let exerciseTitle = value(HevyColumns.exerciseTitle)
            if let last = workouts[position].exercises.indices.last, workouts[position].exercises[last].title == exerciseTitle {
                workouts[position].exercises[last].sets.append(set)
            } else {
                workouts[position].exercises.append(HevyExercise(title: exerciseTitle, notes: value(HevyColumns.exerciseNotes), sets: [set]))
            }
        }
        for index in workouts.indices {
            for exercise in workouts[index].exercises.indices { workouts[index].exercises[exercise].sets.sort { $0.index < $1.index } }
        }
        return workouts.filter { !$0.exercises.isEmpty }
    }

    private static let formats = [HevyColumns.dateFormat, "d MMM yyyy, h:mm a", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss"]

    /// Hevy writes local times without a zone, so they're read in the phone's.
    static func date(_ text: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        if let date = try? Date(text, strategy: .iso8601) { return date }
        throw HevyImportError.badDate(text)
    }
}

extension HevyWorkout {
    /// This workout as it's stored, with Hevy's exercise names already turned into the app's.
    /// Every id comes from the workout's key, so a second import makes the very same rows.
    func stored(exerciseName: (String) -> String) -> StoredWorkout {
        StoredWorkout(
            id: id.uuidString, title: title, note: description.isEmpty ? nil : description,
            startedAt: startedAt, finishedAt: finishedAt, routineId: nil,
            exercises: exercises.enumerated().map { exerciseIndex, exercise in
                let exerciseId = DerivedID.uuid("\(importKey)|\(exerciseIndex)")
                return StoredExercise(
                    id: exerciseId.uuidString, name: exerciseName(exercise.title), brand: nil, restSeconds: 90, settings: [],
                    notes: exercise.notes.isEmpty ? [] : [StoredNote(id: DerivedID.uuid("\(importKey)|\(exerciseIndex)|note").uuidString, text: exercise.notes)],
                    sets: exercise.sets.enumerated().map { setIndex, set in
                        StoredSet(
                            id: DerivedID.uuid("\(importKey)|\(exerciseIndex)|\(setIndex)").uuidString, kind: set.kind,
                            weightKg: set.weightKg, reps: set.reps, durationSeconds: set.durationSeconds, rpe: set.rpe,
                            completedAt: Int64((finishedAt.timeIntervalSince1970 * 1000).rounded()), overrides: [:], setType: set.type
                        )
                    }
                )
            },
            importKey: importKey
        )
    }
}

// MARK: - Matching exercise names

/// Finds the exercise in the library that a Hevy name means.
enum HevyExerciseMatcher {
    /// Hevy names that don't match a built-in exercise by name alone, already simplified.
    static let aliases: [String: String] = [
        "seated cable row": "Seated Row",
        "seated row": "Seated Row",
        "lying leg curl": "Leg Curl",
        "seated leg curl": "Leg Curl",
        "overhead press": "Shoulder Press",
        "standing calf raise": "Calf Raise",
        "cable fly crossovers": "Cable Fly",
        "cable crossover": "Cable Fly",
        "chest fly": "Pec Deck",
        "butterfly": "Pec Deck",
        "rear delt reverse fly": "Rear Delt Fly",
        "reverse fly": "Rear Delt Fly",
        "incline bench press dumbbell": "Incline Dumbbell Press",
        "hip adduction": "Adductors",
        "hip abduction": "Abductors",
        "triceps rope pushdown": "Triceps Pushdown",
        "tricep pushdown": "Triceps Pushdown",
        "triceps extension cable": "Triceps Pushdown",
        "biceps curl": "Bicep Curl",
        "pull ups": "Pull Up",
        "pullup": "Pull Up",
        "iso lateral chest press": "Chest Press",
        "incline chest press": "Chest Press",
        "deadlift trap bar": "Deadlift",
        "hack squat machine": "Hack Squat",
    ]

    /// The name in lower case, without punctuation or anything in brackets, such as "bench press" for "Bench Press (Barbell)".
    static func simplified(_ name: String) -> String {
        words(stripping: name, brackets: true)
    }

    /// The name in lower case with the bracketed part kept, such as "bench press barbell".
    static func simplifiedWithEquipment(_ name: String) -> String {
        words(stripping: name, brackets: false)
    }

    private static func words(stripping name: String, brackets: Bool) -> String {
        var text = ""
        var depth = 0
        for scalar in name.unicodeScalars {
            switch scalar {
            case "(", "[":
                depth += 1
                text.unicodeScalars.append(" ")
            case ")", "]":
                depth = max(0, depth - 1)
                text.unicodeScalars.append(" ")
            default:
                if depth > 0 && brackets { continue }
                text.unicodeScalars.append(CharacterSet.alphanumerics.contains(scalar) ? scalar : " ")
            }
        }
        return text.lowercased().split(separator: " ").joined(separator: " ")
    }

    /// The library name a Hevy name means, or nil when nothing fits. `names` is every exercise
    /// in the library, built in and custom, so an exercise made by an earlier import matches again.
    static func match(_ hevyName: String, among names: [String]) -> String? {
        let available = Dictionary(names.map { (simplified($0), $0) }, uniquingKeysWith: { a, _ in a })
        let availableWithEquipment = Dictionary(names.map { (simplifiedWithEquipment($0), $0) }, uniquingKeysWith: { a, _ in a })
        let withEquipment = simplifiedWithEquipment(hevyName)
        let plain = simplified(hevyName)
        if let name = availableWithEquipment[withEquipment] { return name }
        if let alias = aliases[withEquipment] ?? aliases[plain], let name = available[simplified(alias)] { return name }
        return available[plain]
    }

    /// A custom exercise for a Hevy name nothing matched, with the kit read from the brackets
    /// and a muscle guessed from the name. Both can be corrected on the exercise page.
    static func customExercise(named name: String) -> ExerciseInfo {
        ExerciseInfo(name: name, equipment: equipment(in: name), primaryMuscle: muscle(in: name), isCustom: true)
    }

    static func equipment(in name: String) -> Equipment {
        let text = simplifiedWithEquipment(name)
        if text.contains("barbell") || text.contains("smith") { return .barbell }
        if text.contains("dumbbell") || text.contains("kettlebell") { return .dumbbell }
        if text.contains("cable") { return .cable }
        if text.contains("machine") { return .machine }
        if text.contains("bodyweight") || text.contains("weighted") || text.contains("assisted") { return .bodyweight }
        return .other
    }

    private static let muscleHints: [(Muscle, [String])] = [
        (.hamstrings, ["leg curl", "hamstring", "romanian", "nordic", "good morning"]),
        (.quadriceps, ["squat", "leg press", "leg extension", "lunge", "step up", "split squat"]),
        (.lowerBack, ["deadlift", "back extension", "hyperextension"]),
        (.glutes, ["hip thrust", "glute", "kickback", "bridge"]),
        (.calves, ["calf"]),
        (.adductors, ["adduct"]),
        (.abductors, ["abduct"]),
        (.lats, ["pull up", "chin up", "pulldown", "pull down", "lat ", "pullover"]),
        (.middleBack, ["row", "face pull"]),
        (.traps, ["shrug"]),
        (.triceps, ["tricep", "skullcrusher", "skull crusher", "pushdown", "dip", "close grip"]),
        (.biceps, ["curl"]),
        (.forearms, ["wrist", "forearm", "farmer", "grip"]),
        (.shoulders, ["shoulder", "overhead", "lateral raise", "front raise", "rear delt", "reverse fly", "arnold", "upright"]),
        (.chest, ["bench", "chest", "fly", "push up", "pushup"]),
        (.abdominals, ["crunch", "plank", "sit up", "situp", "leg raise", "ab ", "abs", "russian twist", "dead bug"]),
        (.neck, ["neck"]),
    ]

    /// The muscle a name points at, such as biceps for anything with "curl", or chest when nothing does.
    static func muscle(in name: String) -> Muscle {
        let text = " " + simplified(name) + " "
        for (muscle, hints) in muscleHints where hints.contains(where: { text.contains($0) }) { return muscle }
        return .chest
    }
}

// MARK: - Ids built from content

/// A UUIDv5: the same name always gives the same id, as the data model asks of rows that must be unique.
nonisolated enum DerivedID {
    /// The namespace for everything the app derives, chosen once at random.
    private static let namespace: [UInt8] = [0x6b, 0x1f, 0x2a, 0x9c, 0x3d, 0x4e, 0x5f, 0x60, 0x87, 0x18, 0x29, 0x3a, 0x4b, 0x5c, 0x6d, 0x7e]

    static func uuid(_ name: String) -> UUID {
        var hasher = Insecure.SHA1()
        hasher.update(data: Data(namespace))
        hasher.update(data: Data(name.utf8))
        var bytes = Array(hasher.finalize().prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// What importing a Hevy export did, for the screen shown after.
struct HevyImportResult: Equatable {
    var imported = 0
    /// Workouts the file had that were already in history, from an earlier import.
    var alreadyThere = 0
    /// Hevy exercises that matched nothing in the library, now custom exercises, in the order they appeared.
    var newExercises: [String] = []
}
