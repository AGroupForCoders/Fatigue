import SwiftUI

/// Placeholder first screen. It exists so the app has somewhere to start a workout from.
struct HomeScreen: View {
    @Environment(\.palette) private var palette
    /// Launch with `-openProfile` to open the profile straight away, for screenshots.
    @State private var showingProfile = ProcessInfo.processInfo.arguments.contains("-openProfile")
    /// Launch with `-openWorkout` to go straight to the workout screen, for screenshots.
    @State private var showingWorkout = ProcessInfo.processInfo.arguments.contains("-openWorkout")

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack {
                Text("Fatigue")
                    .textStyle(Tokens.Typography.title)
                    .foregroundStyle(palette.foreground)
                Spacer()
                Button { showingProfile = true } label: {
                    Image(systemName: "person")
                        .foregroundStyle(palette.foreground)
                        .frame(width: Tokens.Size.control, height: Tokens.Size.control)
                        .overlay(Circle().strokeBorder(palette.borderControl, lineWidth: Tokens.Size.line))
                }
                .buttonStyle(.press)
                .accessibilityLabel("Profile")
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
        .sheet(isPresented: $showingProfile) {
            ProfileScreen()
                .environment(\.palette, palette)
                .presentationBackground(palette.background)
        }
        .fullScreenCover(isPresented: $showingWorkout) {
            ThemeProvider {
                WorkoutScreen(session: .sample())
            }
        }
    }
}

#Preview {
    ThemeProvider { HomeScreen() }
        .environment(AuthStore())
}
