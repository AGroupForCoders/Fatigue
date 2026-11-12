import SwiftUI

/// Placeholder first screen. It exists so the app has somewhere to start a workout from.
struct HomeScreen: View {
    @Environment(\.palette) private var palette
    /// Launch with `-openWorkout` to go straight to the workout screen, for screenshots.
    @State private var showingWorkout = ProcessInfo.processInfo.arguments.contains("-openWorkout")

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack {
                Text("Fatigue")
                    .textStyle(Tokens.Typography.title)
                    .foregroundStyle(palette.foreground)
                Spacer()
                ThemeMenu()
            }
            Text("No workout running")
                .textStyle(Tokens.Typography.body)
                .foregroundStyle(palette.foregroundMuted)

            Spacer()

            PrimaryButton(title: "Start workout") { showingWorkout = true }
        }
        .padding(.horizontal, Tokens.Space.xxl)
        .padding(.top, Tokens.Space.l)
        .padding(.bottom, Tokens.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.background)
        .overlay { GrainOverlay() }
        .fullScreenCover(isPresented: $showingWorkout) {
            ThemeProvider {
                WorkoutScreen(session: .sample())
            }
        }
    }
}

#Preview {
    ThemeProvider { HomeScreen() }
}
