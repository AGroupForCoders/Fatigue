import SwiftUI

/// The screen you log a workout on: one scrolling list of exercises, with a rest bar at the bottom.
struct WorkoutScreen: View {
    enum Mode {
        /// A workout happening now: elapsed time, rest timer, Finish.
        case live
        /// A finished workout opened from history: its date, no rest timer, Save, and × to drop the changes.
        case editing
    }

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var session: WorkoutSession
    /// Running now, or a finished workout opened from history to fix.
    var mode: Mode = .live
    /// Hides the screen and leaves the workout running in the bar above the bottom nav.
    var onMinimise: () -> Void = {}
    var onFinish: () -> Void = {}
    @FocusState private var focused: FocusedCell?
    @State private var addingExercises = false

    var body: some View {
        ScrollViewReader { proxy in
            content
                .onChange(of: focused) { old, new in
                    if case .note = old, old != new {
                        withAnimation(.standard) { session.removeEmptyNotes() }
                    }
                }
                .onChange(of: session.openRPE) { _, id in
                    guard let id else { return }
                    focused = nil
                    withAnimation(.standard) { proxy.scrollTo(id, anchor: .center) }
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
                    if session.exercises.isEmpty {
                        Text("No exercises yet. Add the first one to get going.")
                            .textStyle(Tokens.Typography.body)
                            .foregroundStyle(palette.foregroundMuted)
                            .padding(.vertical, Tokens.Space.xxxl)
                    }
                    Button { addingExercises = true } label: {
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
                    .buttonStyle(.pressRow)
                    Hairline()
                }
                .padding(.horizontal, Tokens.Space.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(palette.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomPanel }
        .overlay { GrainOverlay() }
        .animation(.standard, value: session.rest == nil)
        .animation(.standard, value: session.openRPE)
        .task(id: session.rest?.endsAt) {
            guard let endsAt = session.rest?.endsAt else { return }
            try? await Task.sleep(for: .seconds(max(0, endsAt.timeIntervalSinceNow)))
            if !Task.isCancelled { restFinished = session.finishRestIfDue() }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: restFinished) { _, finished in finished }
        .sheet(isPresented: $addingExercises) {
            ExercisePicker { names in
                withAnimation(.standard) { session.addExercises(named: names) }
            }
            .environment(\.palette, palette)
        }
    }

    @State private var restFinished = false

    /// The panel pinned to the bottom: the RPE scale while picking an RPE, otherwise the rest timer.
    /// The container rises from the bottom edge when the first of them appears. Switching between
    /// the two only crossfades in place, so the bottom of the screen never has two panels sliding past each other.
    @ViewBuilder private var bottomPanel: some View {
        if session.openRPE != nil || session.rest != nil {
            ZStack(alignment: .bottom) { panelContent }
                .background(palette.background.ignoresSafeArea(edges: .bottom))
                .transition(.bottomPanel(reduceMotion: reduceMotion))
        }
    }

    @ViewBuilder private var panelContent: some View {
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
            .transition(.opacity)
        } else if let rest = session.rest {
            RestBar(rest: rest, onAdjust: { session.adjustRest(by: $0) }, onSkip: { session.skipRest() })
                .transition(.opacity)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Button(action: onMinimise) {
                    Image(systemName: mode == .live ? "chevron.down" : "xmark")
                        .foregroundStyle(palette.foregroundMuted)
                        .frame(width: Tokens.Size.control, height: Tokens.Size.control, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.press)
                .accessibilityLabel(mode == .live ? "Minimise workout" : "Close without saving")
                TextField("", text: $session.title)
                    .textStyle(Tokens.Typography.title)
                    .foregroundStyle(palette.foreground)
                    .submitLabel(.done)
                    .accessibilityLabel("Workout name")
                if mode == .editing {
                    Text("\(session.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide)))  ·  \(session.doneCount) sets")
                        .textStyle(Tokens.Typography.control)
                        .monospacedDigit()
                        .foregroundStyle(palette.foregroundMuted)
                } else {
                TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                    HStack(spacing: 0) {
                        Text("\(Self.clock(context.date.timeIntervalSince(session.startedAt)))  ·  ")
                        Text("\(session.doneCount)")
                            .contentTransition(.numericText(value: Double(session.doneCount)))
                            .animation(.quick, value: session.doneCount)
                        Text(" of \(session.setCount) sets")
                    }
                    .textStyle(Tokens.Typography.control)
                    .monospacedDigit()
                    .foregroundStyle(palette.foregroundMuted)
                }
                }
            }
            Spacer()
            PrimaryButton(title: mode == .live ? "Finish" : "Save", compact: true, action: onFinish)
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
    @State private var pickingBrand = false
    @State private var editingSetup: SetupEdit?
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

            notes

            HStack(spacing: Tokens.Space.s) {
                Button { pickingRest = true } label: {
                    OutlinedLabel(systemImage: "timer", text: WorkoutScreen.clock(TimeInterval(exercise.restSeconds)))
                }
                .buttonStyle(.press)
                .accessibilityLabel("Rest time")

                Button {
                    let id = withAnimation(.standard) { session.addNote(to: exerciseIndex) }
                    focus.wrappedValue = .note(id)
                } label: {
                    OutlinedLabel(systemImage: "plus", text: "Note", isMuted: exercise.notes.isEmpty)
                }
                .buttonStyle(.press)
                .accessibilityLabel("Add a note")

                Button { pickingBrand = true } label: {
                    OutlinedLabel(text: exercise.brand ?? "No brand", showsChevron: true, isMuted: exercise.brand == nil)
                }
                .buttonStyle(.press)
                .accessibilityLabel("Brand")
            }
            .padding(.top, Tokens.Space.m)

            columnHeadings
                .padding(.top, Tokens.Space.xxl)
                .padding(.bottom, Tokens.Space.s)

            ForEach(exercise.groups) { group in
                if !group.heading.isEmpty {
                    Hairline(soft: true)
                    Button {
                        if let first = group.setIndices.first {
                            editingSetup = .group(group.setIndices, exercise.sets[first].setup)
                        }
                    } label: {
                        HStack(spacing: Tokens.Space.xs) {
                            Text(group.heading)
                            Image(systemName: "chevron.down")
                                .imageScale(.small)
                                .foregroundStyle(palette.foregroundFaint)
                        }
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.foregroundMuted)
                        .padding(.leading, Tokens.Size.setNumberColumn + Tokens.Space.s)
                        .padding(.top, Tokens.Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressRow)
                    .accessibilityLabel("\(group.heading). Change setup")
                    .transition(.opacity)
                }
                // Keyed by set id, not position, so a deleted row's swipe state never lands on the row that moves up.
                ForEach(group.setIndices.map { exercise.sets[$0].id }, id: \.self) { setID in
                    let setIndex = exercise.sets.firstIndex { $0.id == setID } ?? 0
                    VStack(spacing: 0) {
                        if group.heading.isEmpty || setIndex != group.setIndices.first {
                            Hairline(soft: true)
                        }
                        SwipeToDelete(accessibilityName: "set \(setIndex + 1)") {
                            session.deleteSet(setID)
                        } content: {
                            SetRow(session: session, setID: setID, number: setIndex + 1, focus: focus)
                        }
                    }
                    .transition(.opacity)
                }
            }

            Hairline(soft: true)
            addSetMenu
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
        .sheet(item: $editingSetup) { edit in
            SetupSheet(exercise: exercise, setup: edit.setup, actionTitle: edit.actionTitle) { setup in
                withAnimation(.standard) {
                    switch edit {
                    case .group(let indices, _): session.changeSetup(of: indices, in: exerciseIndex, to: setup)
                    case .new: session.addSet(to: exerciseIndex, setup: setup)
                    }
                }
            }
            .environment(\.palette, palette)
        }
    }

    /// The exercise's notes, each a free-form text box under the name. Note adds another one below.
    /// A note left empty is removed when you leave it.
    @ViewBuilder private var notes: some View {
        if !exercise.notes.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                ForEach(exercise.notes) { note in
                    SwipeToDelete(accessibilityName: "note") {
                        session.deleteNote(note.id)
                    } content: {
                        TextField("", text: noteText(note.id), prompt: Text("Seat height, grip, anything").foregroundStyle(palette.foregroundFaint), axis: .vertical)
                            .textStyle(Tokens.Typography.control)
                            .foregroundStyle(palette.foregroundMuted)
                            .focused(focus, equals: .note(note.id))
                            .padding(.vertical, Tokens.Space.xs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, Tokens.Space.s)
        }
    }

    /// A note's text looked up by id, so a note deleted mid-edit never leaves a binding to a missing index.
    private func noteText(_ id: UUID) -> Binding<String> {
        Binding {
            session.exercises[exerciseIndex].notes.first { $0.id == id }?.text ?? ""
        } set: { text in
            if let index = session.exercises[exerciseIndex].notes.firstIndex(where: { $0.id == id }) {
                session.exercises[exerciseIndex].notes[index].text = text
            }
        }
    }

    /// Tap adds a set like the last one. Press and hold to pick another setup this exercise uses,
    /// or start a new one, which gets its own heading.
    private var addSetMenu: some View {
        Menu {
            ForEach(exercise.setups, id: \.self) { setup in
                Button(exercise.heading(for: setup)) {
                    withAnimation(.standard) { session.addSet(to: exerciseIndex, setup: setup) }
                }
            }
            Divider()
            Button("New setup", systemImage: "plus") {
                editingSetup = .new(exercise.sets.last?.setup ?? SetSetup(kind: .reps))
            }
        } label: {
            HStack {
                Text("Add set")
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(palette.foregroundFaint)
            }
            .textStyle(Tokens.Typography.control)
            .foregroundStyle(palette.foregroundMuted)
            .frame(maxWidth: .infinity, minHeight: Tokens.Size.control, alignment: .leading)
            .contentShape(Rectangle())
        } primaryAction: {
            withAnimation(.standard) { session.addSet(to: exerciseIndex) }
        }
        .accessibilityHint("Press and hold to pick a setup")
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
    let setID: UUID
    /// The set's number within its exercise, starting at 1.
    let number: Int
    var focus: FocusState<FocusedCell?>.Binding

    var body: some View {
        // Looked up by id on every render, so a row that is animating out after a delete draws nothing
        // instead of reading an index that no longer exists.
        if let place = session.place(of: setID) {
            row(session.exercises[place.exercise].sets[place.set], exercise: place.exercise, index: place.set)
                .id(setID)
        }
    }

    private func row(_ set: WorkoutSet, exercise e: Int, index i: Int) -> some View {
        HStack(spacing: Tokens.Space.s) {
            Text("\(number)")
                .foregroundStyle(palette.foregroundFaint)
                .contentTransition(.numericText(value: Double(number)))
                .frame(width: Tokens.Size.setNumberColumn, alignment: .leading)
            Text(set.previous.isEmpty ? "-" : set.previous)
                .foregroundStyle(palette.foregroundMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            NumberCell(text: $session.exercises[e].sets[i].weight, isDone: set.isDone, accessibilityName: "Weight in kilograms", focus: focus, cell: .weight(set.id))
                .frame(width: Tokens.Size.weightColumn)
            NumberCell(
                text: $session.exercises[e].sets[i].amount,
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
            TickBox(isDone: set.isDone) { session.toggle(set: i, in: e) }
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
                // Scaled rather than resized, so each tick only moves pixels and never re-lays out the bar.
                // Linear over the same quarter second as the timeline, so the line creeps instead of stepping.
                ZStack(alignment: .leading) {
                    Rectangle().fill(palette.border)
                    Rectangle().fill(palette.foreground)
                        .scaleEffect(x: progress, anchor: .leading)
                        .animation(.linear(duration: 0.25), value: progress)
                }
                .frame(height: Tokens.Size.line)

                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                    Text(WorkoutScreen.clock(remaining.rounded(.up)))
                        .textStyle(Tokens.Typography.timer)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.quick, value: remaining.rounded(.up))
                        .foregroundStyle(palette.foreground)
                    Text("Rest")
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.foregroundMuted)
                    Spacer()
                    restButton("-15") { onAdjust(-15) }
                    restButton("+15") { onAdjust(15) }
                    Button(action: onSkip) { OutlinedLabel(text: "Skip") }
                        .buttonStyle(.press)
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
        .buttonStyle(.press)
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

/// What the setup sheet is doing: changing a group's setup, or adding a set with a new one.
private enum SetupEdit: Identifiable {
    case group([Int], SetSetup)
    case new(SetSetup)

    var id: String {
        switch self {
        case .group(let indices, _): "group-\(indices.first ?? 0)"
        case .new: "new"
        }
    }

    var setup: SetSetup {
        switch self {
        case .group(_, let setup), .new(let setup): setup
        }
    }

    var actionTitle: String {
        switch self {
        case .group(let indices, _): indices.count == 1 ? "Change 1 set" : "Change \(indices.count) sets"
        case .new: "Add set"
        }
    }
}
