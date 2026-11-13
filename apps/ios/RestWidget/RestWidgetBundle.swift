import SwiftUI
import WidgetKit

/// The widget extension: only the rest Live Activity for now.
@main
struct RestWidgetBundle: WidgetBundle {
    init() {
        // Inter ships inside the extension too (see the Fonts build membership), so the activity
        // uses the app's typography. Missing fonts fall back to the system font.
        FontRegistry.registerBundledFonts()
    }

    var body: some Widget {
        RestWidgetLiveActivity()
    }
}
