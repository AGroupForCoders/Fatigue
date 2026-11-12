import SwiftUI

/// Builds a new prebuilt workout, or edits one: its name, then exercises from the library.
/// Drag exercises by their handle to reorder them, slide left to remove one, and set how many
/// sets each has and what to aim for.
struct RoutineEditor: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(ExerciseCatalog.self) private var catalog
    let isNew: Bool
    let onSave: (Routine) -> Void

    @State private var routine: Routine
    @State private var picking = false
    @FocusState private var editingName: Bool

    /// Starts a new prebuilt workout.
    init(onSave: @escaping (Routine) -> Void) {
        isNew = true
        self.onSave = onSave
        _routine = State(initialValue: Routine(name: "", exercises: []))
    }

    /// Edits a prebuilt workout you already have. It keeps its id, so it stays in the same place.
    init(editing routine: Routine, onSave: @escaping (Routine) -> Void) {
        isNew = false
        self.onSave = onSave
        _routine = State(initialValue: routine)
    }

    private var canSave: Bool { !routine.name.trimmingCharacters(in: .whitespaces).isEmpty && !routine.exercises.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Group {
                    HStack(alignment: .top) {
                        Text(isNew ? "New workout" : "Edit workout")
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
                    .padding(.bottom, Tokens.Space.l)

                    LineField(label: "Name", text: $routine.name, kind: .name, isFocused: editingName)
                        .focused($editingName)
                        .submitLabel(.done)

                    Text("Exercises")
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.foregroundMuted)
                        .padding(.top, Tokens.Space.xxl)
                }
                .plainRow(palette)

                ForEach($routine.exercises) { $exercise in
                    RoutineExerciseEditorRow(exercise: $exercise)
                        .listRowBackground(palette.background)
                        .listRowSeparatorTint(palette.borderSoft)
                        .listRowInsets(EdgeInsets(top: 0, leading: Tokens.Space.xxl, bottom: 0, trailing: Tokens.Space.xxl))
                }
                .onMove { routine.exercises.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { routine.exercises.remove(atOffsets: $0) }

                Button { picking = true } label: {
                    HStack {
                        Text("Add exercises")
                        Spacer()
                        Image(systemName: "plus")
                    }
                    .textStyle(Tokens.Typography.body)
                    .foregroundStyle(palette.foreground)
                    .frame(minHeight: Tokens.Size.primaryButton)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressRow)
                .plainRow(palette)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .environment(\.defaultMinListRowHeight, 0)

            PrimaryButton(title: isNew ? "Save workout" : "Save changes") {
                routine.name = routine.name.trimmingCharacters(in: .whitespaces)
                onSave(routine)
                dismiss()
            }
            .opacity(canSave ? 1 : 0.4)
            .disabled(!canSave)
            .animation(.quick, value: canSave)
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.vertical, Tokens.Space.l)
        }
        .background(palette.background)
        .presentationDetents([.large])
        .presentationBackground(palette.background)
        .onAppear { if isNew { editingName = true } }
        .sheet(isPresented: $picking) {
            ExercisePicker { names, brands in
                withAnimation(.standard) {
                    routine.exercises += names.map { name in
                        RoutineExercise.new(named: name, brand: brands[name], settings: catalog.setup(for: name, brand: brands[name]).settings)
                    }
                }
            }
            .environment(\.palette, palette)
        }
    }
}

/// One exercise in the routine editor: its name, how many sets, and the weight and reps to aim for.
/// Exercises whose sets differ, such as a hold then reps, show the count only; finishing a workout
/// can update those sets (see the finish summary).
private struct RoutineExerciseEditorRow: View {
    @Environment(\.palette) private var palette
    @Binding var exercise: RoutineExercise

    /// Whether every set shares a setup and target, so one weight and reps can stand for all of them.
    private var setsMatch: Bool {
        guard let first = exercise.sets.first else { return true }
        return exercise.sets.allSatisfy { $0 == first }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.name)
                    .textStyle(Tokens.Typography.body)
                    .foregroundStyle(palette.foreground)
                if let brand = exercise.brand {
                    Text(brand)
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.foregroundMuted)
                }
            }
            HStack(spacing: Tokens.Space.m) {
                HStack(spacing: 0) {
                    step("minus", label: "One set fewer") {
                        if exercise.sets.count > 1 { exercise.sets.removeLast() }
                    }
                    Text("\(exercise.sets.count) set\(exercise.sets.count == 1 ? "" : "s")")
                        .textStyle(Tokens.Typography.control)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(exercise.sets.count)))
                        .animation(.quick, value: exercise.sets.count)
                        .foregroundStyle(palette.foreground)
                        .frame(minWidth: Tokens.Size.weightColumn)
                    step("plus", label: "One more set") {
                        exercise.sets.append(exercise.sets.last ?? RoutineSet(setup: SetSetup(kind: .reps)))
                    }
                }
                Spacer()
                if setsMatch {
                    target("kg", text: Binding(
                        get: { exercise.sets.first?.weight ?? "" },
                        set: { value in for index in exercise.sets.indices { exercise.sets[index].weight = value } }
                    ))
                    Text("×").foregroundStyle(palette.foregroundFaint)
                    target(exercise.sets.first?.setup.kind == .hold ? "s" : "reps", text: Binding(
                        get: { exercise.sets.first?.amount ?? "" },
                        set: { value in for index in exercise.sets.indices { exercise.sets[index].amount = value } }
                    ))
                } else {
                    Text("Sets differ")
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.foregroundFaint)
                }
            }
        }
        .padding(.vertical, Tokens.Space.m)
        .sensoryFeedback(.selection, trigger: exercise.sets.count)
    }

    private func step(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(palette.foreground)
                .frame(width: Tokens.Size.outlinedControl, height: Tokens.Size.outlinedControl)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    private func target(_ unit: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(unit).foregroundStyle(palette.foregroundFaint))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .textStyle(Tokens.Typography.control)
            .monospacedDigit()
            .foregroundStyle(palette.foreground)
            .frame(width: Tokens.Size.amountColumn, height: Tokens.Size.cell - Tokens.Space.s)
            .background(palette.surface, in: .rect(cornerRadius: Tokens.Radius.control))
            .accessibilityLabel(unit == "kg" ? "Target weight" : "Target \(unit == "s" ? "seconds" : "reps")")
    }
}

private extension View {
    /// A list row that looks like the rest of the app: no separator, no inset background.
    func plainRow(_ palette: Palette) -> some View {
        listRowBackground(palette.background)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: Tokens.Space.xxl, bottom: 0, trailing: Tokens.Space.xxl))
    }
}
