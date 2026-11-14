import SwiftUI
import Testing
import UIKit
@testable import Fatigue

@MainActor
/// Puts the workout screen in the test host's window and deletes sets while it's on screen. Every box in a set
/// row redraws on its own, so one could read its set by a position that the delete had just removed.
struct WorkoutScreenRenderTests {
    @Test func deletingSetsWhileOnScreenDoesNotCrash() async throws {
        let session = WorkoutSession.sample()
        let store = WorkoutStore(history: [])
        let screen = ThemeProvider {
            WorkoutScreen(session: session)
                .environment(ExerciseCatalog())
                .environment(store)
        }
        let window = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first)
        window.rootViewController = UIHostingController(rootView: screen)
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(500))
        for _ in 0..<6 {
            guard let exercise = session.exercises.first(where: { !$0.sets.isEmpty }), let set = exercise.sets.first else { break }
            withAnimation(.default) { session.deleteSet(set.id) }
            try await Task.sleep(for: .milliseconds(400))
        }
        #expect(session.exercises.flatMap(\.sets).count < WorkoutSession.sample().exercises.flatMap(\.sets).count)
    }
}
