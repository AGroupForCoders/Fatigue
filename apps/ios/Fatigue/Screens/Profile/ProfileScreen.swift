import PhotosUI
import SwiftUI

/// You and your workouts: photo, name, how long you've been lifting, and your history.
/// Export and settings sit at the top right.
struct ProfileScreen: View {
    @Environment(\.palette) private var palette
    @Environment(AuthStore.self) private var auth
    @Environment(WorkoutStore.self) private var store
    @Environment(SocialStore.self) private var social
    /// Launch with `-openSettings` to open settings straight away, for screenshots.
    @State private var showingSettings = ProcessInfo.processInfo.arguments.contains("-openSettings")
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage? = ProfilePhoto.load()
    @State private var path = NavigationPath()
    @State private var editingProfile = false
    @State private var exporting = false
    @State private var exportFile: ExportFile?

    var body: some View {
        NavigationStack(path: $path) {
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: UUID.self) { id in
                    WorkoutDetailScreen(workoutID: id)
                }
                .exercisePages(history: store.history)
                .navigationDestination(for: FriendsRoute.self) { _ in FriendsScreen() }
                .socialPages()
        }
        .task(id: auth.account?.id) {
            // A different account on this phone shouldn't see the last one's friends while loading.
            if social.myProfile?.userId != auth.account?.id { social.reset() }
            await social.load()
            // Debug builds open the friends page with `-openFriends`, for screenshots.
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-openFriends"), path.isEmpty, social.myProfile != nil { path.append(FriendsRoute()) }
            #endif
        }
        .sheet(isPresented: $editingProfile) {
            ProfileEditor(current: social.myProfile)
                .environment(\.palette, palette)
                .environment(social)
        }
        .onAppear {
            // Debug builds open the third workout in history with `-openHistory`, for screenshots.
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-openHistory"), path.isEmpty, store.history.count > 2 {
                path.append(store.history[2].id)
            }
            #endif
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Spacer()
                    Button(action: export) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(exporting ? palette.foregroundFaint : palette.foreground)
                            .frame(width: Tokens.Size.control, height: Tokens.Size.control)
                    }
                    .buttonStyle(.press)
                    .disabled(exporting)
                    .accessibilityLabel("Export your data")
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(palette.foreground)
                            .frame(width: Tokens.Size.control, height: Tokens.Size.control)
                    }
                    .buttonStyle(.press)
                    .accessibilityLabel("Settings")
                }
                .padding(.top, Tokens.Space.s)

                if let account = auth.account {
                    header(account)
                        .padding(.bottom, Tokens.Space.xxxl)
                }

                Text("History")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
                    .padding(.bottom, Tokens.Space.s)
                Hairline()
                if store.history.isEmpty {
                    Text("Workouts you finish show up here.")
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.foregroundMuted)
                        .padding(.vertical, Tokens.Space.xxl)
                }
                ForEach(store.history) { workout in
                    NavigationLink(value: workout.id) {
                        HistoryRow(workout: workout)
                    }
                    .buttonStyle(.pressRow)
                    Hairline(soft: true)
                }
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.bottom, Tokens.Space.xxxl)
        }
        .background(palette.background)
        .sheet(isPresented: $showingSettings) {
            SettingsScreen()
                .environment(\.palette, palette)
        }
        .sheet(item: $exportFile) { file in
            ShareSheet(items: [file.url])
                .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let saved = ProfilePhoto.save(data) {
                    withAnimation(.standard) { photo = saved }
                    // Friends see it once it's up. If that fails, it goes up the next time the profile loads.
                    if let jpeg = ProfilePhoto.data() { try? await social.setProfilePhoto(jpeg) }
                }
                photoItem = nil
            }
        }
    }

    /// Writes every finished workout to a CSV, one row per set, and opens the share sheet with it.
    /// The rows are gathered here, where the model lives; the file is written off the main actor.
    private func export() {
        guard !exporting else { return }
        exporting = true
        let rows = store.exportRows()
        Task {
            defer { exporting = false }
            do {
                let url = try await Task.detached(priority: .userInitiated) { try DataExport.write(rows, on: .now) }.value
                exportFile = ExportFile(url: url)
            } catch {
                #if DEBUG
                print("Export failed: \(error)")
                #endif
            }
        }
    }

    private func header(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Avatar(name: account.name, photo: photo)
            }
            .buttonStyle(.press)
            .accessibilityLabel(photo == nil ? "Add a profile photo" : "Change profile photo")

            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text(account.name)
                    .textStyle(Tokens.Typography.title)
                    .foregroundStyle(palette.foreground)
                Text("Lifting since \(account.createdAt.formatted(.dateTime.month(.wide).year()))  ·  \(store.history.count) workout\(store.history.count == 1 ? "" : "s")")
                    .textStyle(Tokens.Typography.body)
                    .foregroundStyle(palette.foregroundMuted)
                if let bio = social.myProfile?.bio {
                    Text(bio)
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            socialRow
        }
        .animation(.standard, value: social.profile)
    }

    /// Your handle and friends once you have a handle, or a prompt to pick one. Left out while the API can't be reached.
    @ViewBuilder private var socialRow: some View {
        switch social.profile {
        case .ready(let profile):
            // Side by side when they fit, one above the other for a long handle or a lot of requests.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tokens.Space.s) { profileButtons(profile) }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: Tokens.Space.s) { profileButtons(profile) }
            }
        case .needsHandle:
            Button { editingProfile = true } label: {
                OutlinedLabel(systemImage: "at", text: "Pick a handle")
            }
            .buttonStyle(.press)
        case .unknown, .unavailable:
            EmptyView()
        }
    }

    @ViewBuilder private func profileButtons(_ profile: MyProfile) -> some View {
        Button { editingProfile = true } label: {
            OutlinedLabel(systemImage: profile.defaultVisibility.systemImage, text: "@\(profile.handle)")
        }
        .buttonStyle(.press)
        .accessibilityLabel("Edit profile, @\(profile.handle)")
        NavigationLink(value: FriendsRoute()) {
            OutlinedLabel(systemImage: "person.2", text: friendsText)
        }
        .buttonStyle(.press)
    }

    private var friendsText: String {
        let friends = social.accepted.count
        let requests = social.incoming.count
        let text = friends == 1 ? "1 friend" : "\(friends) friends"
        return requests == 0 ? text : "\(text)  ·  \(requests) request\(requests == 1 ? "" : "s")"
    }
}

/// A round profile photo, or your first initial when there's no photo yet.
struct Avatar: View {
    @Environment(\.palette) private var palette
    let name: String
    let photo: UIImage?
    /// Someone else's photo, loaded from the API's link. Ignored when `photo` is there.
    var url: URL? = nil
    var size: CGFloat = Tokens.Size.primaryButton + Tokens.Space.xxl

    var body: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .quick)) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        initial
                    }
                }
            } else {
                initial
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(palette.borderControl, lineWidth: Tokens.Size.line))
    }

    private var initial: some View {
        ZStack {
            palette.surface
            Text(name.first.map { String($0).uppercased() } ?? "")
                .textStyle(Tokens.Typography.exerciseName)
                .foregroundStyle(palette.foregroundMuted)
        }
    }
}

/// Your profile photo, kept as a small JPEG on this phone so it shows straight away. A copy goes up to the API for friends.
nonisolated enum ProfilePhoto {
    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "profile-photo.jpg")
    }

    static func load() -> UIImage? {
        UIImage(contentsOfFile: url.path(percentEncoded: false))
    }

    /// The saved JPEG, as it's uploaded.
    static func data() -> Data? {
        try? Data(contentsOf: url)
    }

    /// Shrinks the picked photo to 512 points across and saves it. Returns the saved image.
    static func save(_ data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let side: CGFloat = 512
        let scale = side / min(image.size.width, image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return nil }
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        guard (try? jpeg.write(to: url, options: .atomic)) != nil else { return nil }
        return resized
    }

    /// Removes the photo, such as when you sign out, so the next account on this phone doesn't get it.
    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
