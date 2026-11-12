import CoreText
import SwiftUI

/// A font and its letter spacing. Every value in `Tokens.Typography` is one of these.
nonisolated struct TextStyle: Sendable {
    let fontName: String
    let size: CGFloat
    let tracking: CGFloat

    var font: Font { .custom(fontName, size: size) }
}

extension View {
    /// Sets the font and letter spacing from a text style token.
    func textStyle(_ style: TextStyle) -> some View {
        font(style.font).tracking(style.tracking)
    }
}

enum FontRegistry {
    /// Makes the fonts bundled with the app, such as Inter, available to `Font.custom`.
    /// Called once at launch. If a font is missing, text falls back to the system font.
    static func registerBundledFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
