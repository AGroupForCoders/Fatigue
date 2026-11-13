import SwiftUI

/// The RPE picker pinned to the bottom of the workout screen, where the rest timer sits:
/// which set it is for, what the chosen value means, and 6 to 10 in half steps.
/// One tap picks a value and closes it.
struct RPEPanel: View {
    @Environment(\.palette) private var palette
    let title: String
    let selected: Double?
    let onPick: (Double?) -> Void
    let onClose: () -> Void

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
        VStack(spacing: 0) {
            Hairline()
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                        Text(title)
                            .textStyle(Tokens.Typography.body)
                            .foregroundStyle(palette.foreground)
                        Text(selected.map(Self.meaning) ?? "How hard was it?")
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                    }
                    Spacer()
                    if selected != nil {
                        Button("Clear") { onPick(nil) }
                            .textStyle(Tokens.Typography.control)
                            .foregroundStyle(palette.foregroundMuted)
                            .frame(height: Tokens.Size.control)
                    }
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .foregroundStyle(palette.foreground)
                            .frame(width: Tokens.Size.control, height: Tokens.Size.control, alignment: .trailing)
                    }
                    .accessibilityLabel("Close")
                }

                HStack(spacing: Tokens.Space.xs) {
                    ForEach(Self.values, id: \.self) { value in
                        let isSelected = value == selected
                        Button { onPick(value) } label: {
                            Text(RPECell.format(value))
                                .textStyle(Tokens.Typography.control)
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? palette.background : palette.foreground)
                                .frame(maxWidth: .infinity)
                                .frame(height: Tokens.Size.control)
                                .background(isSelected ? palette.foreground : palette.surface, in: .rect(cornerRadius: Tokens.Radius.control))
                        }
                        .buttonStyle(.press)
                        .accessibilityLabel("RPE \(RPECell.format(value)), \(Self.meaning(value))")
                    }
                }
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.top, Tokens.Space.m)
            .padding(.bottom, Tokens.Space.l)
        }
        .background(palette.background.ignoresSafeArea(edges: .bottom))
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// A sheet for picking the brand of an exercise: the brands you've used, with your last set on each,
/// then suggestions, then a field to type your own, and a label such as the model or the gym under it.
/// Brand and label together decide which history and settings you get.
///
/// When the brand you're on has history or settings, picking another one also offers to move them along:
/// onto a new name that's a rename (or putting no-brand history onto its brand), onto a brand you've
/// already used it's a merge. `onUse` gets the brand and whether to move.
struct BrandSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let exerciseName: String
    let known: [KnownBrand]
    let current: Brand?
    let onUse: (_ brand: Brand?, _ movingHistory: Bool) -> Void

    /// The brand picked from the rows or suggestions, by name. The label below is kept apart so it can be edited.
    @State private var picked: String?
    @State private var typed = ""
    @State private var movingHistory = false
    @State private var label: String

    private static let suggestions = ["Technogym", "Hammer Strength", "Life Fitness", "Matrix", "Cybex", "Prime", "Precor"]

    init(exerciseName: String, known: [KnownBrand], current: Brand?, onUse: @escaping (_ brand: Brand?, _ movingHistory: Bool) -> Void) {
        self.exerciseName = exerciseName
        self.known = known
        self.current = current
        self.onUse = onUse
        _picked = State(initialValue: current?.name)
        _label = State(initialValue: current?.label ?? "")
    }

    /// Whether there's anything on the current brand to move, and somewhere else to move it.
    private var canMove: Bool {
        choice != current && known.contains { $0.brand == current }
    }

    /// Whether the picked brand already has history or settings of its own, so moving would merge the two.
    private var isMerge: Bool {
        known.contains { $0.brand == choice }
    }

    private var isMoving: Bool { canMove && movingHistory }

    private var actionTitle: String {
        let target = choice?.display ?? "no brand"
        guard isMoving else { return "Use \(target)" }
        if isMerge { return "Merge into \(target)" }
        return current == nil ? "Move history to \(target)" : "Rename to \(target)"
    }

    private var moveExplanation: String {
        let from = current?.display ?? "no brand"
        let to = choice?.display ?? "no brand"
        if isMerge {
            return "Everything on \(from) joins what's already on \(to): workouts, records and settings. Settings both have keep \(to)'s."
        }
        if current == nil { return "Everything logged on no brand moves to \(to), with its settings and records." }
        return "\(from) is renamed to \(to). Its workouts, settings and records stay with it."
    }

    private var rows: [KnownBrand] {
        known.contains { $0.brand == nil } ? known : known + [KnownBrand(brand: nil, lastSet: "", when: "")]
    }

    private var suggested: [String] {
        Self.suggestions.filter { name in !known.contains { $0.brand?.name == name } }
    }

    /// The brand name that'll be used: what you typed, or else what you picked.
    private var chosenName: String? {
        let text = typed.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? picked : text
    }

    /// The brand and label together. Nil is no brand, and a label with no brand is dropped.
    private var choice: Brand? {
        Brand(name: chosenName, label: label)
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
                            Text("History, settings and records are kept per brand and label.")
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
                    ForEach(rows) { known in
                        Button {
                            picked = known.brand?.name
                            label = known.brand?.label ?? ""
                            typed = ""
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                                    Text(known.brand?.display ?? "No brand")
                                        .textStyle(Tokens.Typography.exerciseName)
                                        .foregroundStyle(palette.foreground)
                                    if !known.lastSet.isEmpty {
                                        Text("\(known.lastSet), \(known.when)")
                                            .textStyle(Tokens.Typography.caption)
                                            .foregroundStyle(palette.foregroundMuted)
                                    }
                                }
                                Spacer()
                                if choice == known.brand {
                                    Image(systemName: "checkmark").foregroundStyle(palette.foreground)
                                }
                            }
                            .frame(minHeight: Tokens.Size.setRow + Tokens.Space.m)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressRow)
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
                        .buttonStyle(.pressRow)
                        Hairline()
                    }
                    TextField("", text: $typed, prompt: Text("Or type your own").foregroundStyle(palette.foregroundMuted))
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.foreground)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .frame(minHeight: Tokens.Size.primaryButton)
                    Hairline()

                    if chosenName != nil {
                        Text("Label")
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                            .padding(.top, Tokens.Space.xxl)
                            .padding(.bottom, Tokens.Space.xs)
                        TextField("", text: $label, prompt: Text("Such as the model or the gym").foregroundStyle(palette.foregroundMuted))
                            .textStyle(Tokens.Typography.body)
                            .foregroundStyle(palette.foreground)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .frame(minHeight: Tokens.Size.primaryButton)
                            .accessibilityLabel("Label")
                        Hairline()
                    }
                    if canMove { moveSection }
                }
                .animation(.standard, value: chosenName != nil)
                .padding(.horizontal, Tokens.Space.xxl)
                .padding(.top, Tokens.Space.xxl)
                .animation(.standard, value: canMove)
            }
            PrimaryButton(title: actionTitle) {
                onUse(choice, isMoving)
                dismiss()
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.vertical, Tokens.Space.l)
        }
        .background(palette.background)
        .overlay { GrainOverlay() }
        .presentationDetents([.large])
        .presentationBackground(palette.background)
        .sensoryFeedback(.selection, trigger: movingHistory)
    }

    /// Whether what's logged on the current brand comes along to the picked one, or stays where it is.
    private var moveSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("History on \(current?.display ?? "no brand")")
                .textStyle(Tokens.Typography.caption)
                .foregroundStyle(palette.foregroundMuted)
            HStack(spacing: Tokens.Space.s) {
                Button { movingHistory = false } label: { OptionLabel(title: "Leave it", isSelected: !movingHistory) }
                    .buttonStyle(.press)
                Button { movingHistory = true } label: {
                    OptionLabel(title: isMerge ? "Merge into \(choice?.display ?? "no brand")" : "Move it along", isSelected: movingHistory)
                }
                .buttonStyle(.press)
            }
            Text(movingHistory ? moveExplanation : "Your sets on \(current?.display ?? "no brand") stay there, and \(choice?.display ?? "no brand") starts its own history.")
                .textStyle(Tokens.Typography.caption)
                .foregroundStyle(palette.foregroundFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Tokens.Space.xxl)
        .transition(.opacity)
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
                            .animation(.quick, value: isSelected)
                    }
                    .buttonStyle(.press)
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


