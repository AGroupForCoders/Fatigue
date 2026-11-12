import Testing
@testable import Fatigue

/// Checks that the generated tokens are wired into the app.
/// The real point of this file is to prove the test target builds and runs,
/// so CI has something to run until there is logic worth testing.
struct TokensTests {
    @Test func controlsAreLessRoundedThanPanels() {
        #expect(Tokens.Radius.control < Tokens.Radius.panel)
    }

    @Test func spacingScaleIncreases() {
        let scale = [
            Tokens.Space.xs, Tokens.Space.s, Tokens.Space.m,
            Tokens.Space.l, Tokens.Space.xl, Tokens.Space.xxl,
        ]
        #expect(scale == scale.sorted())
    }
}
