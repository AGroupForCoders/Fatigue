import SwiftUI

/// What the exercise editor hands back when you save.
struct ExerciseEdit {
    var info: ExerciseInfo
    /// The brand picked at the top, and its settings.
    var brand: Brand?
    var setup: BrandSetup
    /// Old setting name to new, for settings renamed in this edit, so group overrides follow the rename.
    var renamedSettings: [String: String]
    /// Settings edited on other brands before switching away from them, keyed by brand (nil for no brand).
    var otherSetups: [Brand?: BrandSetup] = [:]
}

/// Creates a custom exercise, or edits one: name, equipment and muscles, then the settings saved
/// for the brand picked under the name. Switching brand switches which settings you're editing. Each setting has a value for the whole exercise, and a number setting
/// can count towards the score with a direction and a range.
struct ExerciseEditor: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let isNew: Bool
    let existingNames: [String]
    /// Brands you've used for this exercise, for the brand picker.
    let knownBrands: [KnownBrand]
    /// The settings saved for a brand, loaded when you switch to it.
    let savedSetup: (Brand?) -> BrandSetup
    let onSave: (ExerciseEdit) -> Void

    @State private var info: ExerciseInfo
    @State private var brand: Brand?
    @State private var settings: [EditableSetting]
    /// Settings edited on brands you've switched away from, keyed by brand (nil for no brand).
    @State private var drafts: [Brand?: [EditableSetting]] = [:]
    @State private var pickingBrand = false
    @State private var editingSetting: EditableSetting?
    @FocusState private var editingName: Bool

    /// A setting plus the name it had when the editor opened, so a rename can be carried to existing sets.
    struct EditableSetting: Identifiable, Equatable {
        var setting: ExerciseSetting
        var originalName: String?
        var id: UUID { setting.id }
    }

    /// For a new custom exercise. `name` prefills from what you searched for.
    init(newNamed name: String, existingNames: [String], onSave: @escaping (ExerciseEdit) -> Void) {
        isNew = true
        self.existingNames = existingNames
        knownBrands = []
        savedSetup = { _ in BrandSetup() }
        self.onSave = onSave
        _brand = State(initialValue: nil)
        _info = State(initialValue: ExerciseInfo(name: name, equipment: .machine, primaryMuscle: .chest, isCustom: true))
        _settings = State(initialValue: [])
    }

    /// For an exercise you already have, on the brand it's being done on.
    init(
        editing info: ExerciseInfo, brand: Brand?, setup: BrandSetup, existingNames: [String],
        knownBrands: [KnownBrand], savedSetup: @escaping (Brand?) -> BrandSetup, onSave: @escaping (ExerciseEdit) -> Void
    ) {
        isNew = false
        self.existingNames = existingNames.filter { $0 != info.name }
        self.knownBrands = knownBrands
        self.savedSetup = savedSetup
        self.onSave = onSave
        _brand = State(initialValue: brand)
        _info = State(initialValue: info)
        _settings = State(initialValue: setup.settings.map { EditableSetting(setting: $0, originalName: $0.name) })
    }

    private var trimmedName: String { info.name.trimmingCharacters(in: .whitespaces) }

    private var problem: String? {
        if trimmedName.isEmpty { return "Give it a name." }
        if existingNames.contains(where: { $0.caseInsensitiveCompare(trimmedName) == .orderedSame }) { return "There's already an exercise called \(trimmedName)." }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    about
                    settingsSection
                }
                .padding(.horizontal, Tokens.Space.xxl)
                .padding(.top, Tokens.Space.xxl)
                .padding(.bottom, Tokens.Space.xxxl)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: Tokens.Space.s) {
                if let problem, !isNew || !info.name.isEmpty {
                    Text(problem)
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.accent)
                }
                PrimaryButton(title: isNew ? "Create exercise" : "Save") {
                    var saved = info
                    saved.name = trimmedName
                    let renamed = Dictionary(uniqueKeysWithValues: settings.compactMap { editable in
                        editable.originalName.flatMap { $0 != editable.setting.name ? ($0, editable.setting.name) : nil }
                    })
                    var others = drafts.mapValues { BrandSetup(settings: $0.map(\.setting)) }
                    others[brand] = nil
                    onSave(ExerciseEdit(
                        info: saved, brand: brand, setup: BrandSetup(settings: settings.map(\.setting)),
                        renamedSettings: renamed, otherSetups: others
                    ))
                    dismiss()
                }
                .opacity(problem == nil ? 1 : 0.4)
                .disabled(problem != nil)
                .animation(.quick, value: problem == nil)
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.vertical, Tokens.Space.l)
        }
        .background(palette.background)
        .presentationDetents([.large])
        .presentationBackground(palette.background)
        .onAppear { if isNew { editingName = true } }
        .sheet(isPresented: $pickingBrand) {
            BrandSheet(exerciseName: trimmedName.isEmpty ? "New exercise" : trimmedName, known: knownBrands, current: brand) { picked in
                switchBrand(to: picked)
            }
            .environment(\.palette, palette)
        }
        .sheet(item: $editingSetting) { editing in
            SettingEditor(
                setting: editing.setting,
                takenNames: settings.filter { $0.id != editing.id }.map(\.setting.name),
                isNew: !settings.contains { $0.id == editing.id },
                onSave: { setting in
                    withAnimation(.standard) {
                        if let index = settings.firstIndex(where: { $0.id == editing.id }) {
                            settings[index].setting = setting
                        } else {
                            settings.append(EditableSetting(setting: setting, originalName: nil))
                        }
                    }
                },
                onDelete: { withAnimation(.standard) { settings.removeAll { $0.id == editing.id } } }
            )
            .environment(\.palette, palette)
        }
    }

    /// Keeps what you've edited on the current brand, then shows the settings for the picked one:
    /// edited earlier in this sheet if you've been there, otherwise as saved.
    private func switchBrand(to picked: Brand?) {
        guard picked != brand else { return }
        drafts[brand] = settings
        withAnimation(.standard) {
            settings = drafts[picked] ?? savedSetup(picked).settings.map { EditableSetting(setting: $0, originalName: $0.name) }
            brand = picked
        }
    }

    /// The brand, first of the rows under the name. Tapping it picks another, or adds one.
    private var brandButton: some View {
        Button { pickingBrand = true } label: {
            OutlinedLabel(text: brand?.display ?? "No brand", showsChevron: true, isMuted: brand == nil)
        }
        .buttonStyle(.press)
        .accessibilityLabel("Brand, \(brand?.display ?? "no brand")")
    }

    private var header: some View {
        HStack(alignment: .top) {
            Text(isNew ? "New exercise" : "Edit exercise")
                .textStyle(Tokens.Typography.title)
                .foregroundStyle(palette.foreground)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(palette.foreground)
                    .frame(width: Tokens.Size.control, height: Tokens.Size.control)
            }
            .buttonStyle(.press)
            .accessibilityLabel("Close")
        }
        .padding(.bottom, Tokens.Space.xxl)
    }

    /// Name, equipment and muscles. These belong to the exercise, whatever the brand.
    private var about: some View {
        VStack(alignment: .leading, spacing: 0) {
            if info.isCustom {
                LineField(label: "Name", text: $info.name, kind: .name, isFocused: editingName)
                    .focused($editingName)
                    .submitLabel(.done)
            } else {
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    Text(info.name)
                        .textStyle(Tokens.Typography.exerciseName)
                        .foregroundStyle(palette.foreground)
                    Text("Built in, so the name stays the same for everyone.")
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.foregroundMuted)
                }
            }

            Hairline().padding(.top, Tokens.Space.xxl)
            row("Brand") { brandButton }
            Hairline(soft: true)
            row("Equipment") {
                Menu {
                    Picker("Equipment", selection: $info.equipment) {
                        ForEach(Equipment.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                } label: {
                    OutlinedLabel(text: info.equipment.name, showsChevron: true)
                }
            }
            Hairline(soft: true)
            row("Main muscle") {
                Menu {
                    Picker("Main muscle", selection: $info.primaryMuscle) {
                        ForEach(Muscle.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                } label: {
                    OutlinedLabel(text: info.primaryMuscle.name, showsChevron: true)
                }
            }
            Hairline(soft: true)
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                Text("Also works")
                    .textStyle(Tokens.Typography.body)
                    .foregroundStyle(palette.foreground)
                FlowLayout(spacing: Tokens.Space.s) {
                    ForEach(Muscle.allCases.filter { $0 != info.primaryMuscle }, id: \.self) { muscle in
                        let isOn = info.secondaryMuscles.contains(muscle)
                        Button {
                            if isOn { info.secondaryMuscles.removeAll { $0 == muscle } } else { info.secondaryMuscles.append(muscle) }
                        } label: {
                            OptionLabel(title: muscle.name, isSelected: isOn)
                        }
                        .buttonStyle(.press)
                    }
                }
            }
            .padding(.vertical, Tokens.Space.l)
            .sensoryFeedback(.selection, trigger: info.secondaryMuscles)
            Hairline()
        }
        .onChange(of: info.primaryMuscle) { _, primary in info.secondaryMuscles.removeAll { $0 == primary } }
    }

    /// The settings saved for this exercise on the brand picked at the top.
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text("Settings")
                    .textStyle(Tokens.Typography.exerciseName)
                    .foregroundStyle(palette.foreground)
                Text("Like seat height or notch. Kept per brand, since every machine is set up differently. A group of sets can change a value from its heading.")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Tokens.Space.xxxl)
            .padding(.bottom, Tokens.Space.m)
            Hairline()

            ForEach(settings) { editable in
                Button { editingSetting = editable } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                            Text(editable.setting.name)
                                .textStyle(Tokens.Typography.body)
                                .foregroundStyle(palette.foreground)
                            Text(SettingEditor.describe(editable.setting))
                                .textStyle(Tokens.Typography.caption)
                                .foregroundStyle(palette.foregroundMuted)
                        }
                        Spacer()
                        Text(SettingEditor.displayValue(editable.setting))
                            .textStyle(Tokens.Typography.number)
                            .monospacedDigit()
                            .foregroundStyle(palette.foreground)
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .foregroundStyle(palette.foregroundFaint)
                    }
                    .frame(minHeight: Tokens.Size.setRow)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressRow)
                .transition(.opacity)
                Hairline(soft: true)
            }
            Button {
                editingSetting = EditableSetting(setting: ExerciseSetting(name: ""), originalName: nil)
            } label: {
                HStack {
                    Text("Add setting")
                    Spacer()
                    Image(systemName: "plus")
                }
                .textStyle(Tokens.Typography.control)
                .foregroundStyle(palette.foregroundMuted)
                .frame(minHeight: Tokens.Size.control)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressRow)
        }
    }

    private func row(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(title)
                .textStyle(Tokens.Typography.body)
                .foregroundStyle(palette.foreground)
            Spacer()
            control()
        }
        .frame(minHeight: Tokens.Size.setRow)
    }
}

/// An outlined option, filled in when picked. Used for muscles and the setting editor's choices.
struct OptionLabel: View {
    @Environment(\.palette) private var palette
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .textStyle(Tokens.Typography.control)
            .foregroundStyle(isSelected ? palette.background : palette.foreground)
            .padding(.horizontal, Tokens.Space.m)
            .frame(height: Tokens.Size.outlinedControl - Tokens.Space.xs)
            .background(isSelected ? palette.foreground : Color.clear, in: .rect(cornerRadius: Tokens.Radius.control))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.control)
                    .strokeBorder(isSelected ? palette.foreground : palette.borderControl, lineWidth: Tokens.Size.line)
            )
            .animation(.quick, value: isSelected)
    }
}

/// One setting: its name, type and value, and for a number whether and how it counts towards the score.
struct SettingEditor: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let takenNames: [String]
    let isNew: Bool
    let onSave: (ExerciseSetting) -> Void
    let onDelete: () -> Void

    @State private var setting: ExerciseSetting
    @State private var lowest: String
    @State private var highest: String
    /// A factor you typed, for when ×1.25 and ×1.5 aren't right.
    @State private var ownFactor: String
    @FocusState private var focusedName: Bool

    /// The factors offered for a yes/no setting, as in "Scores and stats".
    private static let presetFactors: [Double] = [1.25, 1.5]

    init(setting: ExerciseSetting, takenNames: [String], isNew: Bool, onSave: @escaping (ExerciseSetting) -> Void, onDelete: @escaping () -> Void) {
        self.takenNames = takenNames
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _setting = State(initialValue: setting)
        _lowest = State(initialValue: setting.rangeMin.map(PlainNumber.string) ?? "")
        _highest = State(initialValue: setting.rangeMax.map(PlainNumber.string) ?? "")
        _ownFactor = State(initialValue: setting.factor.flatMap { Self.presetFactors.contains($0) ? nil : PlainNumber.string($0) } ?? "")
    }

    /// Such as "Number · higher is better, 1 to 10 · own progress per value", or "Yes or no".
    static func describe(_ setting: ExerciseSetting) -> String {
        switch setting.kind {
        case .text: return "Text"
        case .yesNo:
            guard setting.isTracked, let factor = setting.factor else { return "Yes or no" }
            return "Yes or no · counts ×\(PlainNumber.string(factor)) when on"
        case .number:
            guard setting.isTracked, let direction = setting.direction, let min = setting.rangeMin, let max = setting.rangeMax else {
                return "Number"
            }
            var parts = ["Number", "counts, \(direction == .higher ? "higher" : "lower") is better, \(PlainNumber.string(min)) to \(PlainNumber.string(max))"]
            if setting.splitByValue { parts.append("own progress per value") }
            return parts.joined(separator: " · ")
        }
    }

    static func displayValue(_ setting: ExerciseSetting) -> String {
        switch setting.kind {
        case .yesNo: setting.value == "yes" ? "Yes" : "No"
        case .number, .text: setting.value.isEmpty ? "-" : setting.value
        }
    }

    private var problem: String? {
        let name = setting.name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return "Give the setting a name." }
        if takenNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { return "This exercise already has a setting called \(name)." }
        if setting.kind == .number, !setting.value.isEmpty, Double(setting.value) == nil { return "The value has to be a number." }
        if setting.kind == .yesNo, !ownFactor.isEmpty, setting.factor == nil || !Self.presetFactors.contains(setting.factor!) {
            guard let factor = Double(ownFactor), factor > 1, factor <= 2 else { return "The factor has to be above 1 and at most 2." }
        }
        if setting.kind == .number, setting.direction != nil {
            guard let min = Double(lowest), let max = Double(highest) else { return "Set the lowest and highest values." }
            if max <= min { return "The highest value has to be above the lowest." }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(isNew ? "New setting" : setting.name)
                    .textStyle(Tokens.Typography.title)
                    .foregroundStyle(palette.foreground)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(palette.foreground)
                        .frame(width: Tokens.Size.control, height: Tokens.Size.control)
                }
                .buttonStyle(.press)
                .accessibilityLabel("Close")
            }
            .padding(.bottom, Tokens.Space.xxl)

            LineField(label: "Name", text: $setting.name, kind: .name, isFocused: focusedName)
                .focused($focusedName)

            Hairline().padding(.top, Tokens.Space.xxl)
            row("Type") {
                choices([("Number", ExerciseSetting.Kind.number), ("Yes or no", .yesNo), ("Text", .text)], selected: setting.kind) { kind in
                    setting.kind = kind
                    if kind == .yesNo, setting.value != "yes" { setting.value = "no" }
                    if kind != .yesNo, setting.value == "yes" || setting.value == "no" { setting.value = "" }
                }
            }
            Hairline(soft: true)
            row("Value") {
                if setting.kind == .yesNo {
                    choices([("No", "no"), ("Yes", "yes")], selected: setting.value) { setting.value = $0 }
                } else {
                    TextField("", text: $setting.value, prompt: Text("-").foregroundStyle(palette.foregroundFaint))
                        .keyboardType(setting.kind == .number ? .decimalPad : .default)
                        .multilineTextAlignment(.center)
                        .textStyle(Tokens.Typography.number)
                        .foregroundStyle(palette.foreground)
                        .frame(width: setting.kind == .number ? Tokens.Size.amountColumn : Tokens.Size.weightColumn * 2, height: Tokens.Size.cell)
                        .background(palette.surface, in: .rect(cornerRadius: Tokens.Radius.control))
                }
            }
            if setting.kind == .yesNo {
                Hairline(soft: true)
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    Text("Makes it harder")
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.foreground)
                    HStack(spacing: Tokens.Space.s) {
                        choices([("No", Double?.none)] + Self.presetFactors.map { ("×\(PlainNumber.string($0))", Double?.some($0)) },
                                selected: ownFactor.isEmpty ? setting.factor : nil) { factor in
                            ownFactor = ""
                            setting.factor = factor
                        }
                        numberCell($ownFactor, label: "Own factor")
                            .onChange(of: ownFactor) { _, text in if !text.isEmpty { setting.factor = Double(text) } }
                    }
                }
                .padding(.vertical, Tokens.Space.l)
                Text("When it's on, a set's score is multiplied by this. All the settings together count up to ×3. Changing it rescores your history.")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Tokens.Space.s)
            }
            if setting.kind == .number {
                Hairline(soft: true)
                row("Counts towards score") {
                    choices([("Higher", ExerciseSetting.Direction?.some(.higher)), ("Lower", .some(.lower)), ("No", nil)], selected: setting.direction) { setting.direction = $0 }
                }
                if setting.direction != nil {
                    Hairline(soft: true)
                    row("From") {
                        HStack(spacing: Tokens.Space.s) {
                            numberCell($lowest, label: "Lowest")
                            Text("to").textStyle(Tokens.Typography.control).foregroundStyle(palette.foregroundMuted)
                            numberCell($highest, label: "Highest")
                        }
                    }
                    Hairline(soft: true)
                    row("Own progress per value") {
                        choices([("Yes", true), ("No", false)], selected: setting.splitByValue) { setting.splitByValue = $0 }
                    }
                    Text("A set at the best end of the range scores up to twice one at the worst end. With own progress on, notch 8 is only compared with notch 8.")
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.foregroundFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, Tokens.Space.s)
                }
            }
            Hairline()

            if !isNew {
                Button {
                    onDelete()
                    dismiss()
                } label: {
                    Text("Delete setting")
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.accent)
                        .frame(maxWidth: .infinity, minHeight: Tokens.Size.setRow, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressRow)
            }

            Spacer(minLength: Tokens.Space.xxl)
            if let problem, !setting.name.isEmpty {
                Text(problem)
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.accent)
                    .padding(.bottom, Tokens.Space.s)
            }
            PrimaryButton(title: isNew ? "Add setting" : "Save") {
                var saved = setting
                saved.name = setting.name.trimmingCharacters(in: .whitespaces)
                if saved.kind == .number, saved.direction != nil {
                    saved.rangeMin = Double(lowest)
                    saved.rangeMax = Double(highest)
                } else {
                    saved.direction = nil
                    saved.rangeMin = nil
                    saved.rangeMax = nil
                    saved.splitByValue = false
                }
                if saved.kind == .yesNo {
                    if let own = Double(ownFactor) { saved.factor = own }
                    if (saved.factor ?? 1) <= 1 { saved.factor = nil }
                } else {
                    saved.factor = nil
                }
                onSave(saved)
                dismiss()
            }
            .opacity(problem == nil ? 1 : 0.4)
            .disabled(problem != nil)
            .padding(.bottom, Tokens.Space.l)
        }
        .padding(.horizontal, Tokens.Space.xxl)
        .padding(.top, Tokens.Space.xxl)
        .background(palette.background)
        .presentationDetents([.large])
        .presentationBackground(palette.background)
        .animation(.standard, value: setting.kind)
        .animation(.standard, value: setting.direction)
        .animation(.quick, value: setting.factor)
        .sensoryFeedback(.selection, trigger: setting.kind)
        .onAppear { if isNew { focusedName = true } }
    }

    private func row(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(title)
                .textStyle(Tokens.Typography.body)
                .foregroundStyle(palette.foreground)
            Spacer(minLength: Tokens.Space.m)
            control()
        }
        .frame(minHeight: Tokens.Size.setRow)
    }

    private func numberCell(_ text: Binding<String>, label: String) -> some View {
        TextField("", text: text, prompt: Text("-").foregroundStyle(palette.foregroundFaint))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .textStyle(Tokens.Typography.number)
            .foregroundStyle(palette.foreground)
            .frame(width: Tokens.Size.amountColumn, height: Tokens.Size.cell)
            .background(palette.surface, in: .rect(cornerRadius: Tokens.Radius.control))
            .accessibilityLabel(label)
    }

    private func choices<Value: Equatable>(_ options: [(String, Value)], selected: Value, onPick: @escaping (Value) -> Void) -> some View {
        HStack(spacing: Tokens.Space.s) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button { onPick(option.1) } label: {
                    OptionLabel(title: option.0, isSelected: option.1 == selected)
                }
                .buttonStyle(.press)
            }
        }
    }
}

/// Lays its children out in rows, wrapping to the next row when one is full. Used for the muscle chips.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let previous = rows[rows.count - 1]
                rows.append(Row(y: previous.y + previous.height + spacing))
            }
            let gap = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
