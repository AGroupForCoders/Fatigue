import SwiftUI

/// Shown after a Hevy import: how many workouts came in, how many were already there,
/// and the Hevy exercises that matched nothing and are now custom exercises.
struct HevyImportResultSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let result: HevyImportResult

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Imported from Hevy")
                        .textStyle(Tokens.Typography.title)
                        .foregroundStyle(palette.foreground)
                        .padding(.top, Tokens.Space.xxl)
                    Text(summary)
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.foregroundMuted)
                        .padding(.top, Tokens.Space.s)

                    if !result.newExercises.isEmpty {
                        Text("New exercises")
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                            .padding(.top, Tokens.Space.xxxl)
                            .padding(.bottom, Tokens.Space.s)
                        Text("These didn't match a built-in exercise, so they were added as custom exercises with a guessed muscle. You can fix them from the Exercises tab.")
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                            .padding(.bottom, Tokens.Space.m)
                        Hairline()
                        ForEach(result.newExercises, id: \.self) { name in
                            Text(name)
                                .textStyle(Tokens.Typography.body)
                                .foregroundStyle(palette.foreground)
                                .frame(maxWidth: .infinity, minHeight: Tokens.Size.setRow - Tokens.Space.s, alignment: .leading)
                            Hairline(soft: true)
                        }
                    }
                }
                .padding(.horizontal, Tokens.Space.xxl)
            }
            PrimaryButton(title: "Done") { dismiss() }
                .padding(.horizontal, Tokens.Space.xxl)
                .padding(.vertical, Tokens.Space.l)
        }
        .background(palette.background)
        .presentationDetents([.large])
        .presentationBackground(palette.background)
    }

    private var summary: String {
        var parts: [String] = []
        parts.append(result.imported == 1 ? "1 workout added to your history." : "\(result.imported) workouts added to your history.")
        if result.alreadyThere > 0 {
            parts.append(result.alreadyThere == 1 ? "1 was already there and was skipped." : "\(result.alreadyThere) were already there and were skipped.")
        }
        return parts.joined(separator: " ")
    }
}
