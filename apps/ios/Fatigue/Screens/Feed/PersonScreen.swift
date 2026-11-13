import SwiftUI

/// Someone's profile: name, handle, bio, where you stand with them, and the shared workouts you can see.
struct PersonScreen: View {
    @Environment(\.palette) private var palette
    @Environment(SocialStore.self) private var social
    let route: PersonRoute
    @State private var person: Person?
    @State private var posts: [Post] = []
    @State private var cursor: String?
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, Tokens.Space.xxl)
                if let error {
                    Text(error)
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.accent)
                        .padding(.bottom, Tokens.Space.s)
                }
                Text("Shared workouts")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
                    .padding(.bottom, Tokens.Space.s)
                Hairline()
                if loaded, posts.isEmpty {
                    Text(emptyText)
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.foregroundMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, Tokens.Space.xxl)
                }
                ForEach(posts) { post in
                    PostCard(post: post, showsAuthor: false)
                        .onAppear { if post.id == posts.last?.id { Task { await loadMore() } } }
                    Hairline(soft: true)
                }
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.top, Tokens.Space.s)
            .padding(.bottom, Tokens.Space.xxxl)
        }
        .background(palette.background)
        .toolbarRole(.editor)
        .refreshable { await load() }
        .task { await load() }
        .animation(.standard, value: posts)
        .animation(.standard, value: person)
    }

    private var relation: Relation {
        social.friends.first { $0.userId == route.userId }?.relation ?? person?.relation ?? (route.userId == social.myProfile?.userId ? .me : .none)
    }

    private var emptyText: String {
        switch relation {
        case .me: "Workouts you share show up here."
        case .friends: "\(route.name) hasn't shared a workout yet."
        default: "\(route.name) hasn't shared anything public. Add them as a friend to see workouts shared with friends."
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            Avatar(name: route.name, photo: nil, url: person?.photoUrl)
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text(route.name)
                    .textStyle(Tokens.Typography.title)
                    .foregroundStyle(palette.foreground)
                Text("@\(route.handle)")
                    .textStyle(Tokens.Typography.body)
                    .foregroundStyle(palette.foregroundMuted)
                if let bio = person?.bio {
                    Text(bio)
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            relationButton
        }
    }

    @ViewBuilder private var relationButton: some View {
        switch relation {
        case .none:
            PrimaryButton(title: "Add friend", compact: true) { add() }
        case .incoming:
            PrimaryButton(title: "Accept request", compact: true) { add() }
        case .outgoing:
            OutlinedLabel(text: "Requested", isMuted: true)
        case .friends:
            OutlinedLabel(systemImage: "checkmark", text: "Friends", isMuted: true)
        case .me:
            EmptyView()
        }
    }

    private func add() {
        guard let person else { return }
        Task {
            do {
                let relation = try await social.add(person)
                self.person?.relation = relation
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func load() async {
        do {
            async let found = social.person(handle: route.handle)
            async let page = social.posts(by: route.userId)
            let (person, firstPage) = try await (found, page)
            self.person = person
            posts = firstPage.posts
            cursor = firstPage.nextCursor
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    private func loadMore() async {
        guard let current = cursor else { return }
        cursor = nil
        guard let page = try? await social.posts(by: route.userId, cursor: current) else { cursor = current; return }
        let known = Set(posts.map(\.id))
        posts += page.posts.filter { !known.contains($0.id) }
        cursor = page.nextCursor
    }
}
