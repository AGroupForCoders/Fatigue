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
    @Environment(ExerciseCatalog.self) private var catalog
    @State var session: WorkoutSession
    /// Running now, or a finished workout opened from history to fix.
    var mode: Mode = .live
    /// Your finished workouts, for spotting records. Only the ones started before this workout count.
    var history: [FinishedWorkout] = []
    /// Hides the screen and leaves the workout running in the bar above the bottom nav.
    var onMinimise: () -> Void = {}
    /// The prebuilt workout this started from, so the finish summary can offer to update it.
    var routine: Routine? = nil
    /// Called from the finish summary when live, or from Save when editing a past workout.
    var onFinish: (FinishDetails) -> Void = { _ in }
    /// Called with an exercise's name after it's deleted from the library, to take it out of prebuilt workouts.
    var onDeleteExercise: (String) -> Void = { _ in }
    @State private var confirmingUnticked = false
    @State private var reordering = false
    @State private var finishing: Finishing?

    /// The summary being shown, and what was chosen for unticked sets on the way there.
    private struct Finishing: Identifiable {
        let id = UUID()
        let unticked: UntickedSets
    }
    @FocusState private var focused: FocusedCell?
    @State private var addingExercises = false
    /// Exercise pages pushed on top of the workout, from an exercise's name.
    @State private var exercisePath: [ExerciseRoute] = []

    /// The workout sits in its own navigation stack, so tapping an exercise's name pushes its page and back
    /// comes straight back to your sets. The rest bar is outside the stack, so it stays on the exercise page too.
    var body: some View {
        NavigationStack(path: $exercisePath) {
            workout
                .toolbar(.hidden, for: .navigationBar)
                .exercisePages(history: history)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomPanel }
        .animation(.standard, value: session.rest == nil)
        .animation(.standard, value: session.openRPE)
    }

    private var workout: some View {
        ScrollViewReader { proxy in
            content
                .onChange(of: focused) { old, new in
                    if case .note = old, old != new {
                        withAnimation(.standard) { session.removeEmptyNotes() }
                    }
                    if Self.isSetting(old), !Self.isSetting(new) {
                        withAnimation(.standard) { session.removeEmptySettings() }
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
                let records = RecordBook.marks(for: session.exercises, after: history.filter { $0.startedAt < session.startedAt })
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(session.exercises) { exercise in
                        ExerciseSection(
                            session: session, exerciseID: exercise.id, records: records, history: history, focus: $focused,
                            onReorder: { reordering = true }, onDeleteExercise: onDeleteExercise
                        )
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
        .overlay { GrainOverlay() }
        .task(id: session.rest?.endsAt) {
            guard let endsAt = session.rest?.endsAt else { return }
            try? await Task.sleep(for: .seconds(max(0, endsAt.timeIntervalSinceNow)))
            if !Task.isCancelled, session.finishRestIfDue() { restsFinished += 1 }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: restsFinished)
        .confirmationDialog(
            "\(session.untickedCount) set\(session.untickedCount == 1 ? " isn't" : "s aren't") ticked",
            isPresented: $confirmingUnticked,
            titleVisibility: .visible
        ) {
            Button("Count them as done") { finishing = Finishing(unticked: .count) }
            Button("Leave them out") { finishing = Finishing(unticked: .drop) }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Only ticked sets are saved unless you count the rest as done.")
        }
        .sheet(item: $finishing) { choice in
            FinishSummary(
                session: session,
                unticked: choice.unticked,
                changedRoutine: routine.flatMap { $0.differs(from: session) ? $0 : nil },
                history: history.filter { $0.startedAt < session.startedAt }
            ) { details in
                finishing = nil
                onFinish(details)
            }
            .environment(\.palette, palette)
        }
        .onAppear {
            // Debug builds open the finish summary on launch with `-openFinish`, for screenshots.
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-openFinish"), mode == .live {
                session.exercises[0].sets[2].weight = "57.5"
                finishing = Finishing(unticked: .count)
            }
            // `-openExercise` pushes the first exercise's page.
            if ProcessInfo.processInfo.arguments.contains("-openExercise"), exercisePath.isEmpty, let first = session.exercises.first {
                exercisePath = [ExerciseRoute(name: first.name, brand: first.brand)]
            }
            #endif
        }
        .sheet(isPresented: $reordering) {
            ReorderExercises(session: session)
                .environment(\.palette, palette)
        }
        .sheet(isPresented: $addingExercises) {
            ExercisePicker { names, brands in
                withAnimation(.standard) { session.addExercises(named: names, brands: brands, catalog: catalog) }
            }
            .environment(\.palette, palette)
        }
    }

    /// Counts rests that ended on this screen, so each one gets its haptic.
    @State private var restsFinished = 0

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
                title: "\(session.exercises[place.exercise].name) · \(session.exercises[place.exercise].sets.spokenName(at: place.set))",
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
            PrimaryButton(title: mode == .live ? "Finish" : "Save", compact: true, action: finish)
        }
        .padding(.horizontal, Tokens.Space.xxl)
        .padding(.top, Tokens.Space.l)
        .padding(.bottom, Tokens.Space.xl)
    }

    private static func isSetting(_ cell: FocusedCell?) -> Bool {
        switch cell {
        case .settingName, .settingValue: true
        default: false
        }
    }

    /// Live: asks about unticked sets if there are any, then shows the summary.
    /// Editing a past workout: saves straight away.
    private func finish() {
        focused = nil
        guard mode == .live else {
            onFinish(FinishDetails(title: session.title, description: "", unticked: .drop, updateRoutine: false))
            return
        }
        if session.untickedCount > 0, session.setCount > 0 {
            confirmingUnticked = true
        } else {
            finishing = Finishing(unticked: .drop)
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// One exercise in the workout: its name, the rest, note and brand controls, and its sets.
private struct ExerciseSection: View {
    @Environment(\.palette) private var palette
    @Environment(ExerciseCatalog.self) private var catalog
    @Environment(WorkoutStore.self) private var store
    @AppStorage(WeightUnit.storageKey) private var unit: WeightUnit = .kg
    @Bindable var session: WorkoutSession
    /// Keyed by id, not position, so removing or reordering exercises never points a section at the wrong one.
    let exerciseID: UUID
    /// The records each ticked set sets, keyed by set id.
    let records: [UUID: Set<RecordKind>]
    /// Finished workouts, for the brands you've used on this exercise.
    let history: [FinishedWorkout]
    var focus: FocusState<FocusedCell?>.Binding
    var onReorder: () -> Void = {}
    /// Takes a deleted exercise out of prebuilt workouts. The library and this workout are handled here.
    var onDeleteExercise: (String) -> Void = { _ in }

    private var exerciseIndex: Int { session.exercises.firstIndex { $0.id == exerciseID } ?? 0 }
    @State private var editingExercise = false
    @State private var confirmingRemove = false
    /// Whether the settings line is opened up into editable rows.
    @State private var editingSettings = false
    @State private var pickingBrand = false
    @State private var editingSetup: SetupEdit?
    @State private var pickingRest = false

    /// Debug builds can open a picker on launch with `-openBrand`, `-openRest`, `-openRPE`, `-editExercise` or `-editSettings`, for screenshots.
    private func openForScreenshots() {
        #if DEBUG
        guard session.exercises.first?.id == exerciseID else { return }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-openBrand") { pickingBrand = true }
        if args.contains("-openRest") { pickingRest = true }
        if args.contains("-editExercise") { editingExercise = true }
        if args.contains("-editSettings") { editingSettings = true }
        if args.contains("-openRPE") { session.openRPE = exercise.sets.last?.id }
        #endif
    }

    private var exercise: WorkoutExercise { session.exercises[exerciseIndex] }

    private var knownBrands: [KnownBrand] {
        KnownBrand.list(for: exercise.name, history: history, saved: catalog.brands(for: exercise.name), unit: unit)
    }

    /// Moves what's logged on one brand of this exercise onto another: history and the running workout
    /// in the store, settings in the catalog.
    private func moveBrand(from: Brand?, to: Brand?) {
        store.moveBrand(exercise: exercise.name, from: from, to: to)
        catalog.moveBrand(for: exercise.name, from: from, to: to)
    }

    var body: some View {
        // Draws nothing for an exercise that was just removed and is animating out.
        if session.exercises.contains(where: { $0.id == exerciseID }) { content }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // The name opens the exercise page: its graph, records and past sets on this brand.
                NavigationLink(value: ExerciseRoute(name: exercise.name, brand: exercise.brand)) {
                    Text(exercise.name)
                        .textStyle(Tokens.Typography.exerciseName)
                        .foregroundStyle(palette.foreground)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.press)
                .accessibilityHint("Shows your progress on this exercise")
                Spacer()
                Menu {
                    Button("Add setting", systemImage: "plus") { addSetting() }
                    Button("Edit exercise", systemImage: "slider.horizontal.3") { editingExercise = true }
                    Button("Reorder exercises", systemImage: "arrow.up.arrow.down", action: onReorder)
                    Button("Remove exercise", systemImage: "trash", role: .destructive) {
                        if exercise.sets.contains(where: \.isDone) {
                            confirmingRemove = true
                        } else {
                            withAnimation(.standard) { session.removeExercise(at: exerciseIndex) }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(palette.foregroundMuted)
                        .frame(width: Tokens.Size.control, height: Tokens.Size.control, alignment: .trailing)
                }
                .accessibilityLabel("Exercise options")
            }

            settings
            notes

            FlowLayout(spacing: Tokens.Space.s) {
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
                    OutlinedLabel(text: exercise.brand?.display ?? "No brand", showsChevron: true, isMuted: exercise.brand == nil)
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
                        // Laid out like a set row, so when reps and holds are mixed the group's own
                        // "Reps" or "Time" sits over the column it's about.
                        HStack(spacing: Tokens.Space.s) {
                            Color.clear.frame(width: Tokens.Size.setNumberColumn, height: 1)
                            HStack(spacing: Tokens.Space.xs) {
                                Text(group.heading)
                                Image(systemName: "chevron.down")
                                    .imageScale(.small)
                                    .foregroundStyle(palette.foregroundFaint)
                            }
                            .textStyle(Tokens.Typography.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if hasMixedKinds, let first = group.setIndices.first {
                                Color.clear.frame(width: Tokens.Size.weightColumn, height: 1)
                                Text(Self.amountHeading(for: exercise.sets[first].kind))
                                    .textStyle(Tokens.Typography.label)
                                    .frame(width: Tokens.Size.amountColumn)
                                Color.clear.frame(width: Tokens.Size.rpeColumn + Tokens.Space.s + Tokens.Size.tickColumn, height: 1)
                            }
                        }
                        .foregroundStyle(palette.foregroundMuted)
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
                        SwipeToDelete(accessibilityName: exercise.sets.spokenName(at: setIndex).lowercased()) {
                            session.deleteSet(setID)
                        } content: {
                            SetRow(session: session, setID: setID, isRecord: records[setID] != nil, focus: focus)
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
            BrandSheet(exerciseName: exercise.name, known: knownBrands, current: exercise.brand) { brand, movingHistory in
                if movingHistory { moveBrand(from: exercise.brand, to: brand) }
                withAnimation(.standard) { session.changeBrand(of: exerciseIndex, to: brand, catalog: catalog) }
            }
            .environment(\.palette, palette)
        }
        .sheet(isPresented: $pickingRest) {
            RestSheet(exerciseName: exercise.name, seconds: $session.exercises[exerciseIndex].restSeconds)
                .environment(\.palette, palette)
        }
        .confirmationDialog("Remove \(exercise.name)?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove exercise", role: .destructive) {
                withAnimation(.standard) { session.removeExercise(at: exerciseIndex) }
            }
        } message: {
            Text("The sets you've ticked on it are removed too.")
        }
        .onChange(of: exercise.settings) { _, settings in
            catalog.saveSettings(settings, for: exercise.name, brand: exercise.brand)
        }
        .sheet(isPresented: $editingExercise) {
            let known = catalog.info(named: exercise.name)
            ExerciseEditor(
                editing: known ?? ExerciseInfo(name: exercise.name, equipment: .other, primaryMuscle: .chest, isCustom: true),
                brand: exercise.brand,
                setup: BrandSetup(settings: exercise.settings),
                existingNames: catalog.names,
                knownBrands: knownBrands,
                savedSetup: { [name = exercise.name] brand in catalog.setup(for: name, brand: brand) },
                workoutsUsingIt: history.count(using: exercise.name),
                onDelete: known == nil ? nil : { deleteExercise() }
            ) { edit in
                let oldBrand = exercise.brand
                catalog.save(edit.info, renamedFrom: exercise.name, brand: edit.brand, setup: edit.setup)
                store.renameExercise(from: exercise.name, to: edit.info.name)
                catalog.save(edit.otherSetups, for: edit.info.name)
                // After saving, so the settings edited here are what gets merged.
                if let move = edit.brandMove {
                    store.moveBrand(exercise: edit.info.name, from: move.from, to: move.to)
                    catalog.moveBrand(for: edit.info.name, from: move.from, to: move.to)
                }
                withAnimation(.standard) {
                    session.applyEdit(to: exerciseIndex, name: edit.info.name, settings: edit.setup.settings, renamedSettings: edit.renamedSettings)
                    // Picking another brand in the editor moves this exercise onto it.
                    if edit.brand != oldBrand { session.changeBrand(of: exerciseIndex, to: edit.brand, catalog: catalog) }
                }
            }
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

    /// Deletes this exercise from the library and prebuilt workouts. It leaves this workout too, unless
    /// you've ticked sets on it: those stay, and are saved under its name like any other history.
    private func deleteExercise() {
        let name = exercise.name
        guard catalog.delete(exerciseNamed: name) else { return }
        onDeleteExercise(name)
        if !exercise.sets.contains(where: \.isDone) {
            withAnimation(.standard) { session.removeExercise(at: exerciseIndex) }
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

    /// Settings like seat height, as one quiet line under the name: "Seat 4 · Notch 7 · Dead stop".
    /// Tapping it opens the settings up into editable rows. They're remembered for this exercise on this brand.
    @ViewBuilder private var settings: some View {
        if editingSettings {
            settingRows
        } else if !exercise.settings.isEmpty {
            Button {
                withAnimation(.standard) { editingSettings = true }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                    Text(exercise.settingsSummary)
                        .textStyle(Tokens.Typography.control)
                        .foregroundStyle(palette.foregroundMuted)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "pencil")
                        .imageScale(.small)
                        .foregroundStyle(palette.foregroundFaint)
                }
                .padding(.vertical, Tokens.Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressRow)
            .accessibilityLabel("Settings: \(exercise.settingsSummary)")
            .accessibilityHint("Edit settings")
            .padding(.top, Tokens.Space.s)
            .transition(.opacity)
        }
    }

    private func addSetting() {
        let id = withAnimation(.standard) {
            editingSettings = true
            return session.addSetting(to: exerciseIndex)
        }
        focus.wrappedValue = .settingName(id)
    }

    /// The settings opened up: one editable row each, then Add setting and Done.
    private var settingRows: some View {
        VStack(alignment: .leading, spacing: 0) {
                ForEach(exercise.settings) { setting in
                    SwipeToDelete(accessibilityName: setting.name.isEmpty ? "setting" : setting.name) {
                        session.deleteSetting(setting.id)
                    } content: {
                        HStack(spacing: Tokens.Space.m) {
                            TextField("", text: settingText(setting.id, \.name), prompt: Text("Seat height").foregroundStyle(palette.foregroundFaint))
                                .textStyle(Tokens.Typography.control)
                                .foregroundStyle(palette.foregroundMuted)
                                .focused(focus, equals: .settingName(setting.id))
                                .submitLabel(.next)
                                .onSubmit { focus.wrappedValue = .settingValue(setting.id) }
                            if setting.isTracked {
                                Image(systemName: setting.direction == .lower ? "arrow.down.right" : "arrow.up.right")
                                    .imageScale(.small)
                                    .foregroundStyle(palette.foregroundFaint)
                                    .accessibilityLabel("Counts towards your score")
                            }
                            settingValue(setting)
                        }
                        .padding(.vertical, Tokens.Space.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                HStack {
                    Button(action: addSetting) {
                        Label("Add setting", systemImage: "plus")
                            .textStyle(Tokens.Typography.control)
                            .foregroundStyle(palette.foregroundMuted)
                            .frame(minHeight: Tokens.Size.control)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressRow)
                    Spacer()
                    Button {
                        focus.wrappedValue = nil
                        withAnimation(.standard) {
                            session.removeEmptySettings()
                            editingSettings = false
                        }
                    } label: {
                        Text("Done")
                            .textStyle(Tokens.Typography.control)
                            .foregroundStyle(palette.foreground)
                            .frame(minWidth: Tokens.Size.control, minHeight: Tokens.Size.control, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressRow)
                }
            }
            .padding(.top, Tokens.Space.s)
            .transition(.opacity)
    }

    /// The value side of a setting row: Yes or No for a yes/no setting, otherwise a small cell to type in.
    @ViewBuilder private func settingValue(_ setting: ExerciseSetting) -> some View {
        if setting.kind == .yesNo {
            let isOn = setting.value == "yes"
            Button {
                settingText(setting.id, \.value).wrappedValue = isOn ? "no" : "yes"
            } label: {
                Text(isOn ? "Yes" : "No")
                    .textStyle(Tokens.Typography.control)
                    .foregroundStyle(isOn ? palette.foreground : palette.foregroundFaint)
                    .frame(width: Tokens.Size.amountColumn, height: Tokens.Size.cell - Tokens.Space.s)
                    .background(palette.surface, in: .rect(cornerRadius: Tokens.Radius.control))
                    .animation(.quick, value: isOn)
            }
            .buttonStyle(.press)
            .accessibilityLabel("\(setting.name), \(isOn ? "yes" : "no")")
        } else {
            TextField("", text: settingText(setting.id, \.value), prompt: Text("-").foregroundStyle(palette.foregroundFaint))
                .keyboardType(setting.kind == .number ? .decimalPad : .default)
                .textStyle(Tokens.Typography.control)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.foreground)
                .focused(focus, equals: .settingValue(setting.id))
                .frame(width: Tokens.Size.amountColumn, height: Tokens.Size.cell - Tokens.Space.s)
                .background(palette.surface, in: .rect(cornerRadius: Tokens.Radius.control))
        }
    }

    /// A setting's name or value looked up by id, so a row deleted mid-edit never leaves a binding to a missing index.
    private func settingText(_ id: UUID, _ keyPath: WritableKeyPath<ExerciseSetting, String>) -> Binding<String> {
        Binding {
            session.exercises[exerciseIndex].settings.first { $0.id == id }?[keyPath: keyPath] ?? ""
        } set: { text in
            if let index = session.exercises[exerciseIndex].settings.firstIndex(where: { $0.id == id }) {
                session.exercises[exerciseIndex].settings[index][keyPath: keyPath] = text
            }
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

    /// Whether this exercise has both rep sets and holds, so one column heading can't name the amount for all.
    private var hasMixedKinds: Bool {
        Set(exercise.sets.map(\.kind)).count > 1
    }

    static func amountHeading(for kind: SetKind) -> String {
        kind == .hold ? "Time" : "Reps"
    }

    private var columnHeadings: some View {
        HStack(spacing: Tokens.Space.s) {
            Color.clear.frame(width: Tokens.Size.setNumberColumn, height: 1)
            Text("Previous").frame(maxWidth: .infinity, alignment: .leading)
            Text(unit.rawValue).frame(width: Tokens.Size.weightColumn)
            // With reps and holds mixed, each group's heading names this column instead.
            Text(hasMixedKinds ? "" : Self.amountHeading(for: exercise.sets.first?.kind ?? .reps)).frame(width: Tokens.Size.amountColumn)
            Text("RPE").frame(width: Tokens.Size.rpeColumn)
            Color.clear.frame(width: Tokens.Size.tickColumn, height: 1)
        }
        .textStyle(Tokens.Typography.label)
        .foregroundStyle(palette.foregroundMuted)
    }
}

/// One set: its number or type letter, what you did last time, weight, reps or time, RPE and the tick box.
/// Tapping the number opens a menu to mark the set as a warm-up, a drop set or a set to failure.
private struct SetRow: View {
    @Environment(\.palette) private var palette
    @AppStorage(WeightUnit.storageKey) private var unit: WeightUnit = .kg
    @Bindable var session: WorkoutSession
    let setID: UUID
    /// Whether this ticked set beat your best for its shape, shown as a small arrow by its number.
    var isRecord = false
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
        let sets = session.exercises[e].sets
        let mark = sets.mark(at: i)
        let spoken = sets.spokenName(at: i)
        return HStack(spacing: Tokens.Space.s) {
            Menu {
                ForEach(SetType.allCases, id: \.self) { type in
                    Button {
                        withAnimation(.standard) { session.changeType(of: setID, to: type) }
                    } label: {
                        if set.type == type {
                            Label(type.name, systemImage: "checkmark")
                        } else {
                            Text(type.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 1) {
                    Text(mark)
                        .contentTransition(.numericText())
                    if isRecord {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .foregroundStyle(isRecord ? palette.accent : set.type == .normal ? palette.foregroundFaint : palette.foregroundMuted)
                .animation(.standard, value: isRecord)
                .animation(.standard, value: mark)
                .frame(width: Tokens.Size.setNumberColumn, height: Tokens.Size.setRow, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(isRecord ? "\(spoken), record" : spoken)
            .accessibilityHint("Changes the set's type")
            Text(set.previous?.text(in: unit) ?? "-")
                .foregroundStyle(palette.foregroundMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            WeightEntry(kilograms: $session.exercises[e].sets[i].weight) { text in
                NumberCell(text: text, isDone: set.isDone, accessibilityName: "Weight in \(unit.name)", focus: focus, cell: .weight(set.id))
            }
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

/// Puts the exercises in a running workout in a new order: drag each one by its handle.
private struct ReorderExercises: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: WorkoutSession

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Reorder exercises")
                    .textStyle(Tokens.Typography.title)
                    .foregroundStyle(palette.foreground)
                Spacer()
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.top, Tokens.Space.xxl)
            .padding(.bottom, Tokens.Space.l)

            List {
                ForEach(session.exercises) { exercise in
                    HStack {
                        Text(exercise.name)
                            .textStyle(Tokens.Typography.body)
                            .foregroundStyle(palette.foreground)
                        Spacer()
                        Text("\(exercise.sets.count) sets")
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                    }
                    .frame(minHeight: Tokens.Size.control)
                    .listRowBackground(palette.background)
                    .listRowSeparatorTint(palette.borderSoft)
                }
                .onMove { session.moveExercises(from: $0, to: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))

            PrimaryButton(title: "Done") { dismiss() }
                .padding(.horizontal, Tokens.Space.xxl)
                .padding(.vertical, Tokens.Space.l)
        }
        .background(palette.background)
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.background)
        .sensoryFeedback(.selection, trigger: session.exercises.map(\.id))
    }
}

#Preview("Light") {
    WorkoutScreen(session: .sample())
        .environment(WorkoutStore())
        .environment(ExerciseCatalog())
        .environment(WorkoutStore())
        .environment(MediaStore())
        .environment(\.palette, .light)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    WorkoutScreen(session: .sample())
        .environment(WorkoutStore())
        .environment(ExerciseCatalog())
        .environment(WorkoutStore())
        .environment(MediaStore())
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
