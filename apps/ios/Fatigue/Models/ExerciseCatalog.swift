import Foundation
import Observation

/// What kind of kit an exercise uses.
enum Equipment: String, CaseIterable, Hashable {
    case machine, cable, barbell, dumbbell, bodyweight, other
    var name: String { rawValue.capitalized }
}

/// The fixed muscle list from the data model, matching free-exercise-db.
enum Muscle: String, CaseIterable, Hashable {
    case abdominals, abductors, adductors, biceps, calves, chest, forearms, glutes, hamstrings, lats
    case lowerBack = "lower back", middleBack = "middle back", neck, quadriceps, shoulders, traps, triceps

    var name: String { rawValue.capitalized }
}

/// An exercise in the library: what it's called, what it uses and what it works.
struct ExerciseInfo: Identifiable, Equatable {
    var name: String
    var equipment: Equipment
    /// The main muscle, with a share of 1.
    var primaryMuscle: Muscle
    /// Other muscles it works, with a share of 0.5 each to start.
    var secondaryMuscles: [Muscle] = []
    var isCustom = false
    var id: String { name }
}

/// The settings saved for one exercise on one brand, with their values from last time.
/// They never carry over between brands: Technogym adductors have notches, a Hammer Strength one may not.
struct BrandSetup: Equatable {
    var settings: [ExerciseSetting] = []
}

/// The exercise library, plus the settings saved for each exercise and brand.
/// Lives in memory until the local database exists.
@Observable
final class ExerciseCatalog {
    private(set) var exercises: [ExerciseInfo]
    private var setups: [String: BrandSetup]
    /// Where changes are saved. Nil keeps them in memory, as tests and previews do.
    private var database: AppDatabase?

    /// Every saved exercise-and-brand's settings, keyed "Adductors|Technogym", or "Adductors|Technogym|City gym"
    /// with a label (see `Brand.key`).
    var savedSetups: [String: BrandSetup] { setups }

    /// The library as saved on the phone.
    static func load(from database: AppDatabase) -> ExerciseCatalog {
        let catalog = ExerciseCatalog(stored: (try? database.library()) ?? StoredLibrary())
        catalog.database = database
        return catalog
    }

    private func persist() {
        guard let database else { return }
        let stored = stored
        try? database.save(stored)
    }

    init(exercises: [ExerciseInfo] = ExerciseCatalog.builtIn, setups: [String: BrandSetup] = ExerciseCatalog.sampleSetups) {
        self.exercises = exercises.sorted { $0.name < $1.name }
        self.setups = setups
    }

    var names: [String] { exercises.map(\.name) }

    func info(named name: String) -> ExerciseInfo? {
        exercises.first { $0.name == name }
    }

    /// The brands with settings saved for an exercise.
    func brands(for name: String) -> [Brand] {
        setups.keys.compactMap { key in
            let parsed = Self.parse(key: key)
            return parsed.name == name ? parsed.brand : nil
        }
    }

    func setup(for name: String, brand: Brand?) -> BrandSetup {
        setups[Self.key(name, brand)] ?? BrandSetup()
    }

    /// Saves an exercise and the settings for one of its brands.
    /// Renaming a custom exercise moves everything saved under the old name.
    func save(_ info: ExerciseInfo, renamedFrom oldName: String? = nil, brand: Brand?, setup: BrandSetup) {
        let oldName = oldName ?? info.name
        if let index = exercises.firstIndex(where: { $0.name == oldName }) {
            exercises[index] = info
        } else {
            exercises.append(info)
        }
        exercises.sort { $0.name < $1.name }
        if oldName != info.name {
            for (key, value) in setups where key.hasPrefix(oldName + "|") {
                setups[key] = nil
                setups[info.name + key.dropFirst(oldName.count)] = value
            }
            // Before saving the library, which finds exercises by name and would add the new name as another exercise.
            try? database?.renameExercise(from: oldName, to: info.name)
        }
        setups[Self.key(info.name, brand)] = setup
        persist()
    }

    /// Saves settings for other brands of an exercise, edited alongside the one being used. Nil is no brand.
    func save(_ setups: [Brand?: BrandSetup], for name: String) {
        guard !setups.isEmpty else { return }
        for (brand, setup) in setups { self.setups[Self.key(name, brand)] = setup }
        persist()
    }

    /// Remembers the settings for an exercise on a brand, such as after you add a row on the workout screen.
    func saveSettings(_ settings: [ExerciseSetting], for name: String, brand: Brand?) {
        let named = settings.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        guard setups[Self.key(name, brand)]?.settings != named else { return }
        setups[Self.key(name, brand), default: BrandSetup()].settings = named
        persist()
    }

    /// Moves the settings saved for an exercise on one brand onto another, as part of moving its history
    /// (see `WorkoutStore.moveBrand`). Settings both brands have keep the destination's; the rest come along.
    /// With a database the move is done there, and the library is read back.
    func moveBrand(for name: String, from: Brand?, to: Brand?) {
        guard from != to else { return }
        if let database {
            try? database.moveBrand(exercise: name, from: from, to: to)
            let reloaded = ExerciseCatalog(stored: (try? database.library()) ?? StoredLibrary())
            exercises = reloaded.exercises
            setups = reloaded.setups
            return
        }
        guard let source = setups.removeValue(forKey: Self.key(name, from)) else { return }
        var merged = setups[Self.key(name, to)] ?? BrandSetup()
        for setting in source.settings where !merged.settings.contains(where: { $0.name.caseInsensitiveCompare(setting.name) == .orderedSame }) {
            merged.settings.append(setting)
        }
        setups[Self.key(name, to)] = merged
    }

    /// Changes a yes/no setting's factor in what's saved for an exercise and brand, so the next workout there
    /// scores with it. Nil makes the setting stop counting.
    func setFactor(_ factor: Double?, ofSetting setting: String, for name: String, brand: Brand?) {
        let key = Self.key(name, brand)
        guard var setup = setups[key],
              let index = setup.settings.firstIndex(where: { $0.name == setting && $0.kind == .yesNo }),
              setup.settings[index].factor != factor else { return }
        setup.settings[index].factor = factor
        setups[key] = setup
        persist()
    }

    /// Takes a custom exercise out of the library. It's marked deleted rather than removed, so workouts
    /// that used it keep their sets and still show its name. Built-in exercises can't be deleted.
    @discardableResult
    func delete(exerciseNamed name: String) -> Bool {
        guard let index = exercises.firstIndex(where: { $0.name == name }), exercises[index].isCustom else { return false }
        exercises.remove(at: index)
        for key in setups.keys where key.hasPrefix(name + "|") { setups[key] = nil }
        try? database?.deleteExercise(named: name)
        return true
    }

    /// The exercise's name, "|", then the brand's key, which `parse(key:)` reads back.
    static func key(_ name: String, _ brand: Brand?) -> String { "\(name)|\(brand?.key ?? "")" }

    /// The exercise name and brand a setup key stands for.
    static func parse(key: String) -> (name: String, brand: Brand?) {
        let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        return (String(parts[0]), parts.count > 1 ? Brand(key: String(parts[1])) : nil)
    }
}

extension ExerciseCatalog {
    static let sampleAdductorSettings = [
        ExerciseSetting(name: "Seat", value: "4"),
        ExerciseSetting(name: "Notch", value: "7", direction: .higher, rangeMin: 1, rangeMax: 10, splitByValue: true),
        ExerciseSetting(name: "Dead stop", kind: .yesNo, value: "yes", factor: 1.5),
    ]

    static let sampleSetups: [String: BrandSetup] = [
        "Adductors|Technogym": BrandSetup(settings: sampleAdductorSettings),
    ]

    /// The built-in exercises for the spike. The real list is seeded from free-exercise-db.
    static let builtIn: [ExerciseInfo] = [
        ExerciseInfo(name: "Abductors", equipment: .machine, primaryMuscle: .abductors, secondaryMuscles: [.glutes]),
        ExerciseInfo(name: "Adductors", equipment: .machine, primaryMuscle: .adductors),
        ExerciseInfo(name: "Bench Press", equipment: .barbell, primaryMuscle: .chest, secondaryMuscles: [.shoulders, .triceps]),
        ExerciseInfo(name: "Bicep Curl", equipment: .dumbbell, primaryMuscle: .biceps, secondaryMuscles: [.forearms]),
        ExerciseInfo(name: "Cable Fly", equipment: .cable, primaryMuscle: .chest, secondaryMuscles: [.shoulders]),
        ExerciseInfo(name: "Calf Raise", equipment: .machine, primaryMuscle: .calves),
        ExerciseInfo(name: "Chest Press", equipment: .machine, primaryMuscle: .chest, secondaryMuscles: [.shoulders, .triceps]),
        ExerciseInfo(name: "Deadlift", equipment: .barbell, primaryMuscle: .lowerBack, secondaryMuscles: [.glutes, .hamstrings, .traps]),
        ExerciseInfo(name: "Hack Squat", equipment: .machine, primaryMuscle: .quadriceps, secondaryMuscles: [.glutes]),
        ExerciseInfo(name: "Hip Thrust", equipment: .barbell, primaryMuscle: .glutes, secondaryMuscles: [.hamstrings]),
        ExerciseInfo(name: "Incline Dumbbell Press", equipment: .dumbbell, primaryMuscle: .chest, secondaryMuscles: [.shoulders, .triceps]),
        ExerciseInfo(name: "Lat Pulldown", equipment: .cable, primaryMuscle: .lats, secondaryMuscles: [.biceps, .middleBack]),
        ExerciseInfo(name: "Lateral Raise", equipment: .dumbbell, primaryMuscle: .shoulders),
        ExerciseInfo(name: "Leg Curl", equipment: .machine, primaryMuscle: .hamstrings),
        ExerciseInfo(name: "Leg Extension", equipment: .machine, primaryMuscle: .quadriceps),
        ExerciseInfo(name: "Leg Press", equipment: .machine, primaryMuscle: .quadriceps, secondaryMuscles: [.glutes, .hamstrings]),
        ExerciseInfo(name: "Pec Deck", equipment: .machine, primaryMuscle: .chest),
        ExerciseInfo(name: "Preacher Curl", equipment: .machine, primaryMuscle: .biceps),
        ExerciseInfo(name: "Pull Up", equipment: .bodyweight, primaryMuscle: .lats, secondaryMuscles: [.biceps, .middleBack]),
        ExerciseInfo(name: "Rear Delt Fly", equipment: .machine, primaryMuscle: .shoulders, secondaryMuscles: [.middleBack]),
        ExerciseInfo(name: "Romanian Deadlift", equipment: .barbell, primaryMuscle: .hamstrings, secondaryMuscles: [.glutes, .lowerBack]),
        ExerciseInfo(name: "Seated Calf Raise", equipment: .machine, primaryMuscle: .calves),
        ExerciseInfo(name: "Seated Row", equipment: .cable, primaryMuscle: .middleBack, secondaryMuscles: [.lats, .biceps]),
        ExerciseInfo(name: "Shoulder Press", equipment: .machine, primaryMuscle: .shoulders, secondaryMuscles: [.triceps]),
        ExerciseInfo(name: "Squat", equipment: .barbell, primaryMuscle: .quadriceps, secondaryMuscles: [.glutes, .hamstrings, .lowerBack]),
        ExerciseInfo(name: "Triceps Pushdown", equipment: .cable, primaryMuscle: .triceps),
    ]
}
