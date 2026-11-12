import SwiftUI

/// The RPE scale that opens under a set: 6 to 10 in half steps, with what the number means.
/// One tap picks a value and closes the scale.
struct RPEScale: View {
    @Environment(\.palette) private var palette
    let selected: Double?
    let onPick: (Double?) -> Void

    static let values = stride(from: 6.0, through: 10.0, by: 0.5).map { $0 }

    static func meaning(_ value: Double) -> String {
        switch value {
        case 10: "Nothing left"
        case 9.5: "Maybe 1 rep left"
        case 9: "1 rep left"
        case 8.5: "1 to 2 reps left"
        case 8: "2 reps left"
        case 7.5: "2 to 3 reps left"
        case 7: "3 reps left"
        case 6.5: "3 to 4 reps left"
        default: "4 or more reps left"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack {
                Text(selected.map(Self.meaning) ?? "How hard was it?")
                    .foregroundStyle(palette.foregroundMuted)
                Spacer()
                if selected != nil {
                    Button("Clear") { onPick(nil) }
                        .foregroundStyle(palette.foregroundMuted)
                }
            }
            .textStyle(Tokens.Typography.caption)

            HStack(spacing: Tokens.Space.xs) {
                ForEach(Self.values, id: \.self) { value in
                    let isSelected = value == selected
                    Button { onPick(value) } label: {
                        Text(RPECell.format(value))
                            .textStyle(Tokens.Typography.control)
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? palette.background : palette.foreground)
                            .frame(maxWidth: .infinity)
                            .frame(height: Tokens.Size.cell)
                            .background(isSelected ? palette.foreground : palette.surface, in: .rect(cornerRadius: Tokens.Radius.control))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("RPE \(RPECell.format(value)), \(Self.meaning(value))")
                }
            }
        }
        .padding(.leading, Tokens.Size.setNumberColumn + Tokens.Space.s)
        .padding(.bottom, Tokens.Space.m)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// A sheet for picking the brand of an exercise: the brands you've used, with your last set on each,
/// then suggestions, then a field to type your own.
struct BrandSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let exerciseName: String
    let known: [KnownBrand]
    let current: String?
    let onUse: (String?) -> Void

    @State private var picked: String?
    @State private var typed = ""

    private static let suggestions = ["Technogym", "Hammer Strength", "Life Fitness", "Matrix", "Cybex", "Prime", "Precor"]

    init(exerciseName: String, known: [KnownBrand], current: String?, onUse: @escaping (String?) -> Void) {
        self.exerciseName = exerciseName
        self.known = known
        self.current = current
        self.onUse = onUse
        _picked = State(initialValue: current)
    }

    private var rows: [KnownBrand] {
        known.contains { $0.name == nil } ? known : known + [KnownBrand(name: nil, lastSet: "", when: "")]
    }

    private var suggested: [String] {
        Self.suggestions.filter { name in !known.contains { $0.name == name } }
    }

    private var choice: String? {
        let text = typed.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? picked : text
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: Tokens.Space.s) {
                            Text(exerciseName)
                                .textStyle(Tokens.Typography.title)
                                .foregroundStyle(palette.foreground)
                            Text("History and records are kept per brand.")
                                .textStyle(Tokens.Typography.body)
                                .foregroundStyle(palette.foregroundMuted)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(palette.foreground)
                                .frame(width: Tokens.Size.control, height: Tokens.Size.control)
                        }
                        .accessibilityLabel("Close")
                    }
                    .padding(.bottom, Tokens.Space.xxl)

                    Hairline()
                    ForEach(rows) { brand in
                        Button {
                            picked = brand.name
                            typed = ""
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                                    Text(brand.name ?? "No brand")
                                        .textStyle(Tokens.Typography.exerciseName)
                                        .foregroundStyle(palette.foreground)
                                    if !brand.lastSet.isEmpty {
                                        Text("\(brand.lastSet), \(brand.when)")
                                            .textStyle(Tokens.Typography.caption)
                                            .foregroundStyle(palette.foregroundMuted)
                                    }
                                }
                                Spacer()
                                if typed.isEmpty, picked == brand.name {
                                    Image(systemName: "checkmark").foregroundStyle(palette.foreground)
                                }
                            }
                            .frame(minHeight: Tokens.Size.setRow + Tokens.Space.m)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Hairline()
                    }

                    Text("Add a brand")
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.foregroundMuted)
                        .padding(.top, Tokens.Space.xxl)
                        .padding(.bottom, Tokens.Space.xs)
                    ForEach(suggested, id: \.self) { name in
                        Button {
                            picked = name
                            typed = ""
                        } label: {
                            HStack {
                                Text(name)
                                Spacer()
                                if typed.isEmpty, picked == name {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .textStyle(Tokens.Typography.body)
                            .foregroundStyle(palette.foreground)
                            .frame(minHeight: Tokens.Size.primaryButton)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Hairline()
                    }
                    TextField("", text: $typed, prompt: Text("Or type your own").foregroundStyle(palette.foregroundMuted))
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.foreground)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .frame(minHeight: Tokens.Size.primaryButton)
                    Hairline()
                }
                .padding(.horizontal, Tokens.Space.xxl)
                .padding(.top, Tokens.Space.xxl)
            }
            PrimaryButton(title: "Use \(choice ?? "no brand")") {
                onUse(choice)
                dismiss()
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.vertical, Tokens.Space.l)
        }
        .background(palette.background)
        .overlay { GrainOverlay() }
        .presentationDetents([.large])
        .presentationBackground(palette.background)
    }
}

/// A sheet for an exercise's rest time: quick presets, and a wheel in 15 second steps for anything else.
struct RestSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let exerciseName: String
    @Binding var seconds: Int

    private static let presets = [60, 90, 120, 180]
    private static let wheel = Array(stride(from: 15, through: 600, by: 15))

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text("Rest")
                    .textStyle(Tokens.Typography.title)
                    .foregroundStyle(palette.foreground)
                Text("After each set of \(exerciseName)")
                    .textStyle(Tokens.Typography.body)
                    .foregroundStyle(palette.foregroundMuted)
            }
            .padding(.top, Tokens.Space.xxl)

            HStack(spacing: Tokens.Space.s) {
                ForEach(Self.presets, id: \.self) { preset in
                    let isSelected = seconds == preset
                    Button { seconds = preset } label: {
                        Text(WorkoutScreen.clock(TimeInterval(preset)))
                            .textStyle(Tokens.Typography.control)
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? palette.background : palette.foreground)
                            .frame(maxWidth: .infinity)
                            .frame(height: Tokens.Size.outlinedControl)
                            .background(isSelected ? palette.foreground : Color.clear, in: .rect(cornerRadius: Tokens.Radius.control))
                            .overlay(
                                RoundedRectangle(cornerRadius: Tokens.Radius.control)
                                    .strokeBorder(isSelected ? palette.foreground : palette.borderControl, lineWidth: Tokens.Size.line)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, Tokens.Space.xl)

            Picker("Rest", selection: $seconds) {
                ForEach(Self.wheel, id: \.self) { value in
                    Text(WorkoutScreen.clock(TimeInterval(value)))
                        .textStyle(Tokens.Typography.exerciseName)
                        .monospacedDigit()
                        .foregroundStyle(palette.foreground)
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            PrimaryButton(title: "Done") { dismiss() }
                .padding(.bottom, Tokens.Space.l)
        }
        .padding(.horizontal, Tokens.Space.xxl)
        .background(palette.background)
        .presentationDetents([.medium])
        .presentationBackground(palette.background)
        .sensoryFeedback(.selection, trigger: seconds)
    }
}
