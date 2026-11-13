import SwiftUI

/// Your shared workouts and your friends', newest workout first. Pull to refresh; more loads as you scroll.
struct FeedScreen: View {
    @Environment(\.palette) private var palette
    @Environment(SocialStore.self) private var social
    /// Switches to the Profile tab, where you pick a handle and add friends.
    var openProfile: () -> Void = {}
    @State private var path = NavigationPath()
    @State private var error: String?
    @State private var loadingMore = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text("Feed")
                        .textStyle(Tokens.Typography.title)
                        .foregroundStyle(palette.foreground)
                        .padding(.top, Tokens.Space.xl)
                        .padding(.bottom, Tokens.Space.s)
                    if !social.pending.isEmpty {
                        Text(social.pending.count == 1 ? "1 workout waiting to share. It goes out once you're online." : "\(social.pending.count) workouts waiting to share. They go out once you're online.")
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                            .padding(.bottom, Tokens.Space.s)
                    }
                    if let error {
                        Text(error)
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.accent)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, Tokens.Space.s)
                    }
                    Hairline()
                    content
                }
                .padding(.horizontal, Tokens.Space.xxl)
                .padding(.bottom, Tokens.Space.xxxl)
            }
            .background(palette.background)
            .refreshable { await refresh() }
            .toolbar(.hidden, for: .navigationBar)
            .socialPages()
        }
        .task(id: social.myProfile?.userId) {
            if social.myProfile != nil { await refresh() }
            // Debug builds open the first post shared by someone else with `-openPost`, or its author with `-openPerson`, for screenshots.
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if path.isEmpty, let post = social.feed.first(where: { $0.author.userId != social.myProfile?.userId }) {
                if args.contains("-openPost") { path.append(PostRoute(post: post)) }
                if args.contains("-openPerson") { path.append(PersonRoute(userId: post.author.userId, handle: post.author.handle, name: post.author.name)) }
            }
            #endif
        }
        .animation(.standard, value: social.feed)
    }

    @ViewBuilder private var content: some View {
        switch social.profile {
        case .needsHandle:
            empty("Pick a handle on your profile to share workouts and see your friends'.", action: "Go to profile")
        case .unavailable:
            empty("Can't reach Fatigue. Your feed shows up once you're online.")
        case .unknown:
            ProgressView().padding(.vertical, Tokens.Space.xl)
        case .ready:
            if social.feed.isEmpty, social.feedLoaded {
                empty(social.accepted.isEmpty
                      ? "Add friends from your profile to see their workouts here. Workouts you share show here too."
                      : "Nothing shared yet. Turn on sharing when you finish a workout, or share one from your history.",
                      action: social.accepted.isEmpty ? "Find friends" : nil)
            }
            ForEach(social.feed) { post in
                PostCard(post: post)
                    .onAppear { if post.id == social.feed.last?.id { loadMore() } }
                Hairline(soft: true)
            }
            if loadingMore { ProgressView().frame(maxWidth: .infinity).padding(.vertical, Tokens.Space.l) }
        }
    }

    private func empty(_ text: String, action: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            Text(text)
                .textStyle(Tokens.Typography.body)
                .foregroundStyle(palette.foregroundMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action: openProfile) { OutlinedLabel(systemImage: "person", text: action) }
                    .buttonStyle(.press)
            }
        }
        .padding(.vertical, Tokens.Space.xxl)
    }

    private func refresh() async {
        do {
            try await social.refreshFeed()
            withAnimation(.quick) { error = nil }
        } catch {
            withAnimation(.quick) { self.error = error.localizedDescription }
        }
    }

    private func loadMore() {
        guard !loadingMore, social.feedCursor != nil else { return }
        loadingMore = true
        Task {
            defer { loadingMore = false }
            try? await social.loadMoreFeed()
        }
    }
}
