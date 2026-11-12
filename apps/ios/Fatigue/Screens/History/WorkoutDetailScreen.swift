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
                    onMinimise: { editing = nil },
                    onFinish: {
                        if let workout { withAnimation(.standard) { store.replace(workout.updated(from: session)) } }
                        editing = nil
                        if workout == nil { dismiss() }
                    }
                )
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
            Button("Edit workout", systemImage: "pencil") { editing = workout?.editingSession() }
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
                }
                .padding(.bottom, Tokens.Space.xxl)
                Hairline()

                ForEach(Array(workout.exercises.enumerated()), id: \.offset) { _, exercise in
                    ExerciseRecord(exercise: exercise)
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

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                Text(exercise.name)
                    .textStyle(Tokens.Typography.exerciseName)
                    .foregroundStyle(palette.foreground)
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
                        setLine(number: index + 1, set: exercise.sets[index])
                    }
                }
            }
        }
        .padding(.vertical, Tokens.Space.xl)
    }

    private func setLine(number: Int, set: WorkoutSet) -> some View {
        HStack(spacing: Tokens.Space.l) {
            Text("\(number)")
                .foregroundStyle(palette.foregroundFaint)
                .frame(width: Tokens.Size.setNumberColumn, alignment: .leading)
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
