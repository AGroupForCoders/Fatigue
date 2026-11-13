import SwiftUI

@main
struct FatigueApp: App {
    @State private var auth: AuthStore
    @State private var workouts: WorkoutStore
    @State private var catalog: ExerciseCatalog
    @State private var sync: SyncStore

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
        let auth = AuthStore()
        _auth = State(initialValue: auth)
        if let database {
            let workouts = WorkoutStore(database: database)
            let catalog = ExerciseCatalog.load(from: database)
            let sync = SyncStore(database: database, token: { auth.sessionToken }, accountId: { auth.account?.id })
            // Every local save asks for a sync a moment later, so another phone is seconds behind, not a workout.
            workouts.onPersist = { sync.requestSync(.localChange) }
            catalog.onPersist = { sync.requestSync(.localChange) }
            sync.onApplied = {
                workouts.reload()
                catalog.reload()
            }
            _workouts = State(initialValue: workouts)
            _catalog = State(initialValue: catalog)
            _sync = State(initialValue: sync)
        } else {
            _workouts = State(initialValue: WorkoutStore())
            _catalog = State(initialValue: ExerciseCatalog())
            _sync = State(initialValue: SyncStore.unavailable)
        }
    }

    var body: some Scene {
        WindowGroup {
            ThemeProvider {
                RootView()
            }
            .environment(auth)
            .environment(workouts)
            .environment(catalog)
            .environment(sync)
        }
    }
}

/// Sign in first, then home. Crossfades between the two so signing in or out never jumps.
struct RootView: View {
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AuthStore.self) private var auth
    @Environment(SyncStore.self) private var sync

    var body: some View {
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
        .task {
            await auth.restore()
            await signInForScreenshots()
        }
        // Signing in starts the first sync (and clears another account's data first); signing out stops it.
        .onChange(of: auth.account?.id) { _, _ in sync.accountChanged() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { sync.requestSync(.foreground) }
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
