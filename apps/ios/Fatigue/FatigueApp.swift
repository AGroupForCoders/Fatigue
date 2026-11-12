import SwiftUI

@main
struct FatigueApp: App {
    @State private var auth = AuthStore()

    init() {
        FontRegistry.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ThemeProvider {
                RootView()
            }
            .environment(auth)
        }
    }
}

/// Sign in first, then home. Crossfades between the two so signing in or out never jumps.
struct RootView: View {
    @Environment(\.palette) private var palette
    @Environment(AuthStore.self) private var auth

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            switch auth.state {
            case .loading:
                EmptyView()
            case .signedOut:
                SignInScreen().transition(.opacity)
            case .signedIn:
                HomeScreen().transition(.opacity)
            }
        }
        .animation(.standard, value: auth.state)
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
