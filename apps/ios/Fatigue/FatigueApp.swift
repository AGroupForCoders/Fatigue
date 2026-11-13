import SwiftUI

@main
struct FatigueApp: App {
    @State private var auth = AuthStore()
    @State private var workouts: WorkoutStore
    @State private var catalog: ExerciseCatalog

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
        if let database {
            _workouts = State(initialValue: WorkoutStore(database: database))
            _catalog = State(initialValue: ExerciseCatalog.load(from: database))
        } else {
            _workouts = State(initialValue: WorkoutStore())
            _catalog = State(initialValue: ExerciseCatalog())
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
            // The links in reset and verification emails end up here, as fatigue:// URLs.
            .onOpenURL { url in auth.open(url) }
        }
    }
}

/// Sign in first, then home. Crossfades between the two so signing in or out never jumps.
struct RootView: View {
    @Environment(\.palette) private var palette
    @Environment(AuthStore.self) private var auth

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
        .sheet(item: $auth.passwordReset) { _ in
            ResetPasswordScreen()
                .environment(\.palette, palette)
        }
        .task {
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
