import SwiftUI

/// The screen you log a workout on: one scrolling list of exercises, with a rest bar at the bottom.
struct WorkoutScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State var session: WorkoutSession
    @FocusState private var focused: FocusedCell?

    var body: some View {
        ScrollViewReader { proxy in
            content
                .onChange(of: session.openRPE) { _, id in
                    guard let id else { return }
                    focused = nil
                    withAnimation(.easeOut(duration: Tokens.Motion.standard)) { proxy.scrollTo(id, anchor: .center) }
                }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(session.exercises.indices, id: \.self) { index in
                        ExerciseSection(session: session, exerciseIndex: index, focus: $focused)
                        Hairline()
                    }
                    Button {} label: {
                        HStack {
                            Text("Add exercise")
                            Spacer()
                            Image(systemName: "plus")
                        }
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.foreground)
                        .frame(height: Tokens.Size.primaryButton + Tokens.Space.m)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Hairline()
                }
                .padding(.horizontal, Tokens.Space.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(palette.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomPanel }
        .overlay { GrainOverlay() }
        .animation(.easeOut(duration: Tokens.Motion.standard), value: session.rest)
        .animation(.easeOut(duration: Tokens.Motion.standard), value: session.openRPE)
        .task(id: session.rest?.endsAt) {
            guard let endsAt = session.rest?.endsAt else { return }
            try? await Task.sleep(for: .seconds(max(0, endsAt.timeIntervalSinceNow)))
            if !Task.isCancelled { restFinished = session.finishRestIfDue() }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: restFinished) { _, finished in finished }
    }

    @State private var restFinished = false

    /// The panel pinned to the bottom: the RPE scale while picking an RPE, otherwise the rest timer.
    @ViewBuilder private var bottomPanel: some View {
        if let id = session.openRPE, let place = session.place(of: id) {
            let set = session.exercises[place.exercise].sets[place.set]
            RPEPanel(
                title: "\(session.exercises[place.exercise].name) · Set \(place.set + 1)",
                selected: set.rpe,
                onPick: { value in
                    session.exercises[place.exercise].sets[place.set].rpe = value
                    session.openRPE = nil
                },
                onClose: { session.openRPE = nil }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let rest = session.rest {
            RestBar(rest: rest, onAdjust: { session.adjustRest(by: $0) }, onSkip: { session.skipRest() })
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text(session.title)
                    .textStyle(Tokens.Typography.title)
                    .foregroundStyle(palette.foreground)
                TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                    Text("\(Self.clock(context.date.timeIntervalSince(session.startedAt)))  ·  \(session.doneCount) of \(session.setCount) sets")
                        .textStyle(Tokens.Typography.control)
                        .monospacedDigit()
                        .foregroundStyle(palette.foregroundMuted)
                }
            }
            Spacer()
            PrimaryButton(title: "Finish", compact: true) { dismiss() }
        }
        .padding(.horizontal, Tokens.Space.xxl)
        .padding(.top, Tokens.Space.l)
        .padding(.bottom, Tokens.Space.xl)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// One exercise in the workout: its name, the rest, note and brand controls, and its sets.
private struct ExerciseSection: View {
    @Environment(\.palette) private var palette
    @Bindable var session: WorkoutSession
    let exerciseIndex: Int
    var focus: FocusState<FocusedCell?>.Binding
    @State private var editingNote = false
    @State private var noteDraft = ""
    @State private var pickingBrand = false
    @State private var pickingRest = false

    /// Debug builds can open a picker on launch with `-openBrand`, `-openRest` or `-openRPE`, for screenshots.
    private func openForScreenshots() {
        #if DEBUG
        guard exerciseIndex == 0 else { return }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-openBrand") { pickingBrand = true }
        if args.contains("-openRest") { pickingRest = true }
        if args.contains("-openRPE") { session.openRPE = exercise.sets.last?.id }
        #endif
    }

    private var exercise: WorkoutExercise { session.exercises[exerciseIndex] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(exercise.name)
                    .textStyle(Tokens.Typography.exerciseName)
                    .foregroundStyle(palette.foreground)
                Spacer()
                Menu {
                    Button("Reorder exercises") {}
                    Button("Remove exercise", role: .destructive) {}
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(palette.foregroundMuted)
                        .frame(width: Tokens.Size.control, height: Tokens.Size.control, alignment: .trailing)
                }
                .accessibilityLabel("Exercise options")
            }

            HStack(spacing: Tokens.Space.s) {
                Button { pickingRest = true } label: {
                    OutlinedLabel(systemImage: "timer", text: WorkoutScreen.clock(TimeInterval(exercise.restSeconds)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rest time")

                Button {
                    noteDraft = exercise.note
                    editingNote = true
                } label: {
                    OutlinedLabel(text: "Note", isMuted: exercise.note.isEmpty)
                }
                .buttonStyle(.plain)

                Button { pickingBrand = true } label: {
                    OutlinedLabel(text: exercise.brand ?? "No brand", showsChevron: true, isMuted: exercise.brand == nil)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Brand")
            }
            .padding(.top, Tokens.Space.m)

            if !exercise.note.isEmpty {
                Text(exercise.note)
                    .textStyle(Tokens.Typography.control)
                    .foregroundStyle(palette.foregroundMuted)
                    .padding(.top, Tokens.Space.m)
            }

            columnHeadings
                .padding(.top, Tokens.Space.xxl)
                .padding(.bottom, Tokens.Space.s)

            ForEach(exercise.groups) { group in
                if !group.heading.isEmpty {
                    Hairline(soft: true)
                    Text(group.heading)
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.foregroundMuted)
                        .padding(.leading, Tokens.Size.setNumberColumn + Tokens.Space.s)
                        .padding(.top, Tokens.Space.m)
                }
                ForEach(Array(group.setIndices.enumerated()), id: \.element) { position, setIndex in
                    if group.heading.isEmpty || position > 0 {
                        Hairline(soft: true)
                    }
                    SetRow(session: session, exerciseIndex: exerciseIndex, setIndex: setIndex, focus: focus)
                }
            }

            Hairline(soft: true)
            Button { session.addSet(to: exerciseIndex) } label: {
                Text("Add set")
                    .textStyle(Tokens.Typography.control)
                    .foregroundStyle(palette.foregroundMuted)
                    .frame(maxWidth: .infinity, minHeight: Tokens.Size.control, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Tokens.Space.xxxl)
        .padding(.bottom, Tokens.Space.s)
        .onAppear(perform: openForScreenshots)
        .sheet(isPresented: $pickingBrand) {
            BrandSheet(exerciseName: exercise.name, known: exercise.knownBrands, current: exercise.brand) { brand in
                session.exercises[exerciseIndex].brand = brand
            }
            .environment(\.palette, palette)
        }
        .sheet(isPresented: $pickingRest) {
            RestSheet(exerciseName: exercise.name, seconds: $session.exercises[exerciseIndex].restSeconds)
                .environment(\.palette, palette)
        }
        .alert("Note for \(exercise.name)", isPresented: $editingNote) {
            TextField("Seat height, grip, anything", text: $noteDraft)
            Button("Save") { session.exercises[exerciseIndex].note = noteDraft }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var columnHeadings: some View {
        HStack(spacing: Tokens.Space.s) {
            Color.clear.frame(width: Tokens.Size.setNumberColumn, height: 1)
            Text("Previous").frame(maxWidth: .infinity, alignment: .leading)
            Text("kg").frame(width: Tokens.Size.weightColumn)
            Text(exercise.sets.allSatisfy { $0.kind == .hold } ? "Time" : "Reps").frame(width: Tokens.Size.amountColumn)
            Text("RPE").frame(width: Tokens.Size.rpeColumn)
            Color.clear.frame(width: Tokens.Size.tickColumn, height: 1)
        }
        .textStyle(Tokens.Typography.label)
        .foregroundStyle(palette.foregroundMuted)
    }
}

/// One set: its number, what you did last time, weight, reps or time, RPE and the tick box.
private struct SetRow: View {
    @Environment(\.palette) private var palette
    @Bindable var session: WorkoutSession
    let exerciseIndex: Int
    let setIndex: Int
    var focus: FocusState<FocusedCell?>.Binding

    var body: some View {
        let set = session.exercises[exerciseIndex].sets[setIndex]
        row(set).id(set.id)
    }

    private func row(_ set: WorkoutSet) -> some View {
        HStack(spacing: Tokens.Space.s) {
            Text("\(setIndex + 1)")
                .foregroundStyle(palette.foregroundFaint)
                .frame(width: Tokens.Size.setNumberColumn, alignment: .leading)
            Text(set.previous.isEmpty ? "-" : set.previous)
                .foregroundStyle(palette.foregroundMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            NumberCell(text: $session.exercises[exerciseIndex].sets[setIndex].weight, isDone: set.isDone, accessibilityName: "Weight in kilograms", focus: focus, cell: .weight(set.id))
                .frame(width: Tokens.Size.weightColumn)
            NumberCell(
                text: $session.exercises[exerciseIndex].sets[setIndex].amount,
                suffix: set.kind == .hold ? "s" : "",
                isDone: set.isDone,
                accessibilityName: set.kind == .hold ? "Seconds" : "Reps",
                focus: focus,
                cell: .amount(set.id)
            )
            .frame(width: Tokens.Size.amountColumn)
            RPECell(rpe: set.rpe, isDone: set.isDone, isOpen: session.openRPE == set.id) {
                focus.wrappedValue = nil
                session.openRPE = session.openRPE == set.id ? nil : set.id
            }
            .frame(width: Tokens.Size.rpeColumn)
            TickBox(isDone: set.isDone) { session.toggle(set: setIndex, in: exerciseIndex) }
        }
        .textStyle(Tokens.Typography.control)
        .monospacedDigit()
        .frame(height: Tokens.Size.setRow)
    }
}

/// The rest countdown pinned to the bottom of the screen, with a thin progress line across the top.
private struct RestBar: View {
    @Environment(\.palette) private var palette
    let rest: RestTimer
    let onAdjust: (TimeInterval) -> Void
    let onSkip: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = max(0, rest.endsAt.timeIntervalSince(context.date))
            let progress = rest.total > 0 ? 1 - remaining / rest.total : 1
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(palette.border)
                        Rectangle().fill(palette.foreground).frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: Tokens.Size.line)

                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                    Text(WorkoutScreen.clock(remaining.rounded(.up)))
                        .textStyle(Tokens.Typography.timer)
                        .monospacedDigit()
                        .foregroundStyle(palette.foreground)
                    Text("Rest")
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.foregroundMuted)
                    Spacer()
                    restButton("-15") { onAdjust(-15) }
                    restButton("+15") { onAdjust(15) }
                    Button(action: onSkip) { OutlinedLabel(text: "Skip") }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, Tokens.Space.xxl)
                .padding(.vertical, Tokens.Space.l)
            }
            .background(palette.background.ignoresSafeArea(edges: .bottom))
        }
    }

    private func restButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .textStyle(Tokens.Typography.control)
                .foregroundStyle(palette.foreground)
                .frame(width: Tokens.Size.control, height: Tokens.Size.control)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "+15" ? "Add 15 seconds" : "Remove 15 seconds")
    }
}

#Preview("Light") {
    WorkoutScreen(session: .sample())
        .environment(\.palette, .light)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    WorkoutScreen(session: .sample())
        .environment(\.palette, .dark)
        .preferredColorScheme(.dark)
}
