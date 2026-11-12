import SwiftUI

@main
struct FatigueApp: App {
    var body: some Scene {
        WindowGroup {
            HomeScreen()
                .preferredColorScheme(.dark)
                .tint(Tokens.Colors.accent)
        }
    }
}
