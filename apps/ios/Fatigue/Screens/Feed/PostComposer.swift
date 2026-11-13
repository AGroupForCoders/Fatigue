import SwiftUI

/// Shares a workout from history, or shares it again: a caption and who sees it.
struct PostComposer: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(SocialStore.self) private var social
    @AppStorage(WeightUnit.storageKey) private var unit: WeightUnit = .kg
    let workout: FinishedWorkout
    /// Workouts finished before this one, for the records it beat.
    let earlier: [FinishedWorkout]

    @State private var caption = ""
    @State private var visibility: PostVisibility
    @State private var sharing = false
    @State private var queued = false

    init(workout: FinishedWorkout, earlier: [FinishedWorkout], defaultVisibility: PostVisibility) {
        self.workout = workout
        self.earlier = earlier
        _visibility = State(initialValue: defaultVisibility)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xxl) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    Text(social.isShared(workout.id) ? "Share again" : "Share workout")
                        .textStyle(Tokens.Typography.title)
                        .foregroundStyle(palette.foreground)
                    Text(social.isShared(workout.id) ? "Replaces the shared copy with the workout as it is now." : workout.title)
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.foregroundMuted)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(palette.foreground)
                        .frame(width: Tokens.Size.control, height: Tokens.Size.control)
                }
                .buttonStyle(.press)
                .accessibilityLabel("Close")
            }

            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text("Caption")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
                TextField("", text: $caption, prompt: Text("Say something about it").foregroundStyle(palette.foregroundFaint), axis: .vertical)
                    .textStyle(Tokens.Typography.body)
                    .foregroundStyle(palette.foreground)
                    .lineLimit(2...8)
                    .onChange(of: caption) { _, text in if text.count > 2000 { caption = String(text.prefix(2000)) } }
                Hairline()
            }

            VisibilityPicker(visibility: $visibility)

            if queued {
                Text("You're offline. It shares once you're back online.")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
            }

            Spacer()
            PrimaryButton(title: sharing ? "Sharing" : "Share") {
                guard !sharing else { return }
                sharing = true
                let records = ExerciseStats.beaten(by: workout, history: earlier, splitBy: { ExerciseSplit.remembered(for: $0) }, in: unit)
                Task {
                    let sent = await social.share(workout, records: records, visibility: visibility, caption: caption)
                    sharing = false
                    if sent { dismiss() } else { withAnimation(.quick) { queued = true } }
                }
            }
            .disabled(sharing)
        }
        .padding(Tokens.Space.xxl)
        .background(palette.background)
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.background)
    }
}

/// Who sees a shared workout, as a caption and an outlined menu.
struct VisibilityPicker: View {
    @Environment(\.palette) private var palette
    @Binding var visibility: PostVisibility
    var title = "Who sees it"

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text(title)
                .textStyle(Tokens.Typography.caption)
                .foregroundStyle(palette.foregroundMuted)
            Menu {
                Picker(title, selection: $visibility) {
                    ForEach(PostVisibility.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } label: {
                OutlinedLabel(systemImage: visibility.systemImage, text: visibility.title, showsChevron: true)
            }
        }
    }
}
