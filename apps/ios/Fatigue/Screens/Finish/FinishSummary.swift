import SwiftUI

/// What you chose on the finish summary.
struct FinishDetails {
    var title: String
    var description: String
    var unticked: UntickedSets
    var updateRoutine: Bool
}

/// Shown when you finish a workout: how it went, a name and description to save it under, photos and
/// videos to keep with it, and, if it started from a prebuilt workout and you changed things, whether to update that one too.
struct FinishSummary: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(MediaStore.self) private var media
    let session: WorkoutSession
    let unticked: UntickedSets
    /// The prebuilt workout it started from, only when today's workout differs from it.
    let changedRoutine: Routine?
    /// Workouts finished before this one, for the records it beat.
    var history: [FinishedWorkout] = []
    let onSave: (FinishDetails) -> Void

    @State private var title: String
    @State private var description = ""
    @State private var updateRoutine = false
    @FocusState private var focus: Field?
    private let finishedAt = Date.now

    private enum Field { case title, description }

    init(session: WorkoutSession, unticked: UntickedSets, changedRoutine: Routine?, history: [FinishedWorkout] = [], onSave: @escaping (FinishDetails) -> Void) {
        self.session = session
        self.unticked = unticked
        self.changedRoutine = changedRoutine
        self.history = history
        self.onSave = onSave
        _title = State(initialValue: session.title)
    }

    private var workout: FinishedWorkout { session.preview(unticked: unticked, at: finishedAt) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Workout done")
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                        Spacer()
                        Button { dismiss() } label: {
                            Text("Back to workout")
                                .textStyle(Tokens.Typography.control)
                                .foregroundStyle(palette.foregroundMuted)
                                .frame(minHeight: Tokens.Size.control)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressRow)
                    }

                    TextField("", text: $title, prompt: Text("Name").foregroundStyle(palette.foregroundFaint))
                        .textStyle(Tokens.Typography.title)
                        .foregroundStyle(palette.foreground)
                        .focused($focus, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focus = .description }
                        .accessibilityLabel("Workout name")
                    TextField("", text: $description, prompt: Text("How did it go?").foregroundStyle(palette.foregroundFaint), axis: .vertical)
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.foregroundMuted)
                        .focused($focus, equals: .description)
                        .lineLimit(1...6)
                        .padding(.top, Tokens.Space.s)
                        .accessibilityLabel("Description")

                    stats
                        .padding(.top, Tokens.Space.xxl)

                    Hairline().padding(.top, Tokens.Space.xxl)
                    if workout.exercises.isEmpty {
                        Text("No sets ticked, so there's nothing to save. Go back to tick them, or count them as done.")
                            .textStyle(Tokens.Typography.body)
                            .foregroundStyle(palette.foregroundMuted)
                            .padding(.vertical, Tokens.Space.l)
                    }
                    ForEach(Array(workout.exercises.enumerated()), id: \.offset) { _, exercise in
                        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                            Text("\(exercise.sets.count) set\(exercise.sets.count == 1 ? "" : "s")")
                                .monospacedDigit()
                                .foregroundStyle(palette.foregroundMuted)
                                .frame(width: Tokens.Size.weightColumn, alignment: .leading)
                            Text(exercise.name)
                                .foregroundStyle(palette.foreground)
                            if let brand = exercise.brand {
                                Text(brand).foregroundStyle(palette.foregroundFaint)
                            }
                        }
                        .textStyle(Tokens.Typography.control)
                        .padding(.vertical, Tokens.Space.xs)
                    }
                    .padding(.top, Tokens.Space.m)

                    records

                    if !workout.exercises.isEmpty {
                        Hairline().padding(.top, Tokens.Space.xl)
                        // Keyed by the running workout's id; finishing moves them to the saved one.
                        MediaRow(workoutID: session.id)
                            .padding(.top, Tokens.Space.l)
                    }

                    if let changedRoutine {
                        Hairline().padding(.top, Tokens.Space.xl)
                        HStack(alignment: .center, spacing: Tokens.Space.m) {
                            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                                Text("Update \(changedRoutine.name)")
                                    .textStyle(Tokens.Typography.body)
                                    .foregroundStyle(palette.foreground)
                                Text("Use today's exercises, sets and weights next time.")
                                    .textStyle(Tokens.Typography.caption)
                                    .foregroundStyle(palette.foregroundMuted)
                            }
                            Spacer(minLength: Tokens.Space.s)
                            HStack(spacing: Tokens.Space.s) {
                                Button { updateRoutine = false } label: { OptionLabel(title: "No", isSelected: !updateRoutine) }
                                    .buttonStyle(.press)
                                Button { updateRoutine = true } label: { OptionLabel(title: "Yes", isSelected: updateRoutine) }
                                    .buttonStyle(.press)
                            }
                        }
                        .padding(.vertical, Tokens.Space.l)
                        .sensoryFeedback(.selection, trigger: updateRoutine)
                    }
                }
                .padding(.horizontal, Tokens.Space.xxl)
                .padding(.top, Tokens.Space.l)
                .padding(.bottom, Tokens.Space.xxxl)
            }
            .scrollDismissesKeyboard(.interactively)

            // Saving waits for media still being copied in, so nothing is left behind under the running workout's id.
            let addingMedia = media.importing.contains(session.id)
            PrimaryButton(title: addingMedia ? "Adding media…" : workout.exercises.isEmpty ? "Finish without saving" : "Save workout") {
                onSave(FinishDetails(title: title, description: description, unticked: unticked, updateRoutine: updateRoutine))
            }
            .disabled(addingMedia)
            .opacity(addingMedia ? 0.5 : 1)
            .animation(.standard, value: addingMedia)
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.vertical, Tokens.Space.l)
        }
        .background(palette.background)
        .overlay { GrainOverlay() }
        .presentationDetents([.large])
        .presentationBackground(palette.background)
    }

    /// The records this workout beat, such as "Adductors · Heaviest weight · 60 kg". Nothing when it beat none.
    @ViewBuilder private var records: some View {
        let beaten = ExerciseStats.beaten(by: workout, history: history)
        if !beaten.isEmpty {
            Hairline().padding(.top, Tokens.Space.xl)
            Text("Records")
                .textStyle(Tokens.Typography.caption)
                .foregroundStyle(palette.foregroundMuted)
                .padding(.top, Tokens.Space.l)
                .padding(.bottom, Tokens.Space.xs)
            ForEach(beaten) { record in
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                    Image(systemName: "arrow.up")
                        .imageScale(.small)
                        .foregroundStyle(palette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.record)
                            .foregroundStyle(palette.foreground)
                        Text([record.exercise, record.brand].compactMap { $0 }.joined(separator: " · "))
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                    }
                    Spacer()
                    Text(record.value)
                        .monospacedDigit()
                        .foregroundStyle(palette.foreground)
                }
                .textStyle(Tokens.Typography.control)
                .padding(.vertical, Tokens.Space.xs)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Time, sets and volume, side by side in large numbers.
    private var stats: some View {
        HStack(alignment: .top, spacing: 0) {
            stat(HistoryRow.duration(max(1, Int((workout.duration / 60).rounded()))), label: "Time")
            stat("\(workout.setCount)", label: "Sets")
            stat(workout.volume > 0 ? "\(Int(workout.volume).formatted()) kg" : "-", label: "Volume")
        }
    }

    private func stat(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(value)
                .textStyle(Tokens.Typography.exerciseName)
                .monospacedDigit()
                .foregroundStyle(palette.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .textStyle(Tokens.Typography.caption)
                .foregroundStyle(palette.foregroundMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
