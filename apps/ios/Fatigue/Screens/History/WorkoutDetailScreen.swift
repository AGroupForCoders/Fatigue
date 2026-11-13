import SwiftUI

/// A finished workout, read only: every exercise with its brand, setup headings and sets.
/// The menu at the top right edits it on the workout screen, saves it as a prebuilt workout, or deletes it.
struct WorkoutDetailScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkoutStore.self) private var store
    let workoutID: UUID

    @State private var editing: WorkoutSession?
    @State private var confirmingDelete = false
    @State private var savedAsRoutine = false
    @State private var editingDetails = false

    private var workout: FinishedWorkout? { store.history.first { $0.id == workoutID } }

    var body: some View {
        Group {
            if let workout { content(workout) }
        }
        .background(palette.background)
        .toolbarRole(.editor)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { menu }
        }
        .fullScreenCover(item: $editing) { session in
            ThemeProvider {
                WorkoutScreen(
                    session: session,
                    mode: .editing,
                    history: store.history,
                    onMinimise: { editing = nil },
                    onFinish: { _ in
                        if let workout { withAnimation(.standard) { store.replace(workout.updated(from: session)) } }
                        editing = nil
                        if workout == nil { dismiss() }
                    }
                )
            }
        }
        .sheet(isPresented: $editingDetails) {
            if let workout {
                WorkoutDetailsSheet(title: workout.title, description: workout.description) { title, description in
                    store.rename(workoutID, title: title, description: description)
                }
                .environment(\.palette, palette)
            }
        }
        .confirmationDialog("Delete \(workout?.title ?? "workout")?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete workout", role: .destructive) {
                dismiss()
                store.deleteFromHistory(workoutID)
            }
        } message: {
            Text("It's removed from your history for good.")
        }
        .sensoryFeedback(.success, trigger: savedAsRoutine) { _, saved in saved }
    }

    private var menu: some View {
        Menu {
            Button("Edit name and description", systemImage: "text.cursor") { editingDetails = true }
            Button("Edit sets", systemImage: "pencil") { editing = workout?.editingSession() }
            Button(savedAsRoutine ? "Saved to your workouts" : "Save as prebuilt workout", systemImage: savedAsRoutine ? "checkmark" : "plus") {
                guard let workout, !savedAsRoutine else { return }
                store.add(workout.asRoutine())
                savedAsRoutine = true
            }
            Button("Delete workout", systemImage: "trash", role: .destructive) { confirmingDelete = true }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(palette.foreground)
        }
        .accessibilityLabel("Workout options")
    }

    private func content(_ workout: FinishedWorkout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    Text(workout.title)
                        .textStyle(Tokens.Typography.title)
                        .foregroundStyle(palette.foreground)
                    Text(HistoryRow.summary(workout))
                        .textStyle(Tokens.Typography.control)
                        .monospacedDigit()
                        .foregroundStyle(palette.foregroundMuted)
                    if !workout.description.isEmpty {
                        Text(workout.description)
                            .textStyle(Tokens.Typography.body)
                            .foregroundStyle(palette.foreground)
                            .padding(.top, Tokens.Space.s)
                    }
                }
                .padding(.bottom, Tokens.Space.xxl)
                Hairline()

                ForEach(Array(workout.exercises.enumerated()), id: \.offset) { _, exercise in
                    ExerciseRecord(exercise: exercise, history: store.history)
                    Hairline()
                }
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.top, Tokens.Space.s)
            .padding(.bottom, Tokens.Space.xxxl)
        }
    }
}

/// One exercise of a finished workout: name and brand, notes, then its sets under their setup headings.
private struct ExerciseRecord: View {
    @Environment(\.palette) private var palette
    let exercise: WorkoutExercise
    let history: [FinishedWorkout]
    @State private var showingStats = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                Button { showingStats = true } label: {
                    Text(exercise.name)
                        .textStyle(Tokens.Typography.exerciseName)
                        .foregroundStyle(palette.foreground)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.press)
                .accessibilityHint("Shows your progress on this exercise")
                .sheet(isPresented: $showingStats) {
                    ExerciseScreen(name: exercise.name, brand: exercise.brand, history: history)
                        .environment(\.palette, palette)
                }
                if let brand = exercise.brand {
                    Text(brand)
                        .textStyle(Tokens.Typography.control)
                        .foregroundStyle(palette.foregroundMuted)
                }
            }
            if !exercise.settings.isEmpty {
                Text(exercise.settings.map { "\($0.name) \(SettingEditor.displayValue($0))" }.joined(separator: " · "))
                    .textStyle(Tokens.Typography.control)
                    .foregroundStyle(palette.foregroundMuted)
            }
            ForEach(exercise.notes) { note in
                Text(note.text)
                    .textStyle(Tokens.Typography.control)
                    .foregroundStyle(palette.foregroundMuted)
            }
            ForEach(exercise.groups) { group in
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    if !group.heading.isEmpty {
                        Text(group.heading)
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                            .padding(.top, Tokens.Space.s)
                    }
                    ForEach(group.setIndices, id: \.self) { index in
                        setLine(mark: exercise.sets.mark(at: index), spoken: exercise.sets.spokenName(at: index), set: exercise.sets[index])
                    }
                }
            }
        }
        .padding(.vertical, Tokens.Space.xl)
    }

    /// `mark` is the set's number, or W, D or F for a warm-up, drop set or set to failure.
    private func setLine(mark: String, spoken: String, set: WorkoutSet) -> some View {
        HStack(spacing: Tokens.Space.l) {
            Text(mark)
                .foregroundStyle(set.type == .normal ? palette.foregroundFaint : palette.foregroundMuted)
                .frame(width: Tokens.Size.setNumberColumn, alignment: .leading)
                .accessibilityLabel(spoken)
            Text("\(set.weight.isEmpty ? "-" : set.weight) × \(set.amount)\(set.kind == .hold ? "s" : "")")
                .foregroundStyle(palette.foreground)
            if let rpe = set.rpe {
                Text("@\(PlainNumber.string(rpe))")
                    .foregroundStyle(palette.foregroundMuted)
            }
            Spacer()
        }
        .textStyle(Tokens.Typography.number)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

/// Changes a finished workout's name and description.
private struct WorkoutDetailsSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State var title: String
    @State var description: String
    let onSave: (String, String) -> Void
    @FocusState private var focus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xxl) {
            HStack {
                Text("Name and description")
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
            LineField(label: "Name", text: $title, kind: .name, isFocused: focus)
                .focused($focus)
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text("Description")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
                TextField("", text: $description, prompt: Text("How did it go?").foregroundStyle(palette.foregroundFaint), axis: .vertical)
                    .textStyle(Tokens.Typography.body)
                    .foregroundStyle(palette.foreground)
                    .lineLimit(2...8)
                Hairline()
            }
            Spacer()
            PrimaryButton(title: "Save") {
                onSave(title, description)
                dismiss()
            }
        }
        .padding(Tokens.Space.xxl)
        .background(palette.background)
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.background)
    }
}
