import SwiftUI

/// The theme someone picked and a way to change it, the same shape as `useTheme()` on antga.dev.
/// Read it with `@Environment(\.theme)`.
struct ThemeState {
    /// The saved choice: `Theme.system` or the id of a `Palette`.
    var theme: String
    var setTheme: (String) -> Void
}

/// Where the choice is saved, and how a saved choice becomes a palette.
nonisolated enum Theme {
    /// Follow the phone's light or dark setting.
    static let system = "system"

    /// Every choice the app can offer: system first, then each theme in tokens.json.
    static var choices: [String] { [system] + Palette.all.map(\.id) }

    /// The palette to draw for a saved choice.
    ///
    /// - A theme this app has is drawn as it is.
    /// - System, or a choice the app doesn't recognise (for example a theme removed in a later
    ///   version), uses the default light or dark theme to match the phone.
    static func palette(for saved: String?, systemScheme: ColorScheme) -> Palette {
        if let saved, let palette = Palette.all.first(where: { $0.id == saved }) {
            return palette
        }
        return systemScheme == .dark ? .defaultDark : .defaultLight
    }

    /// Whether the app should force light or dark, or leave it to the phone.
    static func forcedScheme(for saved: String?) -> ColorScheme? {
        guard let saved, saved != system else { return nil }
        return Palette.all.first(where: { $0.id == saved })?.appearance
    }
}

extension EnvironmentValues {
    /// The colours to draw with. Views read colours from here and never name a theme,
    /// so a theme added to tokens.json works everywhere without changing any view.
    @Entry var palette: Palette = .defaultLight
    @Entry var theme = ThemeState(theme: Theme.system, setTheme: { _ in })
}

/// Picks the theme for everything inside it and hands it down through the environment.
///
/// Wrap the app in one of these, once. The choice is saved between launches. It also sets
/// the light or dark appearance to match the theme, so the keyboard and system menus fit.
struct ThemeProvider<Content: View>: View {
    @AppStorage("theme") private var saved = Theme.system
    @Environment(\.colorScheme) private var systemScheme
    @ViewBuilder var content: Content

    var body: some View {
        let palette = Theme.palette(for: saved, systemScheme: systemScheme)
        content
            .environment(\.palette, palette)
            .environment(\.theme, ThemeState(theme: saved, setTheme: { saved = $0 }))
            .tint(palette.foreground)
            .preferredColorScheme(Theme.forcedScheme(for: saved))
    }
}

/// A menu for picking a theme, like `ThemeMenu` on antga.dev.
struct ThemeMenu: View {
    @Environment(\.theme) private var theme
    @Environment(\.palette) private var palette

    var body: some View {
        Menu {
            Picker("Theme", selection: Binding(get: { theme.theme }, set: theme.setTheme)) {
                ForEach(Theme.choices, id: \.self) { choice in
                    Text(choice.capitalized).tag(choice)
                }
            }
        } label: {
            Image(systemName: "circle.lefthalf.filled")
                .foregroundStyle(palette.foregroundMuted)
                .frame(width: Tokens.Size.control, height: Tokens.Size.control)
        }
        .accessibilityLabel("Theme")
    }
}
