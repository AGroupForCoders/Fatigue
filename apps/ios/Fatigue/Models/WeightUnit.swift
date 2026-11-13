import Foundation

/// The unit weights are shown and typed in, from the picker in Settings. Weights are always stored in
/// kilograms, as the data model says; this converts at the edges, so 100 lb typed reads 100 lb again.
nonisolated enum WeightUnit: String, CaseIterable {
    case kg, lb

    /// The `UserDefaults` key the Settings picker saves under.
    static let storageKey = "weightUnit"

    /// Exact, by the definition of the international pound.
    static let kilogramsPerPound = 0.45359237

    /// The unit the app is set to right now, for code that can't observe the setting.
    static var current: WeightUnit {
        UserDefaults.standard.string(forKey: storageKey).flatMap(WeightUnit.init(rawValue:)) ?? .kg
    }

    /// For accessibility: "kilograms" or "pounds".
    var name: String { self == .kg ? "kilograms" : "pounds" }

    // MARK: Converting

    /// Kilograms in this unit, at full precision.
    func amount(fromKilograms kilograms: Double) -> Double {
        self == .kg ? kilograms : kilograms / Self.kilogramsPerPound
    }

    /// A weight in this unit as kilograms, at full precision, so what was typed comes back the same.
    func kilograms(from amount: Double) -> Double {
        self == .kg ? amount : amount * Self.kilogramsPerPound
    }

    // MARK: Showing

    /// Kilograms as a plain number in this unit, such as "100" or "57.5". Rounded to two decimals, as fine
    /// as anyone types (quarter-pound plates), so 45.359237 kg reads "100" and not "100.00000000000001".
    func text(fromKilograms kilograms: Double) -> String {
        PlainNumber.string((amount(fromKilograms: kilograms) * 100).rounded() / 100)
    }

    /// The model's kilogram text in this unit, for a cell. Empty, or not a number, stays empty.
    func text(fromKilogramsText text: String) -> String {
        Self.number(text).map(text(fromKilograms:)) ?? ""
    }

    /// With the unit after it, such as "57.5 kg" or "100 lb".
    func labelled(_ kilograms: Double) -> String { "\(text(fromKilograms: kilograms)) \(rawValue)" }

    /// A total such as a volume, to the whole unit: "4,254 kg".
    func wholeLabelled(_ kilograms: Double) -> String {
        "\(Int(amount(fromKilograms: kilograms).rounded()).formatted()) \(rawValue)"
    }

    // MARK: Typing

    /// The model's kilogram text, such as "45.359237", from a weight typed in this unit. Kept at full
    /// precision so the typed value round-trips. Empty when nothing, or nothing numeric, was typed.
    func kilogramsText(fromTyped text: String) -> String {
        Self.number(text).map { PlainNumber.string(kilograms(from: $0)) } ?? ""
    }

    private static func number(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)), value.isFinite else { return nil }
        return value
    }
}
