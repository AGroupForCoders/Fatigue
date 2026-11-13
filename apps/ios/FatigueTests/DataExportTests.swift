import Foundation
import Testing
@testable import Fatigue

@MainActor
struct DataExportTests {
    private let utc = TimeZone(identifier: "UTC")!
    /// 13 Nov 2025, 07:30 UTC.
    private let start = Date(timeIntervalSince1970: 1_763_019_000)

    /// Leg day from the mock-ups: a hold at notch 8 with a dead stop, then a plain rep set, then an unbranded exercise.
    private var workout: FinishedWorkout {
        FinishedWorkout(title: "Leg day", description: "Knee felt fine, \"finally\"", startedAt: start, duration: 52 * 60, exercises: [
            WorkoutExercise(
                name: "Adductors", brand: "Technogym", restSeconds: 120,
                notes: [ExerciseNote(text: "Pads wide"), ExerciseNote(text: "Slow eccentric")],
                settings: ExerciseCatalog.sampleAdductorSettings,
                sets: [
                    WorkoutSet(setup: SetSetup(kind: .hold, values: ["Notch": 8]), weight: "40", amount: "45", rpe: 8, previous: "", isDone: true),
                    WorkoutSet(setup: SetSetup(kind: .reps), weight: "55", amount: "8", rpe: 8.5, previous: "", isDone: true),
                ]
            ),
            WorkoutExercise(name: "Leg Press", brand: nil, restSeconds: 90, sets: [
                WorkoutSet(setup: SetSetup(kind: .reps), weight: "", amount: "12", previous: "", isDone: true),
            ]),
        ])
    }

    // MARK: The CSV writer

    @Test func plainFieldsAreLeftAlone() {
        #expect(CSV.field("Leg day") == "Leg day")
        #expect(CSV.field("") == "")
        #expect(CSV.line(["a", "b", ""]) == "a,b,")
    }

    @Test func fieldsWithCommasQuotesOrLineBreaksAreQuoted() {
        #expect(CSV.field("Deload, knee fine") == "\"Deload, knee fine\"")
        #expect(CSV.field("the \"big\" one") == "\"the \"\"big\"\" one\"")
        #expect(CSV.field("line one\nline two") == "\"line one\nline two\"")
        #expect(CSV.field("line one\r\nline two") == "\"line one\r\nline two\"")
    }

    @Test func documentHasAHeaderAndOneLineARowEndingInLF() {
        let csv = CSV.document(header: ["a", "b"], rows: [["1", "x,y"], ["2", ""]])
        #expect(csv == "a,b\n1,\"x,y\"\n2,\n")
    }

    // MARK: Rows from a workout

    @Test func oneRowPerSetInTheOrderTheyWereDone() {
        let rows = workout.exportRows(timeZone: utc)
        #expect(rows.count == 3)
        #expect(rows.map(\.exerciseTitle) == ["Adductors", "Adductors", "Leg Press"])
        #expect(rows.map(\.setIndex) == [0, 1, 0])
    }

    @Test func workoutColumnsReadLikeHevys() throws {
        let row = try #require(workout.exportRows(timeZone: utc).first)
        #expect(row.title == "Leg day")
        #expect(row.startTime == "13 Nov 2025, 07:30")
        #expect(row.endTime == "13 Nov 2025, 08:22")
        #expect(row.description == "Knee felt fine, \"finally\"")
        #expect(row.exerciseNotes == "Pads wide\nSlow eccentric")
    }

    @Test func aHoldFillsDurationAndARepSetFillsReps() {
        let rows = workout.exportRows(timeZone: utc)
        #expect(rows[0].weightKg == "40")
        #expect(rows[0].reps == "")
        #expect(rows[0].durationSeconds == "45")
        #expect(rows[0].rpe == "8")
        #expect(rows[1].weightKg == "55")
        #expect(rows[1].reps == "8")
        #expect(rows[1].durationSeconds == "")
        #expect(rows[1].rpe == "8.5")
    }

    @Test func anUnloadedSetWithNoRPELeavesThoseCellsEmpty() {
        let row = workout.exportRows(timeZone: utc)[2]
        #expect(row.weightKg == "")
        #expect(row.reps == "12")
        #expect(row.rpe == "")
        #expect(row.brand == "")
        #expect(row.settings == "")
    }

    @Test func settingsUseTheSetsOverridesOverTheExercisesValues() {
        let rows = workout.exportRows(timeZone: utc)
        #expect(rows[0].settings == "Seat=4; Notch=8; Dead stop=yes")
        #expect(rows[1].settings == "Seat=4; Notch=7; Dead stop=yes")
    }

    @Test func brandAndLabelComeFromTheExercisesBrand() {
        var labelled = workout
        labelled.exercises[0].brand = Brand(name: "Technogym", label: "Selection 700")
        let rows = labelled.exportRows(timeZone: utc)
        #expect(rows[0].brand == "Technogym")
        #expect(rows[0].brandLabel == "Selection 700")
        #expect(rows[2].brandLabel == "")
    }

    @Test func setTypesUseHevysNames() {
        var typed = workout
        typed.exercises[0].sets[0].type = .warmup
        typed.exercises[0].sets[1].type = .drop
        let rows = typed.exportRows(timeZone: utc)
        #expect(rows[0].fields[8] == "warmup")
        #expect(rows[1].fields[8] == "dropset")
        #expect(rows[2].fields[8] == "normal")
    }

    @Test func weightedScoreMatchesTheSetScore() {
        let rows = workout.exportRows(timeZone: utc)
        // 40 × 45 s, notch 8 of 1–10 (×1.78) with a dead stop (×1.5), capped at ×3 → 1800 × 2.67.
        #expect(rows[0].weightedScore == "4800")
        // 55 × 8 at notch 7 (×1.67) with a dead stop (×1.5) → 440 × 2.5.
        #expect(rows[1].weightedScore == "1100")
        // Unloaded counts as 1 kg.
        #expect(rows[2].weightedScore == "12")
    }

    @Test func theFileStartsWithHevysColumnsThenFatigues() {
        let csv = DataExport.csv(workout.exportRows(timeZone: utc))
        let header = "title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe,brand,brand_label,settings,weighted_score"
        let firstRow = "Leg day,\"13 Nov 2025, 07:30\",\"13 Nov 2025, 08:22\",\"Knee felt fine, \"\"finally\"\"\",Adductors,,\"Pads wide\nSlow eccentric\",0,normal,40,,,45,8,Technogym,,Seat=4; Notch=8; Dead stop=yes,4800"
        #expect(csv.hasPrefix(header + "\n" + firstRow + "\n"))
    }

    @Test func fileNameCarriesTheDate() {
        #expect(DataExport.fileName(on: start, timeZone: utc) == "fatigue-export-2025-11-13.csv")
    }

    @Test func writingMakesAFileYouCanReadBack() throws {
        let url = try DataExport.write(workout.exportRows(timeZone: utc), on: start, timeZone: utc)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.lastPathComponent == "fatigue-export-2025-11-13.csv")
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.hasPrefix("title,start_time"))
        #expect(contents.hasSuffix("\n"))
        // Header, 3 rows, the trailing LF, and the line break in the Adductors notes, which repeat on both of its rows.
        #expect(contents.components(separatedBy: "\n").count == 7)
    }
}
