import SwiftUI

/// Pushes the friends page from the Profile tab.
struct FriendsRoute: Hashable {}

/// Your friends and requests, and a search by handle to add people.
/// While the search has text, its results replace the lists.
struct FriendsScreen: View {
    @Environment(\.palette) private var palette
    @Environment(SocialStore.self) private var social
    @State private var query = ""
    @State private var results: [Person] = []
    @State private var searching = false
    @State private var error: String?
    @State private var confirmingRemove: FriendRow?

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Friends")
                    .textStyle(Tokens.Typography.title)
                    .foregroundStyle(palette.foreground)
                searchField
                    .padding(.top, Tokens.Space.l)
                if let error {
                    Text(error)
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Tokens.Space.m)
                        .transition(.opacity)
                }
                if isSearching { searchResults } else { lists }
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.top, Tokens.Space.s)
            .padding(.bottom, Tokens.Space.xxxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(palette.background)
        .toolbarRole(.editor)
        .refreshable { await social.load() }
        .animation(.standard, value: social.friends)
        .animation(.standard, value: results)
        .animation(.standard, value: isSearching)
        .task(id: query) {
            // Waits for typing to pause, so every letter doesn't send a search.
            guard isSearching else { results = []; return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            do {
                let found = try await social.search(query)
                if !Task.isCancelled { results = found }
            } catch {
                show(error)
            }
        }
        .confirmationDialog("Remove @\(confirmingRemove?.handle ?? "")?", isPresented: .init(
            get: { confirmingRemove != nil }, set: { if !$0 { confirmingRemove = nil } }
        ), titleVisibility: .visible) {
            Button("Remove friend", role: .destructive) {
                if let row = confirmingRemove { run { try await social.remove(row) } }
            }
        } message: {
            Text("They won't be told. Either of you can add the other again.")
        }
    }

    private var searchField: some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(palette.foregroundMuted)
            TextField("", text: $query, prompt: Text("Find people by handle").foregroundStyle(palette.foregroundFaint))
                .textStyle(Tokens.Typography.body)
                .foregroundStyle(palette.foreground)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
        }
        .padding(.horizontal, Tokens.Space.m)
        .frame(height: Tokens.Size.primaryButton)
        .background(palette.surface, in: .rect(cornerRadius: Tokens.Radius.control))
    }

    @ViewBuilder private var searchResults: some View {
        if searching, results.isEmpty {
            ProgressView().padding(.vertical, Tokens.Space.l)
        } else if results.isEmpty {
            message("Nobody with a handle starting \u{201C}\(query.trimmingCharacters(in: .whitespaces))\u{201D}.")
        }
        ForEach(results) { person in
            row(name: person.name, handle: person.handle) { searchAction(person) }
            Hairline(soft: true)
        }
    }

    @ViewBuilder private var lists: some View {
        if social.friends.isEmpty {
            message("Search for a friend's handle to add them. When they accept, you'll see each other's shared workouts.")
        }
        if !social.incoming.isEmpty {
            caption("Requests")
            ForEach(social.incoming) { request in
                row(name: request.name, handle: request.handle) {
                    HStack(spacing: Tokens.Space.s) {
                        Button { run { try await social.remove(request) } } label: {
                            OutlinedLabel(text: "Decline", isMuted: true)
                        }
                        .buttonStyle(.press)
                        PrimaryButton(title: "Accept", compact: true) { run { try await social.accept(request) } }
                    }
                }
                Hairline(soft: true)
            }
        }
        if !social.accepted.isEmpty {
            caption("Friends")
            ForEach(social.accepted) { friend in
                row(name: friend.name, handle: friend.handle) {
                    Menu {
                        Button("Remove friend", systemImage: "person.badge.minus", role: .destructive) { confirmingRemove = friend }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(palette.foregroundMuted)
                            .frame(width: Tokens.Size.control, height: Tokens.Size.control)
                    }
                    .accessibilityLabel("Options for @\(friend.handle)")
                }
                Hairline(soft: true)
            }
        }
        if !social.outgoing.isEmpty {
            caption("Sent")
            ForEach(social.outgoing) { request in
                row(name: request.name, handle: request.handle) {
                    Button { run { try await social.remove(request) } } label: {
                        OutlinedLabel(text: "Cancel", isMuted: true)
                    }
                    .buttonStyle(.press)
                    .accessibilityLabel("Cancel request to @\(request.handle)")
                }
                Hairline(soft: true)
            }
        }
    }

    /// The button on a search result, which depends on where you stand with them.
    @ViewBuilder private func searchAction(_ person: Person) -> some View {
        let relation = social.friends.first { $0.userId == person.userId }?.relation ?? person.relation
        switch relation {
        case .none:
            PrimaryButton(title: "Add", compact: true) { add(person) }
        case .incoming:
            PrimaryButton(title: "Accept", compact: true) { add(person) }
        case .outgoing:
            OutlinedLabel(text: "Requested", isMuted: true)
        case .friends:
            OutlinedLabel(systemImage: "checkmark", text: "Friends", isMuted: true)
        case .me:
            EmptyView()
        }
    }

    private func add(_ person: Person) {
        run {
            let relation = try await social.add(person)
            if let index = results.firstIndex(of: person) { results[index].relation = relation }
        }
    }

    private func row(name: String, handle: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: Tokens.Space.m) {
            Avatar(name: name, photo: nil, size: Tokens.Size.control)
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(name)
                    .textStyle(Tokens.Typography.body)
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)
                Text("@\(handle)")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: Tokens.Space.s)
            trailing()
        }
        .frame(minHeight: Tokens.Size.setRow)
        .padding(.vertical, Tokens.Space.s)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .textStyle(Tokens.Typography.caption)
            .foregroundStyle(palette.foregroundMuted)
            .padding(.top, Tokens.Space.xl)
            .padding(.bottom, Tokens.Space.xs)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .textStyle(Tokens.Typography.body)
            .foregroundStyle(palette.foregroundMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, Tokens.Space.xl)
    }

    /// Runs a friend action and shows what went wrong, if anything, above the list.
    private func run(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                withAnimation(.quick) { error = nil }
            } catch {
                show(error)
            }
        }
    }

    private func show(_ error: Error) {
        withAnimation(.quick) { self.error = error.localizedDescription }
    }
}
