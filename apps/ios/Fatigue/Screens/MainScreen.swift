import SwiftUI

/// The signed-in app: a tab for each area, the bottom nav, and the running workout's bar above it.
struct MainScreen: View {
    enum Tab: CaseIterable {
        case workout, profile

        var title: String { self == .workout ? "Workout" : "Profile" }
        var icon: String { self == .workout ? "dumbbell" : "person" }
    }

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(WorkoutStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    /// Launch with `-openProfile` to start on the Profile tab, for screenshots.
    @State private var tab: Tab = ProcessInfo.processInfo.arguments.contains("-openProfile") ? .profile : .workout

    var body: some View {
        @Bindable var store = store
        ZStack {
            // Both tabs stay alive, so switching keeps each one's scroll position.
            WorkoutsScreen().opacity(tab == .workout ? 1 : 0).allowsHitTesting(tab == .workout)
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
                        onMinimise: { store.isShowingActive = false },
                        routine: store.activeRoutine,
                        onFinish: { details in
                            withAnimation(.standard) {
                                store.finish(title: details.title, description: details.description, unticked: details.unticked, updateRoutine: details.updateRoutine)
                            }
                        }
                    )
                }
            }
        }
        .onAppear(perform: openForScreenshots)
        .task(id: store.active?.id) { await store.autosaveActive() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.saveActive() }
        }
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
struct ActiveWorkoutBar: View {
    @Environment(\.palette) private var palette
    let session: WorkoutSession
    let onOpen: () -> Void
    let onDiscard: () -> Void
    @State private var confirmingDiscard = false

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
        .confirmationDialog("Delete \(session.title)?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Delete workout", role: .destructive, action: onDiscard)
        } message: {
            Text("The sets you've logged in this workout are thrown away.")
        }
    }
}
