import PhotosUI
import SwiftUI

/// You and your workouts: photo, name, how long you've been lifting, and your history.
/// Export and settings sit at the top right.
struct ProfileScreen: View {
    @Environment(\.palette) private var palette
    @Environment(AuthStore.self) private var auth
    @Environment(WorkoutStore.self) private var store
    /// Launch with `-openSettings` to open settings straight away, for screenshots.
    @State private var showingSettings = ProcessInfo.processInfo.arguments.contains("-openSettings")
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage? = ProfilePhoto.load()
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: UUID.self) { id in
                    WorkoutDetailScreen(workoutID: id)
                }
        }
        .onAppear {
            // Debug builds open the third workout in history with `-openHistory`, for screenshots.
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-openHistory"), path.isEmpty, store.history.count > 2 {
                path = [store.history[2].id]
            }
            #endif
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Spacer()
                    // Export comes later. The button is here so the layout is settled.
                    Button {} label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(palette.foregroundFaint)
                            .frame(width: Tokens.Size.control, height: Tokens.Size.control)
                    }
                    .buttonStyle(.press)
                    .accessibilityLabel("Export your data, coming soon")
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
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let saved = ProfilePhoto.save(data) {
                    withAnimation(.standard) { photo = saved }
                }
                photoItem = nil
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
            }
        }
    }
}

/// A round profile photo, or your first initial when there's no photo yet.
struct Avatar: View {
    @Environment(\.palette) private var palette
    let name: String
    let photo: UIImage?
    var size: CGFloat = Tokens.Size.primaryButton + Tokens.Space.xxl

    var body: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                palette.surface
                Text(name.first.map { String($0).uppercased() } ?? "")
                    .textStyle(Tokens.Typography.exerciseName)
                    .foregroundStyle(palette.foregroundMuted)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(palette.borderControl, lineWidth: Tokens.Size.line))
    }
}

/// The profile photo, kept as a small JPEG on this phone. Uploading it comes with sync.
nonisolated enum ProfilePhoto {
    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "profile-photo.jpg")
    }

    static func load() -> UIImage? {
        UIImage(contentsOfFile: url.path(percentEncoded: false))
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
