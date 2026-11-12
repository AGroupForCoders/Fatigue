import SwiftUI

@main
struct FatigueApp: App {
    init() {
        FontRegistry.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ThemeProvider {
                HomeScreen()
            }
        }
    }
}
