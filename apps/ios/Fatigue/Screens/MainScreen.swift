import SwiftUI

/// The signed-in app: a tab for each area, the bottom nav, and the running workout's bar above it.
struct MainScreen: View {
    enum Tab: CaseIterable {
        case workout, feed, stats, profile

        var title: String {
            switch self {
            case .workout: "Workout"
            case .feed: "Feed"
            case .stats: "Stats"
            case .profile: "Profile"
            }
        }

        var icon: String {
            switch self {
            case .workout: "dumbbell"
            case .feed: "person.2"
            case .stats: "chart.bar"
            case .profile: "person"
            }
        }
    }

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(WorkoutStore.self) private var store
    @Environment(SocialStore.self) private var social
    @AppStorage(WeightUnit.storageKey) private var unit: WeightUnit = .kg
    @Environment(\.scenePhase) private var scenePhase
    /// Launch with `-openFeed`, `-openProfile` or `-openStats` to start on that tab, for screenshots.
    @State private var tab: Tab = {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-openFeed") ? .feed : args.contains("-openProfile") ? .profile : args.contains("-openStats") ? .stats : .workout
    }()

    var body: some View {
        @Bindable var store = store
        ZStack {
            // Every tab stays alive, so switching keeps each one's scroll position.
            WorkoutsScreen().opacity(tab == .workout ? 1 : 0).allowsHitTesting(tab == .workout)
            FeedScreen(openProfile: { tab = .profile }).opacity(tab == .feed ? 1 : 0).allowsHitTesting(tab == .feed)
            StatsScreen().opacity(tab == .stats ? 1 : 0).allowsHitTesting(tab == .stats)
            ProfileScreen().opacity(tab == .profile ? 1 : 0).allowsHitTesting(tab == .profile)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let active = store.active {
                    ActiveWorkoutBar(session: active, onOpen: { store.isShowingActive = true }, onDiscard: store.discard)
                        .transition(.bottomPanel(reduceMotion: reduceMotion))
                }
                BottomNav(selection: $tab)
            }
            .animation(.standard, value: store.active == nil)
        }
        .background(palette.background)
        .overlay { GrainOverlay() }
        .fullScreenCover(isPresented: $store.isShowingActive) {
            if let active = store.active {
                ThemeProvider {
                    WorkoutScreen(
                        session: active,
                        history: store.history,
                        onMinimise: { store.isShowingActive = false },
                        routine: store.activeRoutine,
                        onFinish: { details in
                            let before = store.history
                            withAnimation(.standard) {
                                store.finish(title: details.title, description: details.description, gym: details.gym, unticked: details.unticked, updateRoutine: details.updateRoutine)
                            }
                            share(details.share, before: before)
                        },
                        onDeleteExercise: { store.removeFromRoutines(exerciseNamed: $0) }
                    )
                }
            }
        }
        .onAppear(perform: openForScreenshots)
        .task(id: store.active?.id) { await store.autosaveActive() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.saveActive() }
            // Shares made offline go out when the app comes back.
            if phase == .active { Task { await social.sendPending() } }
        }
    }

    /// Shares the workout just finished, if you chose to on the finish summary. `before` is history before
    /// it, for the records it beat. Waits for a connection if there isn't one.
    private func share(_ visibility: PostVisibility?, before: [FinishedWorkout]) {
        guard let visibility, let finished = store.history.first, finished.id != before.first?.id else { return }
        let records = ExerciseStats.beaten(by: finished, history: before, splitBy: { ExerciseSplit.remembered(for: $0) }, in: unit)
        // Every photo and video on it goes too, the same as the share sheet starts with all of them ticked.
        let media = store.media.media(for: finished.id)
        Task { await social.share(finished, records: records, visibility: visibility, media: media) }
    }

    /// Debug builds start the leg day workout on launch with `-openWorkout`, or start it minimised
    /// into the bar with `-minimisedWorkout`, for screenshots.
    private func openForScreenshots() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard store.active == nil, let first = store.routines.first else { return }
        if args.contains("-openWorkout") { store.start(first) }
        if args.contains("-minimisedWorkout") {
            store.start(first)
            store.isShowingActive = false
        }
        #endif
    }
}

/// The app's bottom navigation: a hairline, then one icon and label per tab.
struct BottomNav: View {
    @Environment(\.palette) private var palette
    @Binding var selection: MainScreen.Tab

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                ForEach(MainScreen.Tab.allCases, id: \.self) { tab in
                    let isSelected = tab == selection
                    Button { selection = tab } label: {
                        VStack(spacing: Tokens.Space.xs) {
                            Image(systemName: tab.icon)
                                .symbolVariant(isSelected ? .fill : .none)
                                .frame(height: Tokens.Space.xxl)
                            Text(tab.title)
                                .textStyle(Tokens.Typography.label)
                        }
                        .foregroundStyle(isSelected ? palette.foreground : palette.foregroundFaint)
                        .animation(.quick, value: isSelected)
                        .frame(maxWidth: .infinity, minHeight: Tokens.Size.primaryButton)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.press)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.top, Tokens.Space.s)
        }
        .background(palette.background.ignoresSafeArea(edges: .bottom))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// The running workout, sitting above the bottom nav while you're elsewhere in the app:
/// its name, how long it's been going and sets done. Tap to go back to it, or delete it.
/// It also ends the rest timer when its time is up, with the same haptic as the workout screen,
/// so a rest that ends while the workout is minimised is still felt.
struct ActiveWorkoutBar: View {
    @Environment(\.palette) private var palette
    let session: WorkoutSession
    let onOpen: () -> Void
    let onDiscard: () -> Void
    @State private var confirmingDiscard = false
    /// Counts rests that ended from here, so each one gets its haptic.
    @State private var restsFinished = 0

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: Tokens.Space.s) {
                Button(action: onOpen) {
                    HStack {
                        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                            Text(session.title)
                                .textStyle(Tokens.Typography.body)
                                .foregroundStyle(palette.foreground)
                            TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                                Text("\(WorkoutScreen.clock(context.date.timeIntervalSince(session.startedAt)))  ·  \(session.doneCount) of \(session.setCount) sets")
                                    .textStyle(Tokens.Typography.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(palette.foregroundMuted)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.up")
                            .imageScale(.small)
                            .foregroundStyle(palette.foregroundMuted)
                    }
                    .frame(maxWidth: .infinity, minHeight: Tokens.Size.control)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressRow)
                .accessibilityHint("Opens the workout")

                Button { confirmingDiscard = true } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(palette.accent)
                        .frame(width: Tokens.Size.control, height: Tokens.Size.control)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.press)
                .accessibilityLabel("Delete workout")
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.vertical, Tokens.Space.m)
        }
        .background(palette.surface)
        // The workout screen does the same while it's open. Whichever clears the timer first gets the
        // haptic, so it only ever plays once.
        .task(id: session.rest?.endsAt) {
            guard let endsAt = session.rest?.endsAt else { return }
            try? await Task.sleep(for: .seconds(max(0, endsAt.timeIntervalSinceNow)))
            if !Task.isCancelled, session.finishRestIfDue() { restsFinished += 1 }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: restsFinished)
        .confirmationDialog("Delete \(session.title)?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Delete workout", role: .destructive, action: onDiscard)
        } message: {
            Text("The sets you've logged in this workout are thrown away.")
        }
    }
}
