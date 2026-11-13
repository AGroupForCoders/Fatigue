import SwiftUI

/// Opens a shared workout's page.
struct PostRoute: Hashable {
    let post: Post
}

/// Opens someone's profile and their shared workouts.
struct PersonRoute: Hashable {
    let userId: String
    let handle: String
    let name: String
}

extension View {
    /// Lets a navigation stack push post pages and people's profiles.
    func socialPages() -> some View {
        navigationDestination(for: PostRoute.self) { route in PostScreen(post: route.post) }
            .navigationDestination(for: PersonRoute.self) { route in PersonScreen(route: route) }
    }
}

/// A shared workout in a list: who shared it and when, its name and caption, a summary line,
/// the first few exercises and any records. Tapping it opens the full workout.
struct PostCard: View {
    @Environment(\.palette) private var palette
    @AppStorage(WeightUnit.storageKey) private var unit: WeightUnit = .kg
    let post: Post
    /// Off on someone's own profile, where every post is theirs.
    var showsAuthor = true

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            if showsAuthor { PostAuthorLine(post: post) }
            NavigationLink(value: PostRoute(post: post)) {
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(post.snapshot?.title ?? "Workout")
                            .textStyle(Tokens.Typography.exerciseName)
                            .foregroundStyle(palette.foreground)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Spacer()
                        if !showsAuthor { PostWhen(post: post) }
                    }
                    if let caption = post.caption {
                        Text(caption)
                            .textStyle(Tokens.Typography.body)
                            .foregroundStyle(palette.foreground)
                            .multilineTextAlignment(.leading)
                            .lineLimit(4)
                    }
                    if let snapshot = post.snapshot {
                        Text(PostScreen.summary(snapshot, unit: unit))
                            .textStyle(Tokens.Typography.control)
                            .monospacedDigit()
                            .foregroundStyle(palette.foregroundMuted)
                        if let gym = snapshot.gym {
                            Label(gym.name, systemImage: "mappin.and.ellipse")
                                .textStyle(Tokens.Typography.control)
                                .foregroundStyle(palette.foregroundMuted)
                                .lineLimit(1)
                        }
                        exercises(snapshot)
                        if !snapshot.records.isEmpty {
                            Label(snapshot.records.count == 1 ? "1 record" : "\(snapshot.records.count) records", systemImage: "arrow.up")
                                .textStyle(Tokens.Typography.control)
                                .foregroundStyle(palette.accent)
                        }
                    } else {
                        Text("Shared from a newer version of Fatigue. Update the app to see it.")
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressRow)
        }
        .padding(.vertical, Tokens.Space.xl)
    }

    /// Up to three exercises, such as "4 sets  Adductors  Technogym", then "and 2 more".
    @ViewBuilder private func exercises(_ snapshot: PostSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            ForEach(Array(snapshot.exercises.prefix(3).enumerated()), id: \.offset) { _, exercise in
                let count = exercise.groups.reduce(0) { $0 + $1.sets.count }
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                    Text("\(count) set\(count == 1 ? "" : "s")")
                        .monospacedDigit()
                        .foregroundStyle(palette.foregroundMuted)
                        .frame(width: Tokens.Size.weightColumn, alignment: .leading)
                    // The brand only shows when it fits whole next to the name; a long name truncates on its own.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                            Text(exercise.name).foregroundStyle(palette.foreground)
                            if let brand = exercise.brand { Text(brand).foregroundStyle(palette.foregroundFaint) }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        Text(exercise.name).foregroundStyle(palette.foreground)
                    }
                }
                .lineLimit(1)
            }
            if snapshot.exercises.count > 3 {
                Text("and \(snapshot.exercises.count - 3) more")
                    .foregroundStyle(palette.foregroundMuted)
            }
        }
        .textStyle(Tokens.Typography.control)
    }
}

/// Who shared a post and when, such as "Jos  @jos · Yesterday". Tapping it opens their profile.
struct PostAuthorLine: View {
    @Environment(\.palette) private var palette
    let post: Post

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            NavigationLink(value: PersonRoute(userId: post.author.userId, handle: post.author.handle, name: post.author.name)) {
                HStack(spacing: Tokens.Space.s) {
                    Avatar(name: post.author.name, photo: nil, size: Tokens.Size.control)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(post.author.name)
                            .textStyle(Tokens.Typography.body)
                            .foregroundStyle(palette.foreground)
                        Text("@\(post.author.handle)")
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                    }
                    .lineLimit(1)
                }
            }
            .buttonStyle(.press)
            .accessibilityHint("Opens their profile")
            Spacer()
            PostWhen(post: post)
        }
    }
}

/// When the workout was, with a lock or friends icon when the post isn't public.
struct PostWhen: View {
    @Environment(\.palette) private var palette
    let post: Post

    var body: some View {
        HStack(spacing: Tokens.Space.xs) {
            if post.visibility != .everyone {
                Image(systemName: post.visibility.systemImage)
                    .imageScale(.small)
                    .accessibilityLabel(post.visibility == .friends ? "Friends only" : "Only you")
            }
            Text(HistoryRow.when(post.startedAt))
        }
        .textStyle(Tokens.Typography.caption)
        .foregroundStyle(palette.foregroundMuted)
    }
}
