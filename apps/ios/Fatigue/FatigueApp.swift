import SwiftUI

@main
struct FatigueApp: App {
    @State private var auth = AuthStore()
    @State private var social = SocialStore()
    @State private var workouts: WorkoutStore
    @State private var catalog: ExerciseCatalog
    @State private var sync: SyncEngine

    init() {
        FontRegistry.registerBundledFonts()
        RestNotifications.shared.becomeDelegate()
        // Everything is saved in SQLite on the phone. If the file can't be opened, the app falls
        // back to a database in memory so it still opens, but nothing is kept after it closes.
        let database: AppDatabase?
        do {
            database = try AppDatabase.onDisk()
        } catch {
            #if DEBUG
            print("Couldn't open the database, keeping everything in memory: \(error)")
            #endif
            database = try? AppDatabase.inMemory()
        }
        let workouts = database.map { WorkoutStore(database: $0) } ?? WorkoutStore()
        _workouts = State(initialValue: workouts)
        let catalog = database.map { ExerciseCatalog.load(from: $0) } ?? ExerciseCatalog()
        _catalog = State(initialValue: catalog)
        // Backs up to the API and brings down what other phones changed. A pull reloads what the screens show.
        let sync = SyncEngine(database: database)
        sync.onPulled = { [workouts, catalog] outcome in
            workouts.reloadFromDatabase()
            catalog.reloadFromDatabase()
            if let unit = outcome.weightUnit { UserDefaults.standard.set(unit, forKey: WeightUnit.storageKey) }
        }
        _sync = State(initialValue: sync)
        // Outside the app the rest timer is followed by the "Rest done" notification and the Live Activity:
        // ticking a set starts them, ±15 moves them, and skipping, finishing or deleting the workout ends them.
        workouts.onRestChange = { rest, session in
            RestNotifications.shared.update(for: rest)
            RestLiveActivity.shared.update(for: rest, workoutTitle: session.title)
        }
        // Skip and +15 s on the Live Activity run here, in the app, on the same timer.
        RestIntentHandler.perform = { [workouts] action in workouts.perform(action) }
        // A Live Activity can outlive the app. Line it up with the timer that came back, or take it down.
        RestLiveActivity.shared.update(for: workouts.active?.rest, workoutTitle: workouts.active?.title ?? "")
    }

    var body: some Scene {
        WindowGroup {
            ThemeProvider {
                RootView()
            }
            .environment(auth)
            .environment(social)
            .environment(workouts)
            .environment(workouts.media)
            .environment(catalog)
            .environment(sync)
            // The links in reset and verification emails end up here, as fatigue:// URLs.
            .onOpenURL { url in auth.open(url) }
        }
    }
}

/// Sign in first, then home. Crossfades between the two so signing in or out never jumps.
struct RootView: View {
    @Environment(\.palette) private var palette
    @Environment(AuthStore.self) private var auth
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        @Bindable var auth = auth
        ZStack {
            palette.background.ignoresSafeArea()
            switch auth.state {
            case .loading:
                EmptyView()
            case .signedOut:
                SignInScreen().transition(.opacity)
            case .signedIn:
                MainScreen().transition(.opacity)
            }
        }
        .animation(.standard, value: auth.state)
        // Sync follows whoever is signed in, and stops while nobody is.
        .onChange(of: auth.account?.id, initial: true) { _, id in sync.account = id }
        .sheet(item: $auth.passwordReset) { _ in
            ResetPasswordScreen()
                .environment(\.palette, palette)
        }
        .task {
            sync.startWatching()
            await auth.restore()
            await signInForScreenshots()
        }
    }

    /// Debug builds can sign in on launch with `-signIn email password`, for screenshots against the local API.
    private func signInForScreenshots() async {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard auth.account == nil, let index = args.firstIndex(of: "-signIn"), args.count > index + 2 else { return }
        try? await auth.signIn(email: args[index + 1], password: args[index + 2])
        #endif
    }
}
