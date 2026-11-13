import SwiftUI

/// Wraps a weight text field so it shows and takes the weight in the unit from Settings while the model
/// keeps kilograms. Keeps what's being typed as its own text, so "57." isn't snapped back to "57" mid-edit,
/// and refreshes from the model when the kilograms or the unit change underneath it.
struct WeightEntry<Content: View>: View {
    @AppStorage(WeightUnit.storageKey) private var unit: WeightUnit = .kg
    /// The model's weight, as kilogram text. Empty is unloaded.
    @Binding var kilograms: String
    @State private var text: String
    private let content: (Binding<String>) -> Content

    init(kilograms: Binding<String>, @ViewBuilder content: @escaping (Binding<String>) -> Content) {
        _kilograms = kilograms
        _text = State(initialValue: WeightUnit.current.text(fromKilogramsText: kilograms.wrappedValue))
        self.content = content
    }

    var body: some View {
        content($text)
            .onChange(of: text) { _, typed in
                let converted = unit.kilogramsText(fromTyped: typed)
                if converted != kilograms { kilograms = converted }
            }
            .onChange(of: kilograms) { _, stored in
                if unit.kilogramsText(fromTyped: text) != stored { text = unit.text(fromKilogramsText: stored) }
            }
            .onChange(of: unit) { _, unit in
                text = unit.text(fromKilogramsText: kilograms)
            }
    }
}
