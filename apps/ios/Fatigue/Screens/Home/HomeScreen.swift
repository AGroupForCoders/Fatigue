import SwiftUI

/// Placeholder first screen. It exists so the app has something to launch into
/// while the workout screen is built.
struct HomeScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text("Fatigue")
                .font(Tokens.Typography.title)
                .foregroundStyle(Tokens.Colors.text)
            Text("No workout running")
                .font(Tokens.Typography.body)
                .foregroundStyle(Tokens.Colors.textMuted)

            Spacer()

            PrimaryButton(title: "Start workout") {}
        }
        .padding(.horizontal, Tokens.Space.xl)
        .padding(.top, Tokens.Space.l)
        .padding(.bottom, Tokens.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.Colors.background)
    }
}

#Preview {
    HomeScreen()
        .preferredColorScheme(.dark)
}
